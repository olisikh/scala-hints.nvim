--- Library registry — aggregates query definitions from all effect-library modules.
---
--- Each library module must return a table with:
---   name    = string   (e.g. "zio")
---   queries = table    { query_name -> { query = TSQuery, handler = fn } }

local M = {}

--- List of library modules to load.
--- Add new libraries here.
local lib_modules = {
  'scala-hints.libs.zio',
  -- 'scala-hints.libs.cats',
  -- 'scala-hints.libs.kyo',
}

--- Cached merged query table: { "lib/query_name" -> query_def }
local _all_queries = nil

--- Load and merge all queries from registered libs.
--- Queries are namespaced as "lib_name/query_name" to avoid collisions.
---@return table<string, table> all_queries
function M.get_all_queries()
  if _all_queries then
    return _all_queries
  end

  _all_queries = {}
  for _, mod_name in ipairs(lib_modules) do
    local ok, lib = pcall(require, mod_name)
    if ok and lib and lib.queries then
      for query_name, query_def in pairs(lib.queries) do
        local full_name = lib.name .. '/' .. query_name
        _all_queries[full_name] = query_def
      end
    elseif not ok then
      vim.notify('[scala-hints] Failed to load lib module: ' .. mod_name .. ': ' .. tostring(lib), vim.log.levels.WARN)
    end
  end

  return _all_queries
end

--- Force reload all library modules (useful after config changes).
function M.reload()
  _all_queries = nil
  for _, mod_name in ipairs(lib_modules) do
    package.loaded[mod_name] = nil
  end
end

return M
