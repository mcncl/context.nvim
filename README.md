# context.nvim

A Neovim plugin for AI interaction with scoped context: selected text, current line, or full file. Responses stream in-place, replacing the selection while you can continue editing elsewhere.

## Installation

### lazy.nvim

```lua
{
  "mcncl/context.nvim",
  config = function()
    require("context").setup({
      provider = "anthropic",
      providers = {
        anthropic = {
          api_key = vim.env.ANTHROPIC_API_KEY,
          model = "claude-sonnet-4-20250514", -- optional
        },
      },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "mcncl/context.nvim",
  config = function()
    require("context").setup({
      provider = "anthropic",
      providers = {
        anthropic = {
          api_key = vim.env.ANTHROPIC_API_KEY,
        },
      },
    })
  end,
}
```

## Configuration

```lua
require("context").setup({
  provider = "anthropic",  -- or "openai", "openai_compat"

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
      base_url = "http://localhost:11434/v1",  -- Ollama example
      api_key = "",  -- Optional for local
      model = "rnj-1",
      max_tokens = 4096,
    },
  },

  keymaps = {
    prompt = "<leader>ai",  -- Open prompt with context
    cancel = "<leader>ac",  -- Cancel in-flight request
  },

  ui = {
    prompt_title = "Context",
    prompt_width = 60,
    prompt_height = 3,
  },
})
```

## Usage

### Keymaps

| Mode | Key | Action |
|------|-----|--------|
| n, v | `<leader>ai` | Open prompt with context |
| n | `<leader>ac` | Cancel active request |

### Commands

- `:Context` - Open prompt with auto-detected context
- `:ContextVisual` - Open prompt with visual selection
- `:ContextLine` - Open prompt with current line
- `:ContextFile` - Open prompt with full file
- `:ContextCancel` - Cancel active request
- `:ContextProvider [name]` - Get or set current provider

### Context Detection

1. **Visual mode**: Select text, then `<leader>ai` - uses selection
2. **Normal mode at line 1**: `<leader>ai` - uses entire file
3. **Normal mode elsewhere**: `<leader>ai` - uses current line

### Programmatic API

```lua
local context = require("context")

context.prompt()           -- Open prompt with auto-detected context
context.prompt_visual()    -- Force visual mode context
context.prompt_line()      -- Force line mode context
context.prompt_file()      -- Force file mode context
context.cancel()           -- Cancel in-flight request
context.set_provider(name) -- Switch provider at runtime
context.is_active()        -- Check if request is in progress
```

## License

MIT
