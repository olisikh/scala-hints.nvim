local parsers = require('nvim-treesitter.parsers')
local async = require('plenary.async')
local query = require('scala-hints.query')
local utils = require('scala-hints.utils')
local source = require('scala-hints.constants').source

local M = {}

local function make_code_action()
  return function(result)
    local action = result.action
    return {
      title = result.title,
      range = {
        start = { line = action.start_row, character = action.start_col },
        ['end'] = { line = action.end_row, character = action.end_col },
      },
      replacement = result.replacement,
    }
  end
end

function M.resolve_actions(bufnr, start_line, end_line, done)
  async.run(function()
    local root = parsers.get_tree_root(bufnr)

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
            callback = make_code_action(),
          }),
          1
        )
      )
    end

    local ok, actions = utils.run_or_timeout(function()
      return async.util.join(queries)
    end, 30000)

    if ok then
      done(utils.flatten_array(actions))
    else
      vim.notify(string.format('[%s]: Failed to collect actions: %s', source, actions), vim.log.levels.WARN)
      done(nil)
    end
  end)
end

return M
