-- Job management for streaming HTTP requests and CLI providers
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
-- @param request table HTTP { url, headers, body } or CLI { command, stdin, settings }
-- @param callbacks table { on_chunk, on_done, on_error }
-- @return job_id number
function M.start(request, callbacks)
  -- Cancel any existing job
  M.cancel()

  local args = request.command and vim.deepcopy(request.command) or build_curl_args(request)
  if vim.fn.executable(args[1]) ~= 1 then
    if callbacks.on_error then
      callbacks.on_error("Executable not found: " .. args[1])
    end
    return nil
  end

  local directory
  if request.settings then
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p", 448)
    local settings_file = directory .. "/settings.json"
    vim.fn.writefile({ vim.fn.json_encode(request.settings) }, settings_file)
    vim.list_extend(args, { "--settings-file", settings_file })
  end

  local function cleanup()
    if directory then
      vim.fn.delete(directory, "rf")
    end
  end

  local stdout_buffer = ""
  local stderr_buffer = ""

  local job_id
  local ok, result = pcall(vim.fn.jobstart, args, {
    cwd = directory,
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
        if request.command then
          -- CLI diagnostics on stderr are not failures unless the process fails.
          stderr_buffer = stderr_buffer .. err
        elseif err ~= "" then
          vim.schedule(function()
            callbacks.on_error(err)
          end)
        end
      end
    end,

    on_exit = function(_, exit_code, _)
      if M.active_job == job_id then
        M.active_job = nil
      end
      cleanup()

      -- Process any remaining data in buffer
      if stdout_buffer ~= "" and callbacks.on_chunk then
        local remaining = stdout_buffer
        vim.schedule(function()
          callbacks.on_chunk(remaining)
        end)
      end

      if request.command and exit_code ~= 0 and stderr_buffer ~= "" and callbacks.on_error then
        vim.schedule(function()
          callbacks.on_error(stderr_buffer)
        end)
      end
      if callbacks.on_done then
        vim.schedule(function()
          callbacks.on_done(exit_code)
        end)
      end
    end,
  })
  job_id = ok and result or -1

  if job_id <= 0 then
    cleanup()
    if callbacks.on_error then
      callbacks.on_error("Failed to start " .. args[1] .. " job: " .. tostring(result))
    end
    return nil
  end

  M.active_job = job_id
  if request.stdin then
    vim.fn.chansend(job_id, request.stdin)
    vim.fn.chanclose(job_id, "stdin")
  end
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
