-- Run with: nvim --headless -u NONE -l tests/chat.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

local requests = {}
local running = false
package.loaded["context.job"] = {
  start = function(request, callbacks)
    table.insert(requests, { body = vim.json.decode(request.body), callbacks = callbacks })
    running = true
    return #requests
  end,
  cancel = function()
    local was_running = running
    running = false
    return was_running
  end,
  is_running = function()
    return running
  end,
}

local context = require("context")
context.setup({ provider = "openai_compat", spinner = { enabled = false } })

-- File discovery must fall back when optional commands are not installed.
local files = require("context.files")
local original_path = vim.env.PATH
local git_path = vim.fn.tempname()
vim.fn.mkdir(git_path, "p")
assert((vim.uv or vim.loop).fs_symlink(vim.fn.exepath("git"), git_path .. "/git"))
for _, path in ipairs({ original_path, git_path, "" }) do
  vim.env.PATH = path
  files.clear_cache()
  files.load_files()
  assert(vim.wait(2000, function() return files.get_files() ~= nil end), "File discovery should finish")
  assert(vim.tbl_contains(files.get_files(), "README.md"), "Discover files with or without rg and git")
end
vim.env.PATH = original_path
vim.fn.delete(git_path, "rf")
files.clear_cache()

local source = vim.api.nvim_get_current_buf()
local original = { "local count = 7", "print(count * 3)" }
vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
vim.bo.modified = false
context.prompt_file()
local chat = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()

local function keys(value)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt", false)
  vim.wait(20, function()
    return false
  end)
end

local function submit(text)
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(chat), 0 })
  keys("A" .. text .. "<CR><Esc>")
end

local function transcript()
  return table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
end

local function chunk(request, text)
  request.callbacks.on_chunk("data: " .. vim.json.encode({ choices = { { delta = { content = text } } } }))
end

local function finish(request)
  running = false
  request.callbacks.on_done(0)
end

submit("What does this print?")
assert(#requests == 1, "Submitting the prompt should start a request")
assert(requests[1].body.messages[1].content:find("chat window", 1, true))
assert(requests[1].body.messages[2].content:find("print(count * 3)", 1, true))
chunk(requests[1], "It prints **21**.\n\n```lua\n")
assert(transcript():find("It prints **21**.", 1, true), "Reply should be visible before completion")
assert(transcript():find("> What does this print?\n\nIt prints", 1, true), "Replies should have no speaker label")
keys("AWhy not 14?<CR><Esc>")
assert(#requests == 1, "Enter must not start a second request while streaming")
chunk(requests[1], "print(7 * 3)\n```")
finish(requests[1])
assert(transcript():find("> Why not 14?", 1, true), "Streaming must preserve the next question being typed")
assert(transcript():find("> What does this print?", 1, true))
assert(transcript():find("```lua\nprint(7 * 3)\n```", 1, true), "Keep Markdown in chat")
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original))
assert(not vim.bo[source].modified, "Chat must not mark source modified")
assert(not require("context.diff").is_active(), "Chat must not start a diff")

submit("")
local messages = requests[2].body.messages
assert(#messages == 4, "Follow-up should include the previous user and assistant messages")
assert(messages[2].role == "user" and messages[2].content:find("What does this print?", 1, true))
assert(messages[3].role == "assistant" and messages[3].content:find("**21**", 1, true))
chunk(requests[2], "Because it multiplies by three.")
context.cancel()
assert(transcript():find("[Cancelled]", 1, true))

submit("Try again")
chunk(requests[2], "STALE RESPONSE")
requests[2].callbacks.on_done(0)
assert(not transcript():find("STALE RESPONSE", 1, true), "Cancelled callbacks must not alter the next reply")
requests[3].callbacks.on_chunk('data: {"error":{"message":"Rate limited"}}')
assert(transcript():find("Error: Rate limited", 1, true))
assert(not context.is_active())

submit("One more question")
assert(#requests == 4, "Errors should leave chat usable")
vim.api.nvim_win_close(win, true)
assert(not context.is_active(), "Closing chat should cancel its request")
chunk(requests[4], "AFTER CLOSE")
requests[4].callbacks.on_done(0)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original))

-- All built-in providers must preserve conversation roles and the edit prompt.
local history = { { role = "user", content = "Earlier question" }, { role = "assistant", content = "Earlier answer" } }
local contexts = { { text = "local x = 9", filetype = "lua", mode = "line" } }
for _, name in ipairs({ "anthropic", "openai", "openai_compat" }) do
  local provider = require("context.providers." .. name)
  local cfg = { api_key = "test-only" }
  local request = provider.build_request("Follow up", contexts, cfg, {
    history = history,
    system_prompt = "Chat instructions",
  })
  local body = vim.json.decode(request.body)
  local turns = body.messages or body.input
  local offset = name == "anthropic" and 0 or 1
  assert((body.system or turns[1].content) == "Chat instructions")
  assert(turns[1 + offset].role == "user" and turns[1 + offset].content == "Earlier question")
  assert(turns[2 + offset].role == "assistant" and turns[2 + offset].content == "Earlier answer")
  assert(turns[3 + offset].content:find("Follow up", 1, true))
  local edit = vim.json.decode(provider.build_request("Replace", contexts, cfg).body)
  assert((edit.system or (edit.messages or edit.input)[1].content):find("raw replacement code", 1, true))
end
assert(#history == 2, "Building a request must not mutate history")

-- Process Enter and the next input in one batch, without yielding to scheduled callbacks.
context.prompt_file()
chat = vim.api.nvim_get_current_buf()
win = vim.api.nvim_get_current_win()
keys("Afirst<CR>second<CR><Esc>")
assert(#requests == 5, "Rapid Enter must leave the second question as a draft")
assert(requests[5].body.messages[2].content:find("Instruction: first", 1, true))
chunk(requests[5], "First answer")
finish(requests[5])
assert(transcript():find("First answer", 1, true) < transcript():find("> second", 1, true))
vim.api.nvim_win_close(win, true)

context.prompt_file()
chat = vim.api.nvim_get_current_buf()
win = vim.api.nvim_get_current_win()
keys("Ahello<CR><C-c><Esc>")
assert(not context.is_active(), "Ctrl-C immediately after Enter must cancel the submitted request")
assert(transcript():find("[Cancelled]", 1, true))
vim.api.nvim_win_close(win, true)

-- The explicit edit mode still offers a diff instead of a chat reply.
context.setup({ provider = "openai_compat", response_mode = "edit", spinner = { enabled = false } })
vim.api.nvim_set_current_buf(source)
context.prompt_file()
keys("AReplace this<CR>")
chunk(requests[#requests], "local count = 8\nprint(count * 3)")
finish(requests[#requests])
assert(require("context.diff").is_active())
assert(vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == "local count = 8")
context.diff_accept()
assert(not require("context.diff").is_active())
print("Chat, history, cancellation, errors, providers and edit mode passed")
vim.cmd("qa!")
