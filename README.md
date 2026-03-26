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
          model = "claude-sonnet-4-5", -- optional
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

  diff = {
    enabled = true,    -- Show diff preview before applying (false = instant-apply)
    vertical = true,   -- Vertical split (false = horizontal)
  },

  spinner = {
    enabled = true,
    interval = 80,       -- ms between animation frames
    done_delay = 1500,   -- ms to show done/error indicator
    minimal = false,     -- true = spinner only, no elapsed time or char count
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
- `:ContextDiffAccept` - Accept the proposed diff
- `:ContextDiffReject` - Reject the proposed diff
- `:ContextProvider [name]` - Get or set current provider

### Diff Preview

When a response completes, a side-by-side diff opens showing the original code vs the proposed replacement. From either window:

| Key | Action |
|-----|--------|
| `<CR>` | Accept the change |
| `q` | Reject and restore original |

The buffer is locked during review to prevent edits. Closing the diff window also rejects. To disable the preview and apply changes instantly, set `diff = { enabled = false }`.

### Context Detection

1. **Visual mode**: Select text, then `<leader>ai` - uses selection
2. **Normal mode at line 1**: `<leader>ai` - uses entire file
3. **Normal mode elsewhere**: `<leader>ai` - uses current line

### Statusline Integration

Expose streaming/review status in your statusline (e.g. lualine):

```lua
lualine_x = {
  { require("context").get_status_line, cond = require("context").is_active },
}
```

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
context.diff_accept()      -- Accept active diff review
context.diff_reject()      -- Reject active diff review
context.get_status()       -- Structured status for programmatic use
context.get_status_line()  -- Formatted string for statusline
```

## License

MIT
