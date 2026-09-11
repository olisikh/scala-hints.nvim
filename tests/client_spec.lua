local client = require('scala-hints.client')
local diagnostics = require('scala-hints.diagnostics')

describe('scala-hints client refresh API', function()
  local bufnr
  local original_collect
  local original_lsp_start
  local original_get_client_by_id

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.scala')
    original_collect = diagnostics.collect_diagnostics
  end)

  after_each(function()
    diagnostics.collect_diagnostics = original_collect
    if original_lsp_start then
      vim.lsp.start = original_lsp_start
      vim.lsp.get_client_by_id = original_get_client_by_id
    end
    client.stop()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('publishes diagnostics and completes through the reusable refresh API', function()
    local published
    local completed
    client.rpc_start({
      notification = function(method, params)
        published = { method = method, params = params }
      end,
    })

    diagnostics.collect_diagnostics = function(_, done)
      done({
        {
          lnum = 0,
          col = 1,
          end_lnum = 0,
          end_col = 4,
          message = 'replace smell',
          severity = vim.diagnostic.severity.HINT,
          source = 'scala-hints',
        },
      })
    end

    assert.is_true(client.refresh_diagnostics(bufnr, {
      wait_for_metals = false,
      on_complete = function(ok)
        completed = ok
      end,
    }))

    assert.is_true(vim.wait(1000, function()
      return completed ~= nil
    end, 10))
    assert.is_true(completed)
    assert.are.equal('textDocument/publishDiagnostics', published.method)
    assert.are.equal(vim.uri_from_bufnr(bufnr), published.params.uri)
    assert.are.equal(1, #published.params.diagnostics)
  end)

  it('cancels readiness polling when the in-process client stops', function()
    local completed
    client.rpc_start({ notification = function() end })

    client.refresh_diagnostics(bufnr, {
      on_complete = function(ok)
        completed = ok
      end,
    })
    client.stop()

    assert.is_false(completed)
  end)

  it('does not publish an in-flight result through a replaced dispatcher', function()
    local first_published = false
    local second_published = false
    local completed
    local pending_collect

    client.rpc_start({
      notification = function()
        first_published = true
      end,
    })
    diagnostics.collect_diagnostics = function(_, done)
      pending_collect = done
    end

    client.refresh_diagnostics(bufnr, {
      wait_for_metals = false,
      on_complete = function(ok)
        completed = ok
      end,
    })
    assert.is_not_nil(pending_collect)

    client.stop()
    client.rpc_start({
      notification = function()
        second_published = true
      end,
    })
    pending_collect({})

    assert.is_true(vim.wait(1000, function()
      return completed ~= nil
    end, 10))
    assert.is_false(completed)
    assert.is_false(first_published)
    assert.is_false(second_published)
  end)

  it('ignores a delayed exit from a replaced in-process client', function()
    local configurations = {}
    local fake_clients = {}
    local published = false
    local completed

    original_lsp_start = vim.lsp.start
    original_get_client_by_id = vim.lsp.get_client_by_id
    vim.lsp.start = function(config)
      table.insert(configurations, config)
      local id = #configurations
      fake_clients[id] = {
        stopped = false,
        is_stopped = function(self)
          return self.stopped
        end,
        stop = function() end,
      }
      return id
    end
    vim.lsp.get_client_by_id = function(id)
      return fake_clients[id]
    end

    assert.are.equal(1, client.start(bufnr))
    client.rpc_start({ notification = function() end })
    fake_clients[1].stopped = true

    assert.are.equal(2, client.start(bufnr))
    client.rpc_start({
      notification = function()
        published = true
      end,
    })
    configurations[1].on_exit(0, 0)

    diagnostics.collect_diagnostics = function(_, done)
      done({})
    end
    client.refresh_diagnostics(bufnr, {
      wait_for_metals = false,
      on_complete = function(ok)
        completed = ok
      end,
    })

    assert.is_true(vim.wait(1000, function()
      return completed ~= nil
    end, 10))
    assert.is_true(completed)
    assert.is_true(published)
  end)

  it('clears the stopped dispatcher when replacement client startup fails', function()
    local published = false
    local completed

    original_lsp_start = vim.lsp.start
    original_get_client_by_id = vim.lsp.get_client_by_id
    vim.lsp.start = function()
      return nil
    end
    client.rpc_start({
      notification = function()
        published = true
      end,
    })

    assert.is_nil(client.start(bufnr))
    assert.is_false(client.refresh_diagnostics(bufnr, {
      wait_for_metals = false,
      on_complete = function(ok)
        completed = ok
      end,
    }))
    assert.is_false(completed)
    assert.is_false(published)
  end)

  it('does not publish a stale workspace result', function()
    local published = false
    local completed
    client.rpc_start({
      notification = function()
        published = true
      end,
    })

    diagnostics.collect_diagnostics = function(_, done)
      done({})
    end

    client.refresh_diagnostics(bufnr, {
      wait_for_metals = false,
      is_current = function()
        return false
      end,
      on_complete = function(ok)
        completed = ok
      end,
    })

    assert.is_true(vim.wait(1000, function()
      return completed ~= nil
    end, 10))
    assert.is_false(completed)
    assert.is_false(published)
  end)
end)
