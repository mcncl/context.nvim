# context.nvim

A Neovim plugin for AI interaction with scoped context: selected text, current line, or full file. Replies stream below your question in a floating chat window without changing your code. An optional edit mode offers code replacements with diff review.

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
  provider = "anthropic",  -- or "openai", "openai_compat", "amp"
  response_mode = "chat",  -- "edit" to replace code with diff review

  providers = {
    amp = {
      command = "amp",  -- Executable name or absolute path
      -- mode = "medium",  -- Optional Amp agent mode
    },
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
    prompt_height = 3,  -- Edit-mode input height
    chat_height = 20,
  },

  diff = {
    enabled = true,    -- Edit mode only (false = instant-apply)
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

### Amp CLI

Install the [Amp CLI](https://ampcode.com/docs/cli) and run `amp login` in your terminal. No separate OpenAI or Anthropic API key is required. Requests use your Amp account and its usage limits or credits.

```lua
require("context").setup({ provider = "amp" })
```

Neovim must be able to find `amp` on its PATH. Otherwise, set `providers.amp.command` to its absolute path.

Each question starts a new local CLI process. Selected code, references, and completed chat turns go through stdin. The answer appears below the question when Amp finishes, and the process exits. Ctrl-C or closing chat terminates the active process. There is no persistent CLI session.

All tools are disabled, including file editing, shell commands, and MCP tools. The CLI runs in a temporary directory with isolated settings and IDE context disabled. Your personal and repository Amp settings are not loaded or changed; use `providers.amp.mode` to select an agent mode. Your saved Amp login is reused. Amp stores each request as a private thread and archives it after execution; closing the Neovim chat does not delete those threads.

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

### Chat

Open a prompt with `<leader>ai` or a `:Context` command, type your question, and press Enter. The answer streams below the question. Your source buffer is not changed, even when the reply contains code.

Each follow-up includes the previous completed questions and answers. The selected code is captured when you open the chat; `@path/to/file.lua` references add files to individual questions. Only one request runs at a time. You can type your next question while waiting, then submit it after the reply finishes.

| Key | Action |
|-----|--------|
| Enter (insert mode) | Send a question, or accept visible `@file` completion |
| Escape | Leave insert mode to scroll or copy replies |
| Enter (normal mode) | Return to the input line |
| Ctrl-C (insert mode) | Cancel the current reply without closing chat |
| `q` (normal mode) | Close chat and cancel any active reply |

Closing the window discards the conversation. Opening another prompt while chat is open focuses the existing conversation. To use different selected code, close the chat and open a new one.

Use `chat_system_prompt` to customize chat instructions. The existing `system_prompt` setting applies to edit mode.

### Diff Preview

Set `response_mode = "edit"` to use the code-replacement workflow. When a response completes, a side-by-side diff opens showing the original code vs the proposed replacement. From either window:

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

## Testing

Run the chat and edit-mode regression checks without API credentials:

```sh
nvim --headless -u NONE -l tests/chat.lua
nvim --headless -u NONE -l tests/amp.lua
luacheck lua/ tests/ --globals vim
```

## License

MIT
