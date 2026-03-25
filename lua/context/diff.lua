-- Diff preview for context.nvim
-- Shows a side-by-side diff of original vs proposed replacement.
-- The user accepts or rejects before the change is finalised.
local M = {}

local spinner = require("context.spinner")
local config = require("context.config")

local state = {
  active = false,
  original_bufnr = nil,    -- the user's real buffer
  scratch_bufnr = nil,     -- buffer showing the original state
  scratch_winid = nil,     -- window for the scratch buffer
  original_winid = nil,    -- window for the real buffer
  original_lines = nil,    -- original lines of the replaced range
  start_line = nil,        -- 0-indexed start of replaced range
  replacement_len = nil,   -- number of replacement lines written
  on_cleanup = nil,        -- callback when review ends
  autocmd_group = nil,     -- augroup for edge-case cleanup
  saved_modifiable = nil,  -- original modifiable value
}

-- Tear down all diff UI and reset state
local function cleanup()
  -- Prevent re-entrancy (WinClosed autocmd can fire during cleanup)
  if not state.active then
    return
  end
  state.active = false

  -- Remove autocmds
  if state.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
    state.autocmd_group = nil
  end

  -- Exit diff mode in both windows
  pcall(function()
    if state.original_winid and vim.api.nvim_win_is_valid(state.original_winid) then
      vim.api.nvim_win_call(state.original_winid, function()
        vim.cmd("diffoff")
      end)
    end
  end)

  -- Close the scratch window/buffer
  if state.scratch_winid and vim.api.nvim_win_is_valid(state.scratch_winid) then
    vim.api.nvim_win_close(state.scratch_winid, true)
  end
  if state.scratch_bufnr and vim.api.nvim_buf_is_valid(state.scratch_bufnr) then
    pcall(vim.api.nvim_buf_delete, state.scratch_bufnr, { force = true })
  end

  -- Restore modifiable on original buffer
  if state.original_bufnr and vim.api.nvim_buf_is_valid(state.original_bufnr) then
    if state.saved_modifiable ~= nil then
      vim.api.nvim_set_option_value("modifiable", state.saved_modifiable, { buf = state.original_bufnr })
    end
  end

  -- Focus back on original window
  if state.original_winid and vim.api.nvim_win_is_valid(state.original_winid) then
    vim.api.nvim_set_current_win(state.original_winid)
  end

  -- Fire the cleanup callback (lets stream.lua clear its own state)
  local cb = state.on_cleanup
  state = {
    active = false,
    original_bufnr = nil,
    scratch_bufnr = nil,
    scratch_winid = nil,
    original_winid = nil,
    original_lines = nil,
    start_line = nil,
    replacement_len = nil,
    on_cleanup = nil,
    autocmd_group = nil,
    saved_modifiable = nil,
  }
  if cb then
    cb()
  end
end

-- Set up buffer-local keymaps for accept/reject on both buffers
local function setup_keymaps()
  local bufs = {}
  if state.original_bufnr then
    table.insert(bufs, state.original_bufnr)
  end
  if state.scratch_bufnr then
    table.insert(bufs, state.scratch_bufnr)
  end

  for _, bufnr in ipairs(bufs) do
    vim.keymap.set("n", "<CR>", function()
      M.accept()
    end, { buffer = bufnr, noremap = true, silent = true, desc = "Context: Accept diff" })

    vim.keymap.set("n", "q", function()
      M.reject()
    end, { buffer = bufnr, noremap = true, silent = true, desc = "Context: Reject diff" })
  end
end

--- Show a diff review of the proposed change.
--- @param bufnr number Target buffer
--- @param start_line number 0-indexed start line
--- @param end_line number 0-indexed end line (inclusive)
--- @param original_lines string[] Original lines being replaced
--- @param replacement_lines string[] Proposed replacement lines
--- @param on_cleanup function? Called when review ends (accept or reject)
function M.show(bufnr, start_line, end_line, original_lines, replacement_lines, on_cleanup)
  -- Safety: reject any in-progress review first
  if state.active then
    cleanup()
  end

  state.active = true
  state.original_bufnr = bufnr
  state.original_lines = original_lines
  state.start_line = start_line
  state.on_cleanup = on_cleanup
  state.original_winid = vim.api.nvim_get_current_win()

  -- Save original modifiable state, then lock the buffer during review
  state.saved_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })

  -- 1. Create scratch buffer with full copy of the original file (pre-change)
  local full_original = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  state.scratch_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(state.scratch_bufnr, 0, -1, false, full_original)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.scratch_bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.scratch_bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = state.scratch_bufnr })
  vim.api.nvim_buf_set_name(state.scratch_bufnr, "[Context: Original]")

  -- Copy filetype for syntax highlighting in diff
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", ft, { buf = state.scratch_bufnr })

  -- 2. Apply the replacement to the REAL buffer (so the diff shows proposed on left)
  vim.api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, start_line, end_line + 1, false, replacement_lines)
  end)
  state.replacement_len = #replacement_lines

  -- 3. Open the scratch buffer in a split
  local diff_cfg = config.get().diff or {}
  local split_cmd = diff_cfg.vertical ~= false and "vsplit" or "split"
  vim.cmd(split_cmd)
  state.scratch_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.scratch_winid, state.scratch_bufnr)

  -- Make the scratch buffer read-only
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.scratch_bufnr })

  -- 4. Enable diff mode on both windows
  vim.api.nvim_win_call(state.scratch_winid, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(state.original_winid, function()
    vim.cmd("diffthis")
  end)

  -- Lock the original buffer to prevent edits during review
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  -- 5. Focus the original buffer window
  vim.api.nvim_set_current_win(state.original_winid)

  -- Scroll to the changed region
  pcall(vim.api.nvim_win_set_cursor, state.original_winid, { start_line + 1, 0 })

  -- 6. Set up keymaps and autocmds
  setup_keymaps()

  state.autocmd_group = vim.api.nvim_create_augroup("ContextDiffReview", { clear = true })

  -- If the user closes the scratch window manually, treat as reject
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.autocmd_group,
    pattern = tostring(state.scratch_winid),
    callback = function()
      if state.active then
        M.reject()
      end
    end,
    once = true,
  })

  -- If the original buffer is wiped, clean up silently
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.autocmd_group,
    buffer = bufnr,
    callback = function()
      if state.active then
        -- Don't try to restore lines — buffer is gone
        state.original_lines = nil
        cleanup()
      end
    end,
    once = true,
  })

  -- 7. Show review indicator
  spinner.review()
end

--- Accept the proposed change. The replacement is already in the buffer.
function M.accept()
  if not state.active then
    return
  end

  -- The replacement is already applied — just clean up the diff UI
  spinner.finish(true)
  cleanup()
end

--- Reject the proposed change and restore original text.
function M.reject()
  if not state.active then
    return
  end

  -- Restore original lines via undo (cleanest for undo history)
  if state.original_bufnr and vim.api.nvim_buf_is_valid(state.original_bufnr) then
    -- Temporarily re-enable modifiable for the undo
    vim.api.nvim_set_option_value("modifiable", true, { buf = state.original_bufnr })
    vim.api.nvim_buf_call(state.original_bufnr, function()
      vim.cmd("silent undo")
    end)
  end

  spinner.finish(false)
  cleanup()
end

--- Check if a diff review is currently active
function M.is_active()
  return state.active
end

return M
