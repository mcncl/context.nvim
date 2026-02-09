-- Inline @file completion for the prompt buffer
local M = {}

local files = require("context.files")

-- Set up completion on a prompt buffer
function M.setup_buffer(bufnr)
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = function()
      M._on_text_changed()
    end,
  })
end

-- Check if the character before @ is whitespace or start of prompt text
function M._on_text_changed()
  -- Don't interfere if completion menu is already visible
  if vim.fn.pumvisible() == 1 then
    return
  end

  local file_list = files.get_files()
  if not file_list or #file_list == 0 then
    return
  end

  -- Get current line and cursor position
  local line = vim.api.nvim_get_current_line()
  local col = vim.fn.col(".")

  -- Get text up to cursor (col is 1-indexed, points to char after cursor in insert mode)
  local before_cursor = line:sub(1, col - 1)

  -- Find the last @ that's preceded by whitespace, start-of-line, or prompt prefix "> "
  -- The prompt buffer adds "> " prefix, so we need to account for that
  local at_pos = nil
  for i = #before_cursor, 1, -1 do
    local ch = before_cursor:sub(i, i)
    if ch == "@" then
      -- Check if preceded by whitespace or at effective start of input
      local before_at = before_cursor:sub(1, i - 1)
      if before_at == "" or before_at == "> " or before_at:match("%s$") then
        at_pos = i
        break
      end
    end
    -- Stop looking if we hit a space (no @ in this word)
    if ch:match("%s") then
      break
    end
  end

  if not at_pos then
    return
  end

  -- Extract query text after @
  local query = before_cursor:sub(at_pos + 1)

  -- Filter file list
  local matches = M._filter_files(file_list, query)
  if #matches == 0 then
    return
  end

  -- Show completion at the @ position
  vim.fn.complete(at_pos, matches)
end

-- Filter file list by query (case-insensitive substring match), limited to 20 results
function M._filter_files(file_list, query)
  local matches = {}
  local lower_query = query:lower()
  local limit = 20

  for _, file in ipairs(file_list) do
    if #matches >= limit then
      break
    end
    if lower_query == "" or file:lower():find(lower_query, 1, true) then
      table.insert(matches, file)
    end
  end

  return matches
end

return M
