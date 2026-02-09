-- OpenAI Responses API provider
local M = {}

function M.build_request(prompt, contexts, config)
  -- Check config first, then fall back to env var (lazy evaluation)
  local api_key = config.api_key
  if not api_key or api_key == "" then
    api_key = vim.env.OPENAI_API_KEY
  end
  if not api_key or api_key == "" then
    error("OpenAI API key not configured. Set OPENAI_API_KEY or configure in setup()")
  end

  local system_prompt = require("context.config").get().system_prompt
  local providers = require("context.providers")
  local user_content = providers.format_contexts(prompt, contexts)

  local body = vim.fn.json_encode({
    model = config.model or "gpt-4o-mini",
    max_output_tokens = config.max_tokens or 4096,
    stream = true,
    input = {
      {
        role = "developer",
        content = system_prompt,
      },
      {
        role = "user",
        content = user_content,
      },
    },
  })

  return {
    url = "https://api.openai.com/v1/responses",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    },
    body = body,
  }
end

function M.parse_stream_chunk(chunk)
  -- Responses API SSE format:
  -- event: response.output_text.delta
  -- data: {"type":"response.output_text.delta","delta":"Hello",...}
  if not chunk or chunk == "" then
    return nil
  end

  -- Find data: anywhere in the chunk
  local data = chunk:match("data: (.+)")
  if not data then
    return nil
  end

  local ok, parsed = pcall(vim.fn.json_decode, data)
  if not ok then
    return nil
  end

  -- Extract text from output_text.delta events
  if parsed.type == "response.output_text.delta" and parsed.delta then
    return parsed.delta
  end

  return nil
end

return M
