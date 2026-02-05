-- context.nvim - AI interaction with scoped context
local M = {}

local config = require("context.config")
local prompt = require("context.prompt")
local stream = require("context.stream")

-- Setup the plugin
function M.setup(opts)
  config.setup(opts)

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

return M
