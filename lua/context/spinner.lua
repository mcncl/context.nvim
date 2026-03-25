-- Streaming progress indicator for context.nvim
local M = {}

local uv = vim.uv or vim.loop

local ns_id = nil

local function ensure_namespace()
  if not ns_id then
    ns_id = vim.api.nvim_create_namespace("context_spinner")
  end
  return ns_id
end

-- Spinner state
local state = {
  active = false,
  stage = "idle", -- "idle" | "streaming" | "done" | "error" | "cancelled"
  bufnr = nil,
  line = nil, -- 0-indexed line for extmark
  mark_id = nil,
  timer = nil,
  frame_idx = 1,
  chars_received = 0,
  start_time = nil,
}

local function get_config()
  local ok, config = pcall(require, "context.config")
  if ok then
    local opts = config.get()
    return opts.spinner or {}
  end
  return {}
end

local function default_frames()
  return { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
end

-- Clear the extmark
local function clear_mark()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and state.mark_id then
    pcall(vim.api.nvim_buf_del_extmark, state.bufnr, ensure_namespace(), state.mark_id)
  end
  state.mark_id = nil
end

-- Stop and close the timer
local function stop_timer()
  if state.timer then
    if state.timer:is_active() then
      state.timer:stop()
    end
    if not state.timer:is_closing() then
      state.timer:close()
    end
    state.timer = nil
  end
end

-- Reset all state to idle
local function reset_state()
  stop_timer()
  clear_mark()
  state.active = false
  state.stage = "idle"
  state.bufnr = nil
  state.line = nil
  state.mark_id = nil
  state.frame_idx = 1
  state.chars_received = 0
  state.start_time = nil
end

-- Set the extmark virtual text at the target line
local function set_virt_text(text, hl_group)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local ns = ensure_namespace()
  local line = state.line

  -- Clamp line to valid range
  local line_count = vim.api.nvim_buf_line_count(state.bufnr)
  if line >= line_count then
    line = line_count - 1
  end
  if line < 0 then
    line = 0
  end

  local opts = {
    virt_text = { { text, hl_group } },
    virt_text_pos = "eol",
  }

  if state.mark_id then
    opts.id = state.mark_id
  end

  state.mark_id = vim.api.nvim_buf_set_extmark(state.bufnr, ns, line, 0, opts)
end

-- Format the spinner display text
local function format_display(frame)
  local cfg = get_config()
  local elapsed = ""
  if state.start_time then
    local secs = math.floor((uv.hrtime() - state.start_time) / 1e9)
    if secs > 0 then
      elapsed = string.format(" %ds", secs)
    end
  end

  local chars = ""
  if state.chars_received > 0 then
    chars = string.format(" (%d chars)", state.chars_received)
  end

  -- Allow user to disable the detail text
  if cfg.minimal then
    return string.format(" %s", frame)
  end

  return string.format(" %s Generating%s%s", frame, elapsed, chars)
end

-- Start the spinner animation
function M.start(bufnr, line)
  -- Clean up any existing spinner
  reset_state()

  local cfg = get_config()
  if cfg.enabled == false then
    return
  end

  state.active = true
  state.stage = "streaming"
  state.bufnr = bufnr
  state.line = line
  state.start_time = uv.hrtime()
  state.chars_received = 0
  state.frame_idx = 1

  local frames = cfg.frames or default_frames()
  local interval = cfg.interval or 80

  -- Show initial frame immediately
  set_virt_text(format_display(frames[1]), "ContextSpinner")

  -- Start animation timer
  state.timer = uv.new_timer()
  state.timer:start(interval, interval, vim.schedule_wrap(function()
    if not state.active or state.stage ~= "streaming" then
      return
    end

    state.frame_idx = (state.frame_idx % #frames) + 1
    set_virt_text(format_display(frames[state.frame_idx]), "ContextSpinner")
  end))
end

-- Update character count during streaming
function M.update(chars_received)
  if not state.active then
    return
  end
  state.chars_received = chars_received
end

-- Show a brief completion indicator then clean up
function M.finish(success)
  if not state.active then
    return
  end

  stop_timer()

  if success then
    state.stage = "done"
    set_virt_text(" ✓ Done", "ContextSpinnerDone")
  else
    state.stage = "error"
    set_virt_text(" ✗ Error", "ContextSpinnerError")
  end

  local cfg = get_config()
  local delay = cfg.done_delay or 1500

  -- Clear after delay
  state.timer = uv.new_timer()
  state.timer:start(delay, 0, vim.schedule_wrap(function()
    reset_state()
  end))
end

-- Cancel the spinner immediately
function M.cancel()
  if not state.active then
    return
  end

  stop_timer()
  state.stage = "cancelled"
  set_virt_text(" ⊘ Cancelled", "ContextSpinnerError")

  local cfg = get_config()
  local delay = cfg.done_delay or 1500

  state.timer = uv.new_timer()
  state.timer:start(delay, 0, vim.schedule_wrap(function()
    reset_state()
  end))
end

-- Get structured status for programmatic use
function M.get_status()
  return {
    active = state.active,
    stage = state.stage,
    chars = state.chars_received,
    elapsed = state.start_time and math.floor((uv.hrtime() - state.start_time) / 1e9) or 0,
  }
end

-- Get a formatted status string for statusline integration (e.g. lualine)
function M.get_status_line()
  if not state.active then
    return ""
  end

  local frames = get_config().frames or default_frames()
  local frame = frames[state.frame_idx] or frames[1]

  if state.stage == "streaming" then
    local secs = state.start_time and math.floor((uv.hrtime() - state.start_time) / 1e9) or 0
    if secs > 0 then
      return string.format("%s Context %ds", frame, secs)
    end
    return string.format("%s Context", frame)
  elseif state.stage == "done" then
    return "✓ Context"
  elseif state.stage == "error" then
    return "✗ Context"
  elseif state.stage == "cancelled" then
    return "⊘ Context"
  end

  return ""
end

return M
