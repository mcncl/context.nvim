-- Streaming handler for buffer updates
local M = {}

local job = require("context.job")
local providers = require("context.providers")

-- Active stream state
local state = {
  bufnr = nil,
  accumulated_text = "",
  context = nil, -- Store context to apply at stream end
}

-- Clear the current state
local function clear_state()
  state = {
    bufnr = nil,
    accumulated_text = "",
    context = nil,
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
  local start_line = context.start_line - 1 -- Convert to 0-indexed
  local end_line = context.end_line - 1
  local start_col = context.start_col - 1
  local end_col = context.end_col

  -- Get content before and after selection
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local before_text = ""
  local after_text = ""

  if #lines > 0 then
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
  state.context = context -- Store context, don't delete yet

  -- Build the request
  local request = provider.build_request(prompt, context.text, context.filetype, config)

  -- Start the job (buffer will be prepared when first chunk arrives)
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
