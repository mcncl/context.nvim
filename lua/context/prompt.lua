-- Prompt UI for context.nvim
local M = {}

local config = require("context.config")
local selection = require("context.selection")
local stream = require("context.stream")
local files = require("context.files")
local completion = require("context.completion")
local references = require("context.references")

local chat_winid

-- Show the prompt UI
-- @param force_mode string|nil Force a specific context mode ("visual", "line", "file")
function M.show(force_mode)
  local cfg = config.get()
  local ui_config = cfg.ui
  local chat = cfg.response_mode ~= "edit"

  if chat and chat_winid and vim.api.nvim_win_is_valid(chat_winid) then
    vim.api.nvim_set_current_win(chat_winid)
    vim.cmd("startinsert!")
    return
  end
  if stream.is_active() then
    vim.notify("Context: finish or cancel the active request first", vim.log.levels.WARN)
    return
  end

  -- Get context first to show mode in prompt
  local context = selection.get_context(force_mode)
  local mode_indicator = string.format("[%s]", context.mode)

  -- Calculate window dimensions
  local width = math.max(1, math.min(ui_config.prompt_width or 60, vim.o.columns - 4))
  local height = chat and (ui_config.chat_height or 20) or (ui_config.prompt_height or 3)
  height = math.max(1, math.min(height, vim.o.lines - 4))

  -- Create floating window
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "prompt", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  if chat then
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
  end

  -- Calculate position (centered)
  local win_width = vim.api.nvim_get_option_value("columns", {})
  local win_height = vim.api.nvim_get_option_value("lines", {})
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = string.format(" %s %s ", ui_config.prompt_title or "Context", mode_indicator),
    title_pos = "center",
  }

  -- Start async file discovery for @file completion
  files.load_files()

  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)
  vim.api.nvim_set_option_value("wrap", true, { win = winid })
  vim.api.nvim_set_option_value("linebreak", true, { win = winid })
  if chat then
    chat_winid = winid
  end

  local history = {}
  local busy = false

  local function close()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  if chat then
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        if busy then
          stream.cancel()
        end
        chat_winid = nil
      end,
    })
  end

  -- Set up prompt
  vim.fn.prompt_setprompt(bufnr, "> ")

  -- Set up @file completion on this buffer
  completion.setup_buffer(bufnr)

  -- Handle submit
  vim.fn.prompt_setcallback(bufnr, function(text)
    if chat then
      if not vim.api.nvim_buf_is_valid(bufnr) or not text or text:match("^%s*$") then
        return
      end
      if busy then
        return
      end

      local resolved = references.resolve(text, context)
      local response_start = vim.api.nvim_buf_line_count(bufnr) - 1
      vim.api.nvim_buf_set_lines(bufnr, response_start, response_start, false, { "", "" })
      response_start = response_start + 1
      local partial = ""
      busy = true

      local function display(value)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        local lines = vim.split(value, "\n", { plain = true })
        table.insert(lines, "")
        vim.api.nvim_buf_set_lines(bufnr, response_start, -2, false, lines)
      end

      local ok, started = pcall(
        stream.start,
        resolved.clean_prompt,
        resolved.contexts,
        cfg.provider,
        config.get_provider_config(cfg.provider),
        {
          bufnr = bufnr,
          line = response_start - 1,
          system_prompt = cfg.chat_system_prompt,
          history = history,
          on_chunk = function(value)
            partial = value
            display(value)
          end,
          on_done = function(value)
            busy = false
            table.insert(history, {
              role = "user",
              content = require("context.providers").format_contexts(resolved.clean_prompt, resolved.contexts),
            })
            table.insert(history, { role = "assistant", content = value })
          end,
          on_error = function(err)
            busy = false
            display(partial .. "\n\nError: " .. err)
          end,
          on_cancel = function()
            busy = false
            display(partial .. "\n\n[Cancelled]")
          end,
        }
      )
      if not ok or not started then
        busy = false
        display("Error: " .. (ok and "Request could not start" or tostring(started)))
      end
      return
    end

    -- Close the prompt window silently
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end

    -- Clear any pending messages and redraw
    vim.cmd("redraw")

    -- Don't proceed if empty prompt
    if not text or text == "" then
      return
    end

    -- Get fresh context in case buffer changed
    local ctx = selection.get_context(force_mode)

    -- Resolve @file references in the prompt
    local resolved = references.resolve(text, ctx)

    -- Get provider config
    local provider_name = cfg.provider
    local provider_config = config.get_provider_config(provider_name)

    -- Start streaming with error handling
    local ok, err = pcall(stream.start, resolved.clean_prompt, resolved.contexts, provider_name, provider_config)
    if not ok then
      vim.notify("Context: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)

  -- Handle cancel (Esc)
  vim.keymap.set("i", "<Esc>", function()
    if chat then
      vim.cmd("stopinsert")
    else
      close()
    end
  end, { buffer = bufnr, noremap = true })

  -- Handle Ctrl-C cancel
  vim.keymap.set("i", "<C-c>", function()
    if chat then
      stream.cancel()
    else
      close()
    end
  end, { buffer = bufnr, noremap = true })

  if chat then
    vim.keymap.set("n", "q", close, { buffer = bufnr, desc = "Context: Close chat" })
    vim.keymap.set("n", "<CR>", function()
      vim.api.nvim_win_set_cursor(winid, { vim.api.nvim_buf_line_count(bufnr), 0 })
      vim.cmd("startinsert!")
    end, { buffer = bufnr, desc = "Context: Reply" })
    vim.fn.prompt_setinterrupt(bufnr, function()
      stream.cancel()
    end)
  end

  -- Handle <CR>: accept completion if popup visible, otherwise submit prompt
  vim.keymap.set("i", "<CR>", function()
    if vim.fn.pumvisible() == 1 then
      return vim.api.nvim_replace_termcodes("<C-y>", true, false, true)
    end
    if busy then
      return ""
    end
    return vim.api.nvim_replace_termcodes("<CR>", true, false, true)
  end, { buffer = bufnr, noremap = true, expr = true })

  -- Start in insert mode
  vim.cmd("startinsert")
end

-- Show prompt with visual selection context
function M.show_visual()
  -- First, exit visual mode to set the '< and '> marks
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    -- Use <Esc> to exit visual mode and set marks
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end
  M.show("visual")
end

-- Show prompt with line context
function M.show_line()
  M.show("line")
end

-- Show prompt with file context
function M.show_file()
  M.show("file")
end

return M
