-- Amp CLI provider: one tool-free execute process per request.
local M = {}

function M.build_request(prompt, contexts, config, options)
  options = options or {}
  local providers = require("context.providers")
  local messages = providers.format_messages(prompt, contexts, options)
  local parts = { options.system_prompt or require("context.config").get().system_prompt }
  for _, message in ipairs(messages) do
    table.insert(parts, message.role .. ":\n" .. message.content)
  end
  table.insert(parts, "Answer only the latest user message. Tools are disabled.")

  local command = {
    config.command or "amp", "--execute", "--stream-json", "--no-ide",
    "--no-notifications", "--no-color", "--executor", "local", "--visibility", "private",
  }
  if config.mode then
    vim.list_extend(command, { "--mode", config.mode })
  end

  return {
    command = command,
    stdin = table.concat(parts, "\n\n"),
    -- Run outside the repository so workspace settings cannot enable tools.
    settings = {
      ["amp.tools.enable"] = {},
      ["amp.tools.disable"] = { "*" },
      ["amp.mcpPermissions"] = {
        { matches = { command = "*" }, action = "reject" },
        { matches = { url = "*" }, action = "reject" },
      },
      ["amp.updates.mode"] = "disabled",
    },
  }
end

function M.parse_stream_chunk(chunk)
  local ok, event = pcall(vim.fn.json_decode, chunk)
  if not ok or type(event) ~= "table" then
    return nil
  end
  if event.type == "system" and event.subtype == "init" and event.tools and #event.tools > 0 then
    return nil, "Amp started with tools enabled; request cancelled"
  end
  if event.type == "result" then
    if event.is_error then
      return nil, event.error or "Amp request failed"
    end
    return event.result
  end
  -- The result repeats the assistant message. Read only the result to avoid duplicates.
  return nil
end

return M
