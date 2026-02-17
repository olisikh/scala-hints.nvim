local utils = require('scala-hints.utils')

local M = {}

local ranks = {
  Functor = 1,
  Apply = 2,
  FlatMap = 3,      -- NEW
  Applicative = 4,  -- was 3
  Monad = 5,        -- was 4
  MonadError = 6,   -- was 5
  Sync = 7,         -- was 6
}

local known = {}
for name, _ in pairs(ranks) do
  known[name] = true
end

local state = {}

local function buf_state(bufnr)
  local s = state[bufnr]
  if not s then
    s = { tick = 0, cache = {} }
    state[bufnr] = s
  end
  return s
end

local function is_def_text(text)
  if not text then
    return false
  end
  local trimmed = vim.trim(text)
  return trimmed:match('^def%s')
    or trimmed:match('^inline%s+def%s')
    or trimmed:match('^override%s+def%s')
    or trimmed:match('^private%s+def%s')
    or trimmed:match('^protected%s+def%s')
end

local function find_enclosing_def(bufnr, node)
  local current = node
  while current do
    local text = utils.get_node_text(bufnr, current)
    if is_def_text(text) then
      return current
    end
    current = current:parent()
  end
  return nil
end

local function def_key(node)
  local sr, sc, er, ec = node:range()
  return table.concat({ sr, sc, er, ec }, ':')
end

local function extract_header(text)
  local header = text
  local eq_index = header:find('=')
  if eq_index then
    header = header:sub(1, eq_index - 1)
  end
  local brace_index = header:find('{')
  if brace_index then
    header = header:sub(1, brace_index - 1)
  end
  return header
end

local function extract_context_bounds(header, evidence)
  local def_index = header:find('%f[%w]def%f[%W]')
  if not def_index then
    return
  end

  local after_def = header:sub(def_index)
  local paren_index = after_def:find('%(')
  if paren_index then
    after_def = after_def:sub(1, paren_index - 1)
  end

  for segment in after_def:gmatch('%b[]') do
    for cls in segment:gmatch(':%s*([%w_%.]+)') do
      local name = cls:match('([%w_]+)$')
      if name and known[name] then
        evidence[name] = true
      end
    end
  end
end

local function extract_param_evidence(header, evidence)
  for cls in header:gmatch('implicit%s+[%w_]+%s*:%s*([%w_%.]+)%s*%[') do
    local name = cls:match('([%w_]+)$')
    if name and known[name] then
      evidence[name] = true
    end
  end

  for cls in header:gmatch('using%s+[%w_]+%s*:%s*([%w_%.]+)%s*%[') do
    local name = cls:match('([%w_]+)$')
    if name and known[name] then
      evidence[name] = true
    end
  end

  for cls in header:gmatch('using%s+([%w_%.]+)%s*%[') do
    local name = cls:match('([%w_]+)$')
    if name and known[name] then
      evidence[name] = true
    end
  end
end

local function extract_evidence_from_def(bufnr, def_node)
  local def_text = utils.get_node_text(bufnr, def_node)
  local header = extract_header(def_text)
  local evidence = {}

  extract_context_bounds(header, evidence)
  extract_param_evidence(header, evidence)

  return evidence
end

local function satisfies(evidence, required)
  local req_rank = ranks[required]
  if not req_rank then
    return false
  end

  for name, _ in pairs(evidence) do
    local rank = ranks[name]
    if rank and rank >= req_rank then
      return true
    end
  end

  return false
end

function M.has_capability(bufnr, node, required)
  if not node or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local def_node = find_enclosing_def(bufnr, node)
  if not def_node then
    return false
  end

  local s = buf_state(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if s.tick ~= tick then
    s.tick = tick
    s.cache = {}
  end

  local key = def_key(def_node)
  local evidence = s.cache[key]
  if not evidence then
    evidence = extract_evidence_from_def(bufnr, def_node)
    s.cache[key] = evidence
  end

  return satisfies(evidence, required)
end

return M
