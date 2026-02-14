--- Tests for the generic query execution engine (query.lua).
---
--- Verifies that run_query correctly handles:
---   - normal results
---   - nil / missing handlers
---   - handler errors
---   - callback errors
---   - the { ready, pending } shape
---   - nil query_def

local H = require('tests.helpers')
local query_engine = require('scala-hints.query')
local ts = vim.treesitter

describe('query engine (query.lua)', function()
  local bufnr, root

  before_each(function()
    -- Use a simple Scala source that we know tree-sitter-scala will parse
    local source = [[val x = ZIO.succeed(())]]
    bufnr, root = H.parse_scala(source)
  end)

  after_each(function()
    if bufnr then
      H.cleanup_buf(bufnr)
      bufnr = nil
    end
  end)

  ---------------------------------------------------------------------------
  -- nil query_def
  ---------------------------------------------------------------------------
  it('returns empty results when query_def is nil', function()
    local results = H.run_query_engine(bufnr, root, 'test_nil', nil, function(item)
      return item
    end)

    assert.are.equal(0, #results)
  end)

  ---------------------------------------------------------------------------
  -- nil query inside query_def
  ---------------------------------------------------------------------------
  it('returns empty results when query_def.query is nil', function()
    local results = H.run_query_engine(bufnr, root, 'test_nil_query', { query = nil, handler = function() end }, function(item)
      return item
    end)

    assert.are.equal(0, #results)
  end)

  ---------------------------------------------------------------------------
  -- nil handler
  ---------------------------------------------------------------------------
  it('returns empty results when handler is nil', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id)'),
      handler = nil,
    }

    local results = H.run_query_engine(bufnr, root, 'test_no_handler', qd, function(item)
      return item
    end)

    assert.are.equal(0, #results)
  end)

  ---------------------------------------------------------------------------
  -- handler that returns plain array
  ---------------------------------------------------------------------------
  it('processes plain array results from handler', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "ZIO"))'),
      handler = function(_bufnr, _matches)
        return {
          { diagnostic = { row = 0, start_col = 0, end_col = 3 }, action = {}, replacement = 'test', title = 'Test' },
        }
      end,
    }

    local results = H.run_query_engine(bufnr, root, 'test_plain', qd, function(item)
      return item
    end)

    assert.are.equal(1, #results)
    assert.are.equal('test', results[1].replacement)
  end)

  ---------------------------------------------------------------------------
  -- handler that returns { ready, pending }
  ---------------------------------------------------------------------------
  it('processes ready items from { ready, pending } result shape', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "ZIO"))'),
      handler = function(_bufnr, _matches)
        return {
          ready = {
            { diagnostic = { row = 0, start_col = 0, end_col = 3 }, action = {}, replacement = 'ready_item', title = 'T' },
          },
          pending = {},
        }
      end,
    }

    local results = H.run_query_engine(bufnr, root, 'test_ready', qd, function(item)
      return item
    end)

    assert.are.equal(1, #results)
    assert.are.equal('ready_item', results[1].replacement)
  end)

  ---------------------------------------------------------------------------
  -- handler that returns nil
  ---------------------------------------------------------------------------
  it('handles nil return from handler gracefully', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "ZIO"))'),
      handler = function(_bufnr, _matches)
        return nil
      end,
    }

    local results = H.run_query_engine(bufnr, root, 'test_nil_return', qd, function(item)
      return item
    end)

    assert.are.equal(0, #results)
  end)

  ---------------------------------------------------------------------------
  -- handler that throws an error
  ---------------------------------------------------------------------------
  it('handles handler error gracefully (no crash)', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "ZIO"))'),
      handler = function(_bufnr, _matches)
        error('intentional test error')
      end,
    }

    -- Should not crash — engine uses pcall
    local results = H.run_query_engine(bufnr, root, 'test_error', qd, function(item)
      return item
    end)

    assert.are.equal(0, #results)
  end)

  ---------------------------------------------------------------------------
  -- callback that throws an error
  ---------------------------------------------------------------------------
  it('handles callback error gracefully (no crash)', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "ZIO"))'),
      handler = function(_bufnr, _matches)
        return {
          { diagnostic = {}, action = {}, replacement = 't', title = 'T' },
        }
      end,
    }

    local results = H.run_query_engine(bufnr, root, 'test_cb_error', qd, function(_item)
      error('callback error')
    end)

    -- The callback error is caught by pcall; no results are added
    assert.are.equal(0, #results)
  end)

  ---------------------------------------------------------------------------
  -- callback transforms results
  ---------------------------------------------------------------------------
  it('applies callback transformation to each result', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "ZIO"))'),
      handler = function(_bufnr, _matches)
        return {
          { diagnostic = { row = 0 }, action = {}, replacement = 'r', title = 'T' },
        }
      end,
    }

    local results = H.run_query_engine(bufnr, root, 'test_transform', qd, function(item)
      return { transformed = true, original = item }
    end)

    assert.are.equal(1, #results)
    assert.is_true(results[1].transformed)
    assert.are.equal('r', results[1].original.replacement)
  end)

  ---------------------------------------------------------------------------
  -- no matches
  ---------------------------------------------------------------------------
  it('returns empty results when query matches nothing', function()
    local qd = {
      query = ts.query.parse('scala', '((identifier) @id (#eq? @id "NONEXISTENT_SYMBOL"))'),
      handler = function(_bufnr, _matches)
        return { { diagnostic = {}, action = {}, replacement = 'x', title = 'X' } }
      end,
    }

    local results = H.run_query_engine(bufnr, root, 'test_no_match', qd, function(item)
      return item
    end)

    assert.are.equal(0, #results)
  end)
end)
