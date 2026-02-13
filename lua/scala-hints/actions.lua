local async = require('plenary.async')
local query = require('scala-hints.query')
local utils = require('scala-hints.utils')
local constants = require('scala-hints.constants')

local source = constants.source

local M = {}

---Transform a query result into an LSP code action shape
---@param result table query handler result with title, action, and replacement
---@return table code_action
local function make_code_action(result)
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

function M.resolve_actions(bufnr, start_line, end_line, done)
  async.run(function()
    local parser = vim.treesitter.get_parser(bufnr, 'scala')
    local tree = parser:parse()[1]
    local root = tree:root()

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
            callback = make_code_action,
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
