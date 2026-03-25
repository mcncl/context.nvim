-- context.nvim - AI interaction with scoped context
local M = {}

local config = require("context.config")
local prompt = require("context.prompt")
local stream = require("context.stream")
local spinner = require("context.spinner")

-- Setup the plugin
function M.setup(opts)
  config.setup(opts)

  -- Define highlight groups (default = true lets users override)
  vim.api.nvim_set_hl(0, "ContextSpinner", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "ContextSpinnerDone", { default = true, link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "ContextSpinnerError", { default = true, link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "ContextSpinnerReview", { default = true, link = "DiagnosticWarn" })

  -- Set up keymaps
  local keymaps = config.get().keymaps

  if keymaps.prompt then
    -- Normal mode: auto-detect context
    vim.keymap.set("n", keymaps.prompt, function()
      M.prompt()
    end, { noremap = true, silent = true, desc = "Context: Open prompt" })

    -- Visual mode: use selection
    vim.keymap.set("v", keymaps.prompt, function()
      M.prompt_visual()
    end, { noremap = true, silent = true, desc = "Context: Open prompt with selection" })
  end

  if keymaps.cancel then
    vim.keymap.set("n", keymaps.cancel, function()
      M.cancel()
    end, { noremap = true, silent = true, desc = "Context: Cancel active request" })
  end
end

-- Open prompt with auto-detected context
function M.prompt()
  prompt.show()
end

-- Open prompt with visual selection context
function M.prompt_visual()
  prompt.show_visual()
end

-- Open prompt with line context
function M.prompt_line()
  prompt.show_line()
end

-- Open prompt with file context
function M.prompt_file()
  prompt.show_file()
end

-- Cancel the active request
function M.cancel()
  return stream.cancel()
end

-- Switch provider at runtime
function M.set_provider(name)
  local cfg = config.get()
  if not cfg.providers[name] then
    vim.notify("Unknown provider: " .. name, vim.log.levels.ERROR)
    return false
  end
  cfg.provider = name
  vim.notify("Context provider set to: " .. name, vim.log.levels.INFO)
  return true
end

-- Check if a request is currently active
function M.is_active()
  return stream.is_active()
end

-- Get structured spinner status for programmatic use
function M.get_status()
  return spinner.get_status()
end

-- Get formatted status string for statusline integration
-- Usage with lualine:
--   lualine_x = {
--     { require("context").get_status_line, cond = require("context").is_active },
--   }
function M.get_status_line()
  return spinner.get_status_line()
end

-- Accept the active diff review
function M.diff_accept()
  local diff_mod = require("context.diff")
  if diff_mod.is_active() then
    diff_mod.accept()
  else
    vim.notify("No diff review active", vim.log.levels.WARN)
  end
end

-- Reject the active diff review
function M.diff_reject()
  local diff_mod = require("context.diff")
  if diff_mod.is_active() then
    diff_mod.reject()
  else
    vim.notify("No diff review active", vim.log.levels.WARN)
  end
end

return M
