local semantic = require('scala-hints.semantic')

describe('semantic.hover_predicate caching', function()
  local bufnr
  local original_get_clients
  local original_defer_fn
  local original_make_position_params
  local fake_client

  local function make_node()
    return {
      range = function()
        return 0, 0, 0, 1
      end,
    }
  end

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'scala')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'x' })
    semantic.reset(bufnr)

    original_get_clients = vim.lsp.get_clients
    original_defer_fn = vim.defer_fn
    original_make_position_params = vim.lsp.util.make_position_params
    vim.lsp.util.make_position_params = function(_winid, _encoding)
      return {
        textDocument = { uri = 'file://test.scala' },
        position = { line = 0, character = 0 },
      }
    end

    fake_client = {
      request = function(_method, _params, _cb, _buf)
        -- overridden per-test
      end,
    }
    vim.lsp.get_clients = function(_opts)
      return { fake_client }
    end
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
    vim.defer_fn = original_defer_fn
    vim.lsp.util.make_position_params = original_make_position_params

    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('does not cache hover failures from timeouts', function()
    local call_count = 0
    fake_client.request = function(_method, _params, _cb, _buf)
      call_count = call_count + 1
      -- do not call cb to force timeout path
    end

    vim.defer_fn = function(fn, _ms)
      fn()
    end

    local node = make_node()
    local results = {}
    semantic.hover_predicate(bufnr, node, function(_value)
      return true
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(1, #results)
    assert.are.equal(false, results[1])
    assert.are.equal(3, call_count)

    semantic.hover_predicate(bufnr, node, function(_value)
      return true
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(2, #results)
    assert.are.equal(false, results[2])
    assert.are.equal(6, call_count)
  end)

  it('caches hover results when LSP responds', function()
    local call_count = 0
    fake_client.request = function(_method, _params, cb, _buf)
      call_count = call_count + 1
      cb(nil, { contents = { value = 'ZIO[Any, Nothing, Int]' } })
    end

    vim.defer_fn = function(_fn, _ms)
      -- no-op to avoid timeout path
    end

    local node = make_node()
    local results = {}
    semantic.hover_predicate(bufnr, node, function(value)
      return value:find('ZIO%[') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(1, #results)
    assert.are.equal(true, results[1])
    assert.are.equal(1, call_count)

    semantic.hover_predicate(bufnr, node, function(value)
      return value:find('ZIO%[') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(2, #results)
    assert.are.equal(true, results[2])
    assert.are.equal(1, call_count)
  end)

  it('does not cache false predicate results', function()
    local call_count = 0
    fake_client.request = function(_method, _params, cb, _buf)
      call_count = call_count + 1
      cb(nil, { contents = { value = 'NotZIO' } })
    end

    vim.defer_fn = function(_fn, _ms)
      -- no-op to avoid timeout path
    end

    local node = make_node()
    local results = {}
    semantic.hover_predicate(bufnr, node, function(value)
      return value:find('ZIO%[') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(1, #results)
    assert.are.equal(false, results[1])
    assert.are.equal(1, call_count)

    semantic.hover_predicate(bufnr, node, function(value)
      return value:find('ZIO%[') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(2, #results)
    assert.are.equal(false, results[2])
    assert.are.equal(2, call_count)
  end)

end)
