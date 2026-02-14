--- Library registry — aggregates query definitions from all effect-library modules.
---
--- Each library module must return a table with:
---   name    = string   (e.g. "zio")
---   queries = table    { query_name -> { query = TSQuery, handler = fn } }
local logger = require('scala-hints.logger').new('libs-init')

local M = {}

--- List of libraries to load.
--- Add new libraries here.
local supported_libs = {
  'zio',
}

local levels = {
  ERROR = vim.log.levels.ERROR,
  WARN = vim.log.levels.WARN,
  INFO = vim.log.levels.INFO,
}

--- Cached merged query table: { "lib/query_name" -> query_def }
local _all_queries = nil

--- Load and merge all queries from registered libs.
--- Queries are namespaced as "lib_name/query_name" to avoid collisions.
---@param excluded_libs table<string> list of lib names to exclude (e.g. { "zio", "cats-effect", "kyo", "yaes" })
---@return table<string, table> all_queries
function M.get_all_queries(excluded_libs)
  if _all_queries then
    return _all_queries
  end

  excluded_libs = excluded_libs or {}

  _all_queries = {}
  for _, lib_name in ipairs(supported_libs) do
    if vim.tbl_contains(excluded_libs, lib_name) then
      logger.info('Skipping excluded lib: ' .. lib_name)
    else
      local ok, lib_module = pcall(require, 'scala-hints.libs.' .. lib_name)
      if ok and lib_module and lib_module.queries then
        for query_name, query_def in pairs(lib_module.queries) do
          local full_name = lib_module.name .. '/' .. query_name
          _all_queries[full_name] = query_def
        end
      elseif not ok then
        logger.warn('Failed to load lib module: ' .. lib_module .. ': ' .. tostring(lib_module))
      end
    end
  end

  return _all_queries
end

--- Force reload all library modules (useful after config changes).
function M.reload()
  _all_queries = nil
  for _, mod_name in ipairs(supported_libs) do
    package.loaded[mod_name] = nil
  end
end

return M
