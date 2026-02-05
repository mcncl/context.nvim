-- Lazy-load entry point for context.nvim
if vim.g.loaded_context then
  return
end
vim.g.loaded_context = true

-- Create user commands
vim.api.nvim_create_user_command("Context", function()
  require("context").prompt()
end, { desc = "Open context prompt with auto-detected context" })

vim.api.nvim_create_user_command("ContextVisual", function()
  require("context").prompt_visual()
end, { desc = "Open context prompt with visual selection", range = true })

vim.api.nvim_create_user_command("ContextLine", function()
  require("context").prompt_line()
end, { desc = "Open context prompt with current line" })

vim.api.nvim_create_user_command("ContextFile", function()
  require("context").prompt_file()
end, { desc = "Open context prompt with full file" })

vim.api.nvim_create_user_command("ContextCancel", function()
  require("context").cancel()
end, { desc = "Cancel active context request" })

vim.api.nvim_create_user_command("ContextProvider", function(opts)
  if opts.args and opts.args ~= "" then
    require("context").set_provider(opts.args)
  else
    local cfg = require("context.config").get()
    vim.notify("Current provider: " .. cfg.provider, vim.log.levels.INFO)
  end
end, {
  desc = "Get or set context provider",
  nargs = "?",
  complete = function()
    local cfg = require("context.config").get()
    return vim.tbl_keys(cfg.providers)
  end,
})
