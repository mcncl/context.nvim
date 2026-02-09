-- Provider interface and factory
local M = {}

local providers = {}

-- Register a provider
function M.register(name, provider)
  providers[name] = provider
end

-- Get a provider by name
function M.get(name)
  local provider = providers[name]
  if not provider then
    -- Try to load the provider module
    local ok, mod = pcall(require, "context.providers." .. name)
    if ok then
      providers[name] = mod
      return mod
    end
    error("Unknown provider: " .. name)
  end
  return provider
end

-- Provider interface definition (for documentation)
-- Each provider must implement:
--
-- build_request(prompt, contexts, config) -> { url, headers, body }
--   Build the HTTP request for the API
--   contexts is an array of { text, filetype, source, mode }
--
-- parse_stream_chunk(chunk) -> string|nil
--   Extract text delta from a streaming chunk, or nil if no text

-- Format contexts array into a single user message for the LLM
-- contexts is an array of { text, filetype, source, mode }
-- The first entry is always the primary (selected code) context
function M.format_contexts(prompt, contexts)
  local parts = {}

  for i, ctx in ipairs(contexts) do
    local lang = (ctx.filetype and ctx.filetype ~= "") and ctx.filetype or ""
    if i == 1 then
      -- Primary context (selected code)
      local label = string.format("Selected code (%s):", ctx.mode or "unknown")
      table.insert(parts, string.format("%s\n```%s\n%s\n```", label, lang, ctx.text))
    else
      -- Referenced file
      local label = string.format("Referenced file: %s", ctx.source or "unknown")
      table.insert(parts, string.format("%s\n```%s\n%s\n```", label, lang, ctx.text))
    end
  end

  table.insert(parts, string.format("Instruction: %s", prompt))

  return table.concat(parts, "\n\n")
end

-- Validate that a provider implements the required interface
function M.validate(provider)
  local required = { "build_request", "parse_stream_chunk" }
  for _, fn in ipairs(required) do
    if type(provider[fn]) ~= "function" then
      return false, "Provider missing required function: " .. fn
    end
  end
  return true
end

return M
