-- Streaming handler for buffer updates
local M = {}

local job = require("context.job")
local providers = require("context.providers")

-- Namespace for extmarks
local ns_id = nil

local function ensure_namespace()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("context_stream")
  end
  return ns_id
end

-- Active stream state
local state = {
  bufnr = nil,
  accumulated_text = "",
  context = nil, -- Original context for mode/col info
  start_mark = nil, -- Extmark tracking selection start
  end_mark = nil, -- Extmark tracking selection end
}

-- Clear the current state
local function clear_state()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, state.bufnr, ensure_namespace(), 0, -1)
  end

  state = {
    bufnr = nil,
    accumulated_text = "",
    context = nil,
    start_mark = nil,
    end_mark = nil,
  }
end

-- Place extmarks at selection boundaries to track position through edits
local function place_marks(bufnr, context)
  local ns = ensure_namespace()
  local start_line = context.start_line - 1 -- 0-indexed
  local end_line = context.end_line - 1

  state.start_mark = vim.api.nvim_buf_set_extmark(bufnr, ns, start_line, 0, {
    right_gravity = false, -- Stays put if text is inserted at this position
  })

  -- End mark: place at the end of the last selected line
  local end_lines = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)
  local end_col = end_lines[1] and #end_lines[1] or 0

  state.end_mark = vim.api.nvim_buf_set_extmark(bufnr, ns, end_line, end_col, {
    right_gravity = true, -- Moves right if text is inserted at this position
  })
end

-- Read current positions from extmarks
local function get_mark_positions()
  if not state.bufnr or not state.start_mark or not state.end_mark then
    return nil
  end

  local ns = ensure_namespace()
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(state.bufnr, ns, state.start_mark, {})
  local end_pos = vim.api.nvim_buf_get_extmark_by_id(state.bufnr, ns, state.end_mark, {})

  if not start_pos or #start_pos == 0 or not end_pos or #end_pos == 0 then
    return nil
  end

  return {
    start_line = start_pos[1], -- 0-indexed
    end_line = end_pos[1],     -- 0-indexed
  }
end

-- Accumulate streaming content (no buffer updates during streaming)
local function update_buffer(new_text)
  if not new_text or new_text == "" then
    return
  end

  -- Just accumulate the text - we'll apply it at the end
  state.accumulated_text = state.accumulated_text .. new_text
end

-- Strip markdown code fences if the LLM included them despite instructions
local function strip_markdown_fences(text)
  -- Remove opening fence (```lang or ```)
  text = text:gsub("^%s*```[%w]*%s*\n", "")
  -- Remove closing fence
  text = text:gsub("\n%s*```%s*$", "")
  return text
end

-- Apply the accumulated result to the buffer (called once at stream end)
local function apply_result()
  if state.accumulated_text == "" then
    return
  end

  -- Clean up any markdown fences the LLM might have included
  state.accumulated_text = strip_markdown_fences(state.accumulated_text)

  local context = state.context
  if not context then
    return
  end

  local bufnr = state.bufnr

  -- Read actual positions from extmarks (safe against edits)
  local marks = get_mark_positions()
  if not marks then
    vim.notify("Context: lost track of selection, aborting", vim.log.levels.WARN)
    return
  end

  local start_line = marks.start_line
  local end_line = marks.end_line

  -- Get content before and after selection
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local before_text = ""
  local after_text = ""

  if #lines > 0 then
    local start_col = context.start_col - 1
    local end_col = context.end_col
    before_text = string.sub(lines[1], 1, start_col)
    after_text = string.sub(lines[#lines], end_col + 1)
  end

  -- For line mode or file mode, no before/after text
  if context.mode == "line" or context.mode == "file" or context.visual_mode == "V" then
    before_text = ""
    after_text = ""
  end

  -- Build the final content
  local content_lines = vim.split(state.accumulated_text, "\n", { plain = true })
  content_lines[1] = before_text .. content_lines[1]
  content_lines[#content_lines] = content_lines[#content_lines] .. after_text

  -- Replace the selection with the result
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, content_lines)
end

-- Start streaming a request
-- @param prompt string The user's prompt
-- @param context table The context from selection.get_context()
-- @param provider_name string The provider to use
-- @param config table The provider config
function M.start(prompt, context, provider_name, config)
  -- Clear any existing state
  clear_state()

  -- Get the provider
  local provider = providers.get(provider_name)
  state.bufnr = vim.api.nvim_get_current_buf()
  state.context = context

  -- Place extmarks to track selection through edits
  place_marks(state.bufnr, context)

  -- Build the request
  local request = provider.build_request(prompt, context.text, context.filetype, config)

  -- Start the job
  local debug = vim.g.context_debug or false

  job.start(request, {
    on_chunk = function(chunk)
      if debug then
        vim.notify("Context chunk: " .. chunk:sub(1, 100), vim.log.levels.DEBUG)
      end

      -- Check for API error responses (JSON with "error" field)
      if chunk:match('^%s*{') and chunk:match('"error"') then
        local ok, parsed = pcall(vim.fn.json_decode, chunk)
        if ok and parsed.error then
          local msg = parsed.error.message or vim.fn.json_encode(parsed.error)
          vim.notify("Context API error: " .. msg, vim.log.levels.ERROR)
          return
        end
      end

      local text = provider.parse_stream_chunk(chunk)
      if debug and text then
        vim.notify("Context parsed: " .. text:sub(1, 50), vim.log.levels.DEBUG)
      end
      if text then
        update_buffer(text)
      end
    end,

    on_error = function(err)
      vim.notify("Context error: " .. err, vim.log.levels.ERROR)
    end,

    on_done = function(exit_code)
      if debug then
        vim.notify("Context job finished with exit code: " .. exit_code, vim.log.levels.DEBUG)
      end
      if exit_code == 0 then
        -- Success - apply the accumulated result
        apply_result()
      elseif exit_code ~= 143 then -- 143 is SIGTERM from cancel
        vim.notify("Context request failed with exit code: " .. exit_code, vim.log.levels.ERROR)
      end
      clear_state()
    end,
  })
end

-- Cancel the current stream
function M.cancel()
  local was_running = job.cancel()
  if was_running then
    vim.notify("Context request cancelled", vim.log.levels.INFO)
  end
  clear_state()
  return was_running
end

-- Check if a stream is currently active
function M.is_active()
  return job.is_running()
end

return M
