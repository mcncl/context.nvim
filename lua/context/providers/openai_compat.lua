-- OpenAI-compatible API provider (Ollama, LM Studio, etc.)
local M = {}

function M.build_request(prompt, context_text, filetype, config)
  local base_url = config.base_url or "http://localhost:11434/v1"
  -- Remove trailing slash if present
  base_url = base_url:gsub("/$", "")

  local system_prompt = require("context.config").get().system_prompt
  local lang = filetype ~= "" and filetype or ""

  local body = vim.fn.json_encode({
    model = config.model or "llama3",
    max_tokens = config.max_tokens or 4096,
    stream = true,
    messages = {
      {
        role = "system",
        content = system_prompt,
      },
      {
        role = "user",
        content = string.format("Code context:\n```%s\n%s\n```\n\nInstruction: %s", lang, context_text, prompt),
      },
    },
  })

  local headers = {
    ["Content-Type"] = "application/json",
  }

  -- Only add Authorization header if api_key is provided
  if config.api_key and config.api_key ~= "" then
    headers["Authorization"] = "Bearer " .. config.api_key
  end

  return {
    url = base_url .. "/chat/completions",
    headers = headers,
    body = body,
  }
end

function M.parse_stream_chunk(chunk)
  -- Same SSE format as OpenAI: data: {"choices": [{"delta": {"content": "..."}}]}
  if not chunk or chunk == "" then
    return nil
  end

  -- Find data: anywhere in the chunk (flexible matching)
  local data = chunk:match("data: (.+)")
  if not data then
    return nil
  end

  if data == "[DONE]" then
    return nil
  end

  local ok, parsed = pcall(vim.fn.json_decode, data)
  if not ok then
    return nil
  end

  if parsed.choices and parsed.choices[1] and parsed.choices[1].delta then
    return parsed.choices[1].delta.content
  end

  return nil
end

return M
