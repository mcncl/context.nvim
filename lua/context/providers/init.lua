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
-- build_request(prompt, context_text, filetype, config) -> { url, headers, body }
--   Build the HTTP request for the API
--   filetype is the buffer's filetype (e.g., "lua", "python", "go")
--
-- parse_stream_chunk(chunk) -> string|nil
--   Extract text delta from a streaming chunk, or nil if no text

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
