local semantic = require('scala-hints.semantic')

describe('semantic.type_definition_predicate caching', function()
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

  it('does not cache type_definition failures from timeouts', function()
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
    semantic.type_definition_predicate(bufnr, node, function(_uri)
      return true
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(1, #results)
    assert.are.equal(false, results[1])
    assert.are.equal(3, call_count)

    semantic.type_definition_predicate(bufnr, node, function(_uri)
      return true
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(2, #results)
    assert.are.equal(false, results[2])
    assert.are.equal(6, call_count)
  end)

  it('caches type_definition results when LSP responds', function()
    local call_count = 0
    fake_client.request = function(_method, _params, cb, _buf)
      call_count = call_count + 1
      cb(nil, { { targetUri = 'file:///path/to/zio/ZIO.scala' } })
    end

    vim.defer_fn = function(_fn, _ms)
      -- no-op to avoid timeout path
    end

    local node = make_node()
    local results = {}
    semantic.type_definition_predicate(bufnr, node, function(uri)
      return uri:find('/zio/') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(1, #results)
    assert.are.equal(true, results[1])
    assert.are.equal(1, call_count)

    semantic.type_definition_predicate(bufnr, node, function(uri)
      return uri:find('/zio/') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(2, #results)
    assert.are.equal(true, results[2])
    assert.are.equal(1, call_count)
  end)

  it('caches URIs even when predicate returns false', function()
    local call_count = 0
    fake_client.request = function(_method, _params, cb, _buf)
      call_count = call_count + 1
      cb(nil, { { targetUri = 'file:///path/to/cats/effect/IO.scala' } })
    end

    vim.defer_fn = function(_fn, _ms)
      -- no-op to avoid timeout path
    end

    local node = make_node()
    local results = {}
    -- predicate looking for ZIO won't match a cats-effect URI
    semantic.type_definition_predicate(bufnr, node, function(uri)
      return uri:find('/zio/') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(1, #results)
    assert.are.equal(false, results[1])
    assert.are.equal(1, call_count)

    -- URIs are cached even when the predicate doesn't match,
    -- so the second call is a cache hit (no new LSP request)
    semantic.type_definition_predicate(bufnr, node, function(uri)
      return uri:find('/zio/') ~= nil
    end, function(result)
      table.insert(results, result)
    end)

    assert.are.equal(2, #results)
    assert.are.equal(false, results[2])
    assert.are.equal(1, call_count) -- still 1: cache hit
  end)

  it('evaluates different predicates against cached URIs independently', function()
    local call_count = 0
    fake_client.request = function(_method, _params, cb, _buf)
      call_count = call_count + 1
      cb(nil, { { targetUri = 'file:///path/to/cats/effect/IO.scala' } })
    end

    vim.defer_fn = function(_fn, _ms)
      -- no-op
    end

    local node = make_node()

    -- First call: ZIO predicate → false (URI is cats-effect)
    local zio_result
    semantic.type_definition_predicate(bufnr, node, function(uri)
      return uri:find('/zio/') ~= nil
    end, function(result)
      zio_result = result
    end)
    assert.are.equal(false, zio_result)
    assert.are.equal(1, call_count)

    -- Second call: CE predicate → true (URI matches cats/effect)
    local ce_result
    semantic.type_definition_predicate(bufnr, node, function(uri)
      return uri:find('cats/effect') ~= nil
    end, function(result)
      ce_result = result
    end)
    assert.are.equal(true, ce_result)
    assert.are.equal(1, call_count) -- cache hit, no new LSP call
  end)

end)
