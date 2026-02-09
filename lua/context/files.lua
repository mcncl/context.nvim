-- Async file discovery and reading for @file references
local M = {}

local config = require("context.config")

-- Module-level cache (persists across prompts in same session)
local file_cache = nil
local loading = false

-- Read a file with safety checks
-- Returns content string on success, or nil + error message on failure
function M.read_file(path)
  local cfg = config.get()
  local max_size = (cfg.files and cfg.files.max_file_size) or 102400

  -- Check existence
  if vim.fn.filereadable(path) ~= 1 then
    return nil, "file not found: " .. path
  end

  -- Check size
  local size = vim.fn.getfsize(path)
  if size < 0 then
    return nil, "cannot read file: " .. path
  end
  if size > max_size then
    return nil, string.format("file too large (%d bytes, max %d): %s", size, max_size, path)
  end

  -- Read the file
  local lines = vim.fn.readfile(path, "b", 1000)
  if not lines or #lines == 0 then
    return nil, "empty file: " .. path
  end

  -- Binary detection: check for null bytes in first 512 bytes
  local sample = {}
  for i = 1, math.min(#lines, 5) do
    sample[i] = lines[i]
  end
  local first_chunk = table.concat(sample, "\n")
  if first_chunk:sub(1, 512):find("\0") then
    return nil, "binary file: " .. path
  end

  -- Read full file content
  local content_lines = vim.fn.readfile(path)
  if not content_lines then
    return nil, "failed to read file: " .. path
  end

  return table.concat(content_lines, "\n")
end

-- Detect filetype from a path
function M.detect_filetype(path)
  if vim.filetype and vim.filetype.match then
    local ok, ft = pcall(vim.filetype.match, { filename = path })
    if ok and ft then
      return ft
    end
  end
  local ext = vim.fn.fnamemodify(path, ":e")
  return (ext and ext ~= "") and ext or ""
end

-- Start async file discovery
function M.load_files()
  if file_cache or loading then
    return
  end
  loading = true

  -- Try rg first
  M._try_rg(function(files)
    if files then
      file_cache = files
      loading = false
      return
    end
    -- Fall back to git ls-files
    M._try_git(function(git_files)
      if git_files then
        file_cache = git_files
        loading = false
        return
      end
      -- Fall back to vim.fn.glob
      M._try_glob()
      loading = false
    end)
  end)
end

-- Try ripgrep for file discovery
function M._try_rg(callback)
  local files = {}
  local job_id = vim.fn.jobstart(
    { "rg", "--files", "--follow", "--hidden", "--glob", "!.git" },
    {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              table.insert(files, line)
            end
          end
        end
      end,
      on_exit = function(_, exit_code)
        vim.schedule(function()
          if exit_code == 0 and #files > 0 then
            callback(files)
          else
            callback(nil)
          end
        end)
      end,
    }
  )
  -- jobstart returns -1 if command not found
  if job_id <= 0 then
    callback(nil)
  end
end

-- Try git ls-files for file discovery
function M._try_git(callback)
  local files = {}
  local job_id = vim.fn.jobstart(
    { "git", "ls-files" },
    {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              table.insert(files, line)
            end
          end
        end
      end,
      on_exit = function(_, exit_code)
        vim.schedule(function()
          if exit_code == 0 and #files > 0 then
            callback(files)
          else
            callback(nil)
          end
        end)
      end,
    }
  )
  if job_id <= 0 then
    callback(nil)
  end
end

-- Synchronous fallback using vim.fn.glob
function M._try_glob()
  local raw = vim.fn.glob("**/*", false, true)
  local files = {}
  for _, f in ipairs(raw) do
    if vim.fn.isdirectory(f) == 0 then
      table.insert(files, f)
    end
  end
  if #files > 0 then
    file_cache = files
  else
    file_cache = {}
  end
end

-- Get the cached file list (may be nil if not loaded yet)
function M.get_files()
  return file_cache
end

-- Clear cache (useful for testing or manual refresh)
function M.clear_cache()
  file_cache = nil
  loading = false
end

return M
