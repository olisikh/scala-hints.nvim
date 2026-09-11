local query = require('scala-hints.query')
local libs = require('scala-hints.libs')
local constants = require('scala-hints.constants')
local logger = require('scala-hints.logger').new('diagnostics')

local source = constants.name

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
  -- Enter on a later event-loop turn so LSP didSave and workspace queue
  -- callbacks return without parsing or traversing Treesitter immediately.
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      done(nil)
      return
    end

    local ok_parser, parser_or_err = pcall(vim.treesitter.get_parser, bufnr, 'scala')
    if not ok_parser then
      logger.warn(string.format('Failed to get Scala parser: %s', parser_or_err))
      done(nil)
      return
    end

    local ok_tree, tree_or_err = pcall(function()
      return parser_or_err:parse()[1]
    end)
    if not ok_tree or not tree_or_err then
      logger.warn(string.format('Failed to parse Scala buffer: %s', tree_or_err))
      done(nil)
      return
    end

    local root = tree_or_err:root()
    local start_line = 0
    local end_line = vim.api.nvim_buf_line_count(bufnr)
    local queries = {}
    for query_name, query_def in pairs(libs.get_all_queries(settings.excluded_libs)) do
      table.insert(queries, { name = query_name, definition = query_def })
    end
    table.sort(queries, function(left, right)
      return left.name < right.name
    end)

    local completed = false
    local diagnostics = {}
    local next_query = 1

    local function finish(results)
      if completed then
        return
      end
      completed = true
      done(results)
    end

    -- Preserve the existing whole-buffer timeout without blocking the UI.
    vim.defer_fn(function()
      if not completed then
        logger.warn('Timed out collecting diagnostics after 30000ms')
        finish(nil)
      end
    end, 30000)

    local function run_next()
      if completed then
        return
      end

      local entry = queries[next_query]
      next_query = next_query + 1
      if not entry then
        finish(diagnostics)
        return
      end

      local thunk = query.run_query({
        bufnr = bufnr,
        root = root,
        query_name = entry.name,
        query_def = entry.definition,
        start_line = start_line,
        end_line = end_line,
        callback = function(item)
          return make_diagnostic(item, entry.name, entry.definition)
        end,
      })

      -- Run one query per event-loop turn. A query's asynchronous Metals work
      -- still uses semantic.lua's global request budget.
      vim.defer_fn(function()
        if completed then
          return
        end
        local ok, err = pcall(thunk, function(results)
          for _, diagnostic in ipairs(results or {}) do
            table.insert(diagnostics, diagnostic)
          end
          vim.defer_fn(run_next, 0)
        end)
        if not ok then
          logger.warn(string.format('Failed to run query %s: %s', entry.name, err))
          vim.defer_fn(run_next, 0)
        end
      end, 0)
    end

    run_next()
  end, 0)
end

return M
