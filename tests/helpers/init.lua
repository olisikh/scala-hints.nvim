--- Test helper utilities for scala-hints.nvim
---
--- Provides functions to:
---   - Create scratch buffers with Scala source and parse with Treesitter
---   - Run a specific query definition against a buffer
---   - Mock/restore LSP-dependent functions (hover_node_and_match, hover_predicate)
---   - Assert result shapes

local H = {}

--- Create a scratch buffer populated with the given Scala source lines.
--- Parses the buffer with tree-sitter-scala and returns the buffer number and root node.
---
---@param source string Scala source code (newlines for multiple lines)
---@return integer bufnr
---@return TSNode root
function H.parse_scala(source)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'scala')

  local lines = vim.split(source, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local parser = vim.treesitter.get_parser(bufnr, 'scala')
  local tree = parser:parse()[1]
  local root = tree:root()

  return bufnr, root
end

--- Wipe the scratch buffer created by parse_scala.
---@param bufnr integer buffer number
function H.cleanup_buf(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

--- Run a query definition's iter_matches + handler against a buffer, collecting results.
--- Returns the normalized { ready, pending } shape.
---
---@param bufnr integer buffer number
---@param root TSNode root of the parse tree
---@param query_def table { query = TSQuery, handler = fn(bufnr, matches) }
---@return table[] ready  ready results
---@return function[] pending  pending thunks (for async handlers)
function H.run_handler(bufnr, root, query_def)
  local all_ready = {}
  local all_pending = {}
  local start_line = 0
  local end_line = vim.api.nvim_buf_line_count(bufnr)

  for _, matches, _ in query_def.query:iter_matches(root, bufnr, start_line, end_line + 1) do
    local ok, result = pcall(query_def.handler, bufnr, matches)
    assert(ok, 'handler error: ' .. tostring(result))

    if result == nil then
      -- skip
    elseif result.ready ~= nil or result.pending ~= nil then
      for _, item in ipairs(result.ready or {}) do
        table.insert(all_ready, item)
      end
      for _, thunk in ipairs(result.pending or {}) do
        table.insert(all_pending, thunk)
      end
    else
      -- Plain array of results
      for _, item in ipairs(result) do
        table.insert(all_ready, item)
      end
    end
  end

  return all_ready, all_pending
end

--- Run the full query engine (query.run_query) against a buffer for a specific query_def.
--- This tests the engine itself, not just the handler.
---
---@param bufnr integer buffer number
---@param root TSNode root of the parse tree
---@param query_name string name of the query (for error messages)
---@param query_def table { query = TSQuery, handler = fn }
---@param callback function transforms a single result item
---@return table[] results collected ready results via callback
function H.run_query_engine(bufnr, root, query_name, query_def, callback)
  local query_mod = require('scala-hints.query')
  local results = {}

  local thunk = query_mod.run_query({
    bufnr = bufnr,
    root = root,
    query_name = query_name,
    query_def = query_def,
    start_line = 0,
    end_line = vim.api.nvim_buf_line_count(bufnr),
    callback = callback or function(item)
      return item
    end,
  })

  -- The thunk expects a callback that receives the ready results
  thunk(function(res)
    results = res
  end)

  return results
end

------------------------------------------------------------------------
-- LSP mocking
------------------------------------------------------------------------

local _original_hover_node_and_match = nil
local _original_hover_predicate = nil

--- Mock utils.hover_node_and_match to return a fixed value.
--- Call H.restore_mocks() in after_each to restore.
---@param return_value boolean value the mock should return
function H.mock_hover_node_and_match(return_value)
  local utils = require('scala-hints.utils')
  if _original_hover_node_and_match == nil then
    _original_hover_node_and_match = utils.hover_node_and_match
  end
  utils.hover_node_and_match = function(_bufnr, _node, _predicate)
    return return_value
  end
end

--- Mock semantic.hover_predicate to immediately call cb with a fixed value.
--- Call H.restore_mocks() in after_each to restore.
---@param return_value boolean value passed to the callback
function H.mock_hover_predicate(return_value)
  local semantic = require('scala-hints.semantic')
  if _original_hover_predicate == nil then
    _original_hover_predicate = semantic.hover_predicate
  end
  semantic.hover_predicate = function(_bufnr, _node, _predicate, cb, _opts)
    cb(return_value)
  end
end

--- Restore all mocked functions to originals.
function H.restore_mocks()
  if _original_hover_node_and_match then
    local utils = require('scala-hints.utils')
    utils.hover_node_and_match = _original_hover_node_and_match
    _original_hover_node_and_match = nil
  end
  if _original_hover_predicate then
    local semantic = require('scala-hints.semantic')
    semantic.hover_predicate = _original_hover_predicate
    _original_hover_predicate = nil
  end
end

--- Resolve all pending thunks and return the collected results.
--- Calls each thunk with a done callback that collects non-nil items.
---@param pending function[] array of pending thunks
---@return table[] results collected from resolved thunks
function H.resolve_pending(pending)
  local results = {}
  for _, thunk in ipairs(pending) do
    thunk(function(item)
      if item ~= nil then
        table.insert(results, item)
      end
    end)
  end
  return results
end

------------------------------------------------------------------------
-- Assertion helpers
------------------------------------------------------------------------

--- Assert a result item has the expected shape and values.
---@param result table the result item
---@param expected table with optional keys: replacement, title, diagnostic, action
function H.assert_result(result, expected)
  assert(result ~= nil, 'expected a result, got nil')
  assert(result.diagnostic ~= nil, 'result missing diagnostic field')
  assert(result.action ~= nil, 'result missing action field')
  assert(result.replacement ~= nil, 'result missing replacement field')
  assert(result.title ~= nil, 'result missing title field')

  if expected.replacement then
    assert.are.equal(expected.replacement, result.replacement, 'replacement mismatch')
  end
  if expected.title then
    assert.are.equal(expected.title, result.title, 'title mismatch')
  end
  if expected.diagnostic then
    for k, v in pairs(expected.diagnostic) do
      assert.are.equal(v, result.diagnostic[k], 'diagnostic.' .. k .. ' mismatch')
    end
  end
  if expected.action then
    for k, v in pairs(expected.action) do
      assert.are.equal(v, result.action[k], 'action.' .. k .. ' mismatch')
    end
  end
end

return H
