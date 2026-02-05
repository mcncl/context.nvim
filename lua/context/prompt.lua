-- Prompt UI for context.nvim
local M = {}

local config = require("context.config")
local selection = require("context.selection")
local stream = require("context.stream")

-- Show the prompt UI
-- @param force_mode string|nil Force a specific context mode ("visual", "line", "file")
function M.show(force_mode)
  local cfg = config.get()
  local ui_config = cfg.ui

  -- Get context first to show mode in prompt
  local context = selection.get_context(force_mode)
  local mode_indicator = string.format("[%s]", context.mode)

  -- Calculate window dimensions
  local width = ui_config.prompt_width or 60
  local height = ui_config.prompt_height or 3

  -- Create floating window
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "prompt", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })

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

  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Set up prompt
  vim.fn.prompt_setprompt(bufnr, "> ")

  -- Handle submit
  vim.fn.prompt_setcallback(bufnr, function(text)
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

    -- Get provider config
    local provider_name = cfg.provider
    local provider_config = config.get_provider_config(provider_name)

    -- Start streaming with error handling
    local ok, err = pcall(stream.start, text, ctx, provider_name, provider_config)
    if not ok then
      vim.notify("Context: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)

  -- Handle cancel (Esc)
  vim.keymap.set("i", "<Esc>", function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end, { buffer = bufnr, noremap = true })

  -- Handle Ctrl-C cancel
  vim.keymap.set("i", "<C-c>", function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end, { buffer = bufnr, noremap = true })

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
