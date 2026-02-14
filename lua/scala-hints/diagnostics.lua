local async = require('plenary.async')
local utils = require('scala-hints.utils')
local query = require('scala-hints.query')
local libs = require('scala-hints.libs')
local constants = require('scala-hints.constants')
local logger = require('scala-hints.logger').new('diagnostics')

local source = constants.plugin_name

local M = {}

local severity_map = {
  ERROR = vim.diagnostic.severity.ERROR,
  WARN = vim.diagnostic.severity.WARN,
  WARNING = vim.diagnostic.severity.WARN,
  INFO = vim.diagnostic.severity.INFO,
  HINT = vim.diagnostic.severity.HINT,
}

local settings = {
  excluded_libs = {},
  default_severity = vim.diagnostic.severity.HINT,
  overrides = {},
}

local function normalize_severity(value)
  if value == nil then
    return nil
  end

  if type(value) == 'number' then
    return value
  end

  if type(value) ~= 'string' then
    return nil
  end

  local key = string.upper(value)
  if key == 'OFF' or key == 'NONE' then
    return false
  end

  return severity_map[key]
end

function M.configure(opts)
  local diagnostics = opts and opts.diagnostics or nil
  if not diagnostics then
    return
  end

  local default_sev = normalize_severity(diagnostics.default_severity)
  if default_sev ~= nil then
    settings.default_severity = default_sev
  end

  if type(diagnostics.overrides) == 'table' then
    settings.overrides = diagnostics.overrides
  end

  if type(diagnostics.excluded_libs) == 'table' then
    settings.excluded_libs = diagnostics.excluded_libs
  end
end

local function resolve_severity(query_name, query_def)
  local override = settings.overrides and settings.overrides[query_name]
  local override_sev = normalize_severity(override)
  if override_sev ~= nil then
    return override_sev
  end

  local def_sev = query_def and query_def.diagnostic_severity
  local normalized = normalize_severity(def_sev)
  if normalized ~= nil then
    return normalized
  end

  return settings.default_severity
end

local function make_diagnostic(result, query_name, query_def)
  local severity = resolve_severity(query_name, query_def)
  if severity == false then
    return nil
  end

  local diagnostic = result.diagnostic
  return {
    lnum = diagnostic.row,
    col = diagnostic.start_col,
    end_lnum = diagnostic.row,
    end_col = diagnostic.end_col,
    message = result.title,
    source = source,
    severity = severity or vim.diagnostic.severity.INFO,
  }
end

function M.collect_diagnostics(bufnr, done)
  async.run(function()
    local parser = vim.treesitter.get_parser(bufnr, 'scala')
    local tree = parser:parse()[1]
    local root = tree:root()

    local start_line = 0
    local end_line = vim.api.nvim_buf_line_count(bufnr)

    local queries = {}
    for query_name, query_def in pairs(libs.get_all_queries(settings.excluded_libs)) do
      table.insert(
        queries,
        async.wrap(
          query.run_query({
            bufnr = bufnr,
            root = root,
            query_name = query_name,
            query_def = query_def,
            start_line = start_line,
            end_line = end_line,
            callback = function(item)
              return make_diagnostic(item, query_name, query_def)
            end,
          }),
          1
        )
      )
    end

    local ok, diagnostics = utils.run_or_timeout(function()
      return async.util.join(queries)
    end, 30000)

    if ok then
      done(utils.flatten_array(diagnostics))
    else
      logger.warn(string.format('Failed to collect diagnostics: %s', diagnostics))
      done(nil)
    end
  end)
end

return M
