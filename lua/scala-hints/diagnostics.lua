local async = require('plenary.async')
local utils = require('scala-hints.utils')
local query = require('scala-hints.query')
local libs = require('scala-hints.libs')
local constants = require('scala-hints.constants')
local diagnostics_config = require('scala-hints.diagnostics_config')
local logger = require('scala-hints.logger').new('diagnostics')

local source = constants.source

local M = {}

local function make_diagnostic(result, query_name, query_def)
  local severity = diagnostics_config.resolve(query_name, query_def)
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
    for query_name, query_def in pairs(libs.get_all_queries()) do
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
      vim.notify(string.format('[%s]: Failed to collect diagnostics: %s', source, diagnostics), vim.log.levels.WARN)
      done(nil)
    end
  end)
end

return M
