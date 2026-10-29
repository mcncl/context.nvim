-- Run with: nvim --headless -u NONE -l tests/amp.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Exercise the real subprocess transport without credentials or inference costs.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local command = directory .. "/fake amp"
vim.fn.writefile(vim.split([[#!/bin/sh
set -eu
printf '%s\n' "$@" > "$CONTEXT_AMP_RECORD/args"
printf '%s\n' "$$" >> "$CONTEXT_AMP_RECORD/pids"
pwd > "$CONTEXT_AMP_RECORD/cwd"
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--settings-file' ]; then
    cp "$2" "$CONTEXT_AMP_RECORD/settings.json"
    break
  fi
  shift
done
cat > "$CONTEXT_AMP_RECORD/prompt"
case "$(cat "$CONTEXT_AMP_RECORD/prompt")" in
  *WAIT*) printf '{"type":"system","subtype":"init","tools":[]}\n'; exec sleep 30 ;;
  *BADTOOLS*) printf '{"type":"system","subtype":"init","tools":["Bash"]}\n'; exec sleep 30 ;;
  *FAIL*) printf '{"type":"result","is_error":true,"error":"Sign in with amp login"}\n'; exit 1 ;;
  *STDERR*) printf 'Authentication failed\n' >&2; exit 1 ;;
esac
printf 'Startup diagnostic\n' >&2
printf '{"type":"system","subtype":"init","tools":[]}\n'
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"It prints **21**."}]}}\n'
printf '{"type":"result","is_error":false,"res'
sleep 0.05
printf 'ult":"It prints **21**."}'
]], "\n", { plain = true }), command)
vim.fn.setfperm(command, "rwx------")
local old_record = vim.env.CONTEXT_AMP_RECORD
vim.env.CONTEXT_AMP_RECORD = directory

local context = require("context")
local job = require("context.job")
context.setup({ provider = "amp", providers = { amp = { command = command } }, spinner = { enabled = false } })
local source = vim.api.nvim_get_current_buf()
local original = { "local count = 7", "print(count * 3)" }
vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
vim.bo.modified = false

local function read(name)
  return table.concat(vim.fn.readfile(directory .. "/" .. name), "\n")
end

local function keys(value)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt", false)
end

context.prompt_file()
local chat = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()
local function transcript()
  return table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
end

local function submit(text)
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(chat), 0 })
  keys("A" .. text .. "<CR><Esc>")
end

local function wait_for_reply(value)
  assert(vim.wait(3000, function()
    return not context.is_active() and transcript():find(value, 1, true) ~= nil
  end), "Expected reply: " .. value .. "\n" .. transcript())
end

submit("What does this print?")
wait_for_reply("It prints **21**.")
assert(select(2, transcript():gsub("It prints", "")) == 1, "Do not repeat assistant and result messages")
assert(read("prompt"):find("print(count * 3)", 1, true), "Pass selected code via stdin")
assert(read("args"):find("--execute\n--stream-json", 1, true))
assert(read("args"):find("--no-ide", 1, true))
assert(not read("args"):find("What does this print?", 1, true), "Keep questions out of process arguments")
local settings = vim.fn.json_decode(read("settings.json"))
assert(#settings["amp.tools.enable"] == 0 and settings["amp.tools.disable"][1] == "*")
assert(settings["amp.mcpPermissions"][1].action == "reject")
assert(read("cwd") ~= vim.fn.getcwd(), "Ignore repository tool settings")
assert(vim.fn.isdirectory(read("cwd")) == 0, "Remove isolated settings after completion")
local first_pid = read("pids")

submit("Why not fourteen?")
assert(vim.wait(3000, function() return read("pids") ~= first_pid and not job.is_running() end))
wait_for_reply("It prints **21**.")
assert(read("prompt"):find("user:\nSelected code", 1, true))
assert(read("prompt"):find("assistant:\nIt prints **21**.", 1, true), "Pass completed history")
assert(read("prompt"):find("Instruction: Why not fourteen?", 1, true))

submit("FAIL")
wait_for_reply("Error: Sign in with amp login")
submit("STDERR")
wait_for_reply("Error: Authentication failed")
submit("BADTOOLS")
wait_for_reply("Error: Amp started with tools enabled")

-- Failed and cancelled turns must not enter follow-up history.
submit("WAIT")
assert(vim.wait(3000, function() return read("prompt"):find("Instruction: WAIT", 1, true) ~= nil end))
assert(not read("prompt"):find("Instruction: FAIL", 1, true))
local active = job.active_job
local cwd = read("cwd")
keys("A<C-c><Esc>")
assert(transcript():find("[Cancelled]", 1, true))
assert(vim.wait(3000, function() return vim.fn.isdirectory(cwd) == 0 end), "Cancel must clean up settings")
assert(vim.fn.jobwait({ active }, 0)[1] ~= -1, "Cancel must terminate the process")

submit("WAIT again")
assert(vim.wait(3000, function() return read("prompt"):find("Instruction: WAIT again", 1, true) ~= nil end))
active = job.active_job
cwd = read("cwd")
vim.api.nvim_win_close(win, true)
assert(vim.wait(3000, function() return vim.fn.isdirectory(cwd) == 0 end))
assert(vim.fn.jobwait({ active }, 0)[1] ~= -1, "Closing chat must terminate the process")

context.setup({ provider = "amp", providers = { amp = { command = directory .. "/missing" } } })
context.prompt_file()
chat = vim.api.nvim_get_current_buf()
win = vim.api.nvim_get_current_win()
submit("Hello")
wait_for_reply("Executable not found:")
keys("A<C-c><Esc>")
assert(transcript():find("Executable not found:", 1, true), "Cancel after startup failure must preserve the error")
vim.api.nvim_win_close(win, true)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original))
assert(not vim.bo[source].modified, "Amp chat must leave source untouched")

vim.env.CONTEXT_AMP_RECORD = old_record
vim.fn.delete(directory, "rf")
print("Amp subprocess, history, tool isolation, errors and cancellation passed")
vim.cmd("qa!")
