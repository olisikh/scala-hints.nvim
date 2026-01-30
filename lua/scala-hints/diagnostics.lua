local parsers = require('nvim-treesitter.parsers')
local async = require('plenary.async')
local utils = require('scala-hints.utils')
local query = require('scala-hints.query')
local constants = require('scala-hints.constants')

local source = constants.source

local M = {}

local function make_diagnostic(result)
  local diagnostic = result.diagnostic
  return {
    row = diagnostic.row + 1,
    col = diagnostic.start_col + 1,
    end_col = diagnostic.end_col + 1,
    message = result.title,
    source = source,
    severity = vim.diagnostic.severity.HINT,
  }
end

function M.collect_diagnostics(bufnr, done)
  local root = parsers.get_tree_root(bufnr)

  local start_line = 0
  local end_line = vim.api.nvim_buf_line_count(bufnr)

  local query_names = {
    'succeed_unit',
    'fail_exception_or_die',
    'map_unit',
    'as_unit',
    'zip_right_unit',
    'zip_right_value',
    'zip_left_value',
    'flat_map_value',
    'map_value',
    'catch_all_unit',
    'fold_cause_ignore',
    'or_else_fail',
    'or_else_fail2',
    'or_else_fail3',
    'zio_type',
    'zlayer_type',
    'zio_none',
    'zio_some',
    'zio_either',
    'zio_foreach',
  }

  local queries = {}
  for _, query_name in ipairs(query_names) do
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
end

return M
