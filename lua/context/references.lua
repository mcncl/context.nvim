-- Extract @file references from prompt text and resolve to context entries
local M = {}

local files = require("context.files")
local config = require("context.config")

-- Pattern: @ preceded by whitespace or start-of-line, followed by a path
-- that contains / or a file extension (to avoid matching emails like user@domain.com)
local function is_file_ref(token)
  -- Must contain a / or a file extension (dot followed by letters at the end)
  return token:find("/") ~= nil or token:match("%.[%w]+$") ~= nil
end

-- Extract @path references from prompt text
-- Returns list of path strings
function M.extract_references(text)
  local refs = {}
  local seen = {}

  -- Match @path tokens: @ at start of line or after whitespace
  for ref in text:gmatch("^@(%S+)") do
    if is_file_ref(ref) and not seen[ref] then
      table.insert(refs, ref)
      seen[ref] = true
    end
  end
  for ref in text:gmatch("%s@(%S+)") do
    if is_file_ref(ref) and not seen[ref] then
      table.insert(refs, ref)
      seen[ref] = true
    end
  end

  return refs
end

-- Remove @path references from prompt text, returning clean prompt
local function clean_prompt(text, refs)
  local clean = text
  for _, ref in ipairs(refs) do
    -- Escape magic pattern characters in the path
    local escaped = ref:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    -- Remove @path (with optional surrounding whitespace cleanup)
    clean = clean:gsub("%s*@" .. escaped, "")
  end
  -- Trim leading/trailing whitespace
  clean = clean:match("^%s*(.-)%s*$")
  return clean
end

-- Resolve @path references in prompt text
-- Returns { clean_prompt = string, contexts = array }
-- Each context entry: { text = string, filetype = string, source = string, mode = string }
-- The first entry in contexts is always the primary (selected code) context
function M.resolve(text, base_context)
  local refs = M.extract_references(text)
  local cfg = config.get()
  local max_refs = (cfg.files and cfg.files.max_references) or 5

  -- Build contexts array starting with the primary context
  -- Preserve all selection fields (start_line, end_line, etc.) needed by stream.lua
  local primary = vim.tbl_extend("force", base_context, {
    source = base_context.mode,
  })
  local contexts = { primary }

  if #refs == 0 then
    return {
      clean_prompt = text,
      contexts = contexts,
    }
  end

  -- Cap references
  if #refs > max_refs then
    vim.notify(
      string.format("Context: too many @file references (%d), using first %d", #refs, max_refs),
      vim.log.levels.WARN
    )
    local capped = {}
    for i = 1, max_refs do
      capped[i] = refs[i]
    end
    refs = capped
  end

  -- Resolve each reference
  for _, ref in ipairs(refs) do
    local content, err = files.read_file(ref)
    if content then
      table.insert(contexts, {
        text = content,
        filetype = files.detect_filetype(ref),
        source = ref,
        mode = "reference",
      })
    else
      vim.notify("Context: " .. (err or ("cannot read: " .. ref)), vim.log.levels.WARN)
    end
  end

  return {
    clean_prompt = clean_prompt(text, refs),
    contexts = contexts,
  }
end

return M
