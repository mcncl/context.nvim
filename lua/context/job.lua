-- Curl job management for streaming HTTP requests
local M = {}

-- Active job handle
M.active_job = nil

-- Build curl arguments for streaming request
local function build_curl_args(request)
  local args = {
    "curl",
    "--silent",
    "--show-error", -- Show errors even in silent mode
    "--no-buffer",
    "-N", -- Disable buffering for real-time streaming
    "-X", "POST",
    request.url,
  }

  -- Add headers
  for key, value in pairs(request.headers) do
    table.insert(args, "-H")
    table.insert(args, key .. ": " .. value)
  end

  -- Add body
  table.insert(args, "-d")
  table.insert(args, request.body)

  return args
end

-- Start a streaming request
-- @param request table { url, headers, body }
-- @param callbacks table { on_chunk, on_done, on_error }
-- @return job_id number
function M.start(request, callbacks)
  -- Cancel any existing job
  M.cancel()

  local args = build_curl_args(request)

  local stdout_buffer = ""

  local job_id = vim.fn.jobstart(args, {
    on_stdout = function(_, data, _)
      if not data then
        return
      end

      -- Accumulate data - join with newlines since data is an array of lines
      stdout_buffer = stdout_buffer .. table.concat(data, "\n")

      -- Process complete lines (SSE events end with newline)
      while true do
        local newline_pos = stdout_buffer:find("\n")
        if not newline_pos then
          break
        end

        local line = stdout_buffer:sub(1, newline_pos - 1)
        stdout_buffer = stdout_buffer:sub(newline_pos + 1)

        -- Skip empty lines (SSE event separators)
        if line ~= "" and callbacks.on_chunk then
          vim.schedule(function()
            callbacks.on_chunk(line)
          end)
        end
      end
    end,

    on_stderr = function(_, data, _)
      if data and callbacks.on_error then
        local err = table.concat(data, "\n")
        if err ~= "" then
          vim.schedule(function()
            callbacks.on_error(err)
          end)
        end
      end
    end,

    on_exit = function(_, exit_code, _)
      M.active_job = nil

      -- Process any remaining data in buffer
      if stdout_buffer ~= "" and callbacks.on_chunk then
        vim.schedule(function()
          callbacks.on_chunk(stdout_buffer)
        end)
      end

      if callbacks.on_done then
        vim.schedule(function()
          callbacks.on_done(exit_code)
        end)
      end
    end,
  })

  if job_id <= 0 then
    if callbacks.on_error then
      callbacks.on_error("Failed to start curl job")
    end
    return nil
  end

  M.active_job = job_id
  return job_id
end

-- Cancel the active job
function M.cancel()
  if M.active_job then
    vim.fn.jobstop(M.active_job)
    M.active_job = nil
    return true
  end
  return false
end

-- Check if a job is currently running
function M.is_running()
  return M.active_job ~= nil
end

return M
