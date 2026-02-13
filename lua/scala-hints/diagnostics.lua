local async = require('plenary.async')
local utils = require('scala-hints.utils')
local query = require('scala-hints.query')
local constants = require('scala-hints.constants')
local logger = require('scala-hints.logger').new('diagnostics')

local source = constants.source

local M = {}

local function make_diagnostic(result)
  local diagnostic = result.diagnostic
  return {
    lnum = diagnostic.row,
    col = diagnostic.start_col,
    end_lnum = diagnostic.row,
    end_col = diagnostic.end_col,
    message = result.title,
    source = source,
    severity = vim.diagnostic.severity.HINT,
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
    for _, query_name in ipairs(constants.query_names) do
      table.insert(
        queries,
        async.wrap(
          query.run_query({
            bufnr = bufnr,
            root = root,
            query_name = query_name,
            start_line = start_line,
            end_line = end_line,
            callback = make_diagnostic,
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
