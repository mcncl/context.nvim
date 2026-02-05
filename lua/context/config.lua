-- Configuration management for context.nvim
local M = {}

M.defaults = {
  provider = "anthropic",

  providers = {
    anthropic = {
      api_key = vim.env.ANTHROPIC_API_KEY,
      model = "claude-sonnet-4-5",
      max_tokens = 4096,
    },
    openai = {
      api_key = vim.env.OPENAI_API_KEY,
      model = "gpt-5-mini",
      max_tokens = 4096,
    },
    openai_compat = {
      base_url = "http://localhost:11434/v1",
      api_key = "",
      model = "llama3",
      max_tokens = 4096,
    },
  },

  keymaps = {
    prompt = "<leader>ai",
    cancel = "<leader>ac",
  },

  ui = {
    prompt_title = "Context",
    prompt_width = 60,
    prompt_height = 3,
  },

  system_prompt = [[You are a code completion assistant. You will receive a code snippet and a user instruction.

CRITICAL: Output ONLY the raw replacement code. Your response will be inserted directly into a code file.
- NO markdown fences (no ```language or ```)
- NO explanations or commentary
- NO "Here's the code:" or similar preambles
- Just the pure code that should replace the selection

The code you output will directly replace the selected text in the user's editor.]],
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

function M.get()
  return M.options
end

function M.get_provider_config(name)
  name = name or M.options.provider
  return M.options.providers[name]
end

return M
