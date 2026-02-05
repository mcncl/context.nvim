-- Context detection: visual selection, current line, or full file
local M = {}

-- Get the current buffer's filetype
local function get_filetype()
  return vim.bo.filetype or ""
end

-- Get the visual selection text and position
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  local start_col = start_pos[3]
  local end_col = end_pos[3]

  -- Get lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil
  end

  -- Get the visual mode that was used
  local mode = vim.fn.visualmode()

  if mode == "v" then
    -- Character-wise visual mode: trim to selection columns
    if #lines == 1 then
      lines[1] = string.sub(lines[1], start_col, end_col)
    else
      lines[1] = string.sub(lines[1], start_col)
      lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end
  elseif mode == "\22" then
    -- Block visual mode (Ctrl-V): extract column range from each line
    local new_lines = {}
    for _, line in ipairs(lines) do
      table.insert(new_lines, string.sub(line, start_col, end_col))
    end
    lines = new_lines
  end
  -- Line-wise visual (V): full lines are used as-is, no trimming needed

  return {
    text = table.concat(lines, "\n"),
    start_line = start_line,
    end_line = end_line,
    start_col = start_col,
    end_col = end_col,
    mode = "visual",
    visual_mode = mode,
    filetype = get_filetype(),
  }
end

-- Get the current line
local function get_current_line()
  local line_num = vim.fn.line(".")
  local line = vim.api.nvim_get_current_line()

  return {
    text = line,
    start_line = line_num,
    end_line = line_num,
    start_col = 1,
    end_col = #line,
    mode = "line",
    filetype = get_filetype(),
  }
end

-- Get the full file content
local function get_full_file()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local line_count = #lines

  return {
    text = table.concat(lines, "\n"),
    start_line = 1,
    end_line = line_count,
    start_col = 1,
    end_col = #lines[line_count] or 0,
    mode = "file",
    filetype = get_filetype(),
  }
end

-- Check if we have a valid visual selection
local function has_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Check if marks are set (line numbers > 0)
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return false
  end

  -- Check if the selection was made in the current buffer recently
  -- by verifying we're in visual mode or just exited it
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    return true
  end

  -- Check if visual marks are valid for current buffer
  local buf_lines = vim.api.nvim_buf_line_count(0)
  if start_pos[2] > buf_lines or end_pos[2] > buf_lines then
    return false
  end

  return true
end

-- Main function to detect and return context
-- @param force_mode string|nil - "visual", "line", or "file" to force a specific mode
function M.get_context(force_mode)
  if force_mode == "file" then
    return get_full_file()
  end

  if force_mode == "line" then
    return get_current_line()
  end

  if force_mode == "visual" then
    if has_visual_selection() then
      return get_visual_selection()
    end
    return get_current_line()
  end

  -- Auto-detect mode
  local current_line = vim.fn.line(".")

  -- Check for visual selection first (if called right after visual mode)
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    return get_visual_selection()
  end

  -- If at line 1 and no visual selection, use full file
  if current_line == 1 and not has_visual_selection() then
    return get_full_file()
  end

  -- Otherwise use current line
  return get_current_line()
end

return M
