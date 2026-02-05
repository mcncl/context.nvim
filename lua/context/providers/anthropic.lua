-- Anthropic Claude API provider
local M = {}

function M.build_request(prompt, context_text, filetype, config)
  -- Check config first, then fall back to env var (lazy evaluation)
  local api_key = config.api_key
  if not api_key or api_key == "" then
    api_key = vim.env.ANTHROPIC_API_KEY
  end
  if not api_key or api_key == "" then
    error("Anthropic API key not configured. Set ANTHROPIC_API_KEY or configure in setup()")
  end

  local system_prompt = require("context.config").get().system_prompt
  local lang = filetype ~= "" and filetype or ""

  local body = vim.fn.json_encode({
    model = config.model or "claude-sonnet-4-5",
    max_tokens = config.max_tokens or 4096,
    stream = true,
    system = system_prompt,
    messages = {
      {
        role = "user",
        content = string.format("Code context:\n```%s\n%s\n```\n\nInstruction: %s", lang, context_text, prompt),
      },
    },
  })

  return {
    url = "https://api.anthropic.com/v1/messages",
    headers = {
      ["Content-Type"] = "application/json",
      ["x-api-key"] = api_key,
      ["anthropic-version"] = "2023-06-01",
    },
    body = body,
  }
end

function M.parse_stream_chunk(chunk)
  -- Anthropic SSE format:
  -- event: content_block_delta
  -- data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}
  if not chunk or chunk == "" then
    return nil
  end

  -- Find data: anywhere in the chunk (may be preceded by event: line)
  local data = chunk:match("data: (.+)")
  if not data then
    return nil
  end

  local ok, parsed = pcall(vim.fn.json_decode, data)
  if not ok then
    return nil
  end

  -- Extract text from content_block_delta events with text_delta type
  if parsed.type == "content_block_delta" and parsed.delta then
    if parsed.delta.type == "text_delta" and parsed.delta.text then
      return parsed.delta.text
    end
  end

  return nil
end

return M
