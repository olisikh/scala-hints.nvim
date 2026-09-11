local workspace = require('scala-hints.workspace')

describe('workspace diagnostics coordinator', function()
  local temporary_root
  local bufnr

  after_each(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    bufnr = nil

    if temporary_root then
      vim.fn.delete(temporary_root, 'rf')
    end
    temporary_root = nil
  end)

  it('discovers Scala sources while excluding generated directories', function()
    temporary_root = vim.fn.tempname()
    vim.fn.mkdir(temporary_root .. '/src/nested', 'p')
    vim.fn.mkdir(temporary_root .. '/target', 'p')
    vim.fn.mkdir(temporary_root .. '/.metals', 'p')
    vim.fn.writefile({ 'object Main' }, temporary_root .. '/src/Main.scala')
    vim.fn.writefile({ 'object Nested' }, temporary_root .. '/src/nested/Nested.scala')
    vim.fn.writefile({ 'object Generated' }, temporary_root .. '/target/Generated.scala')
    vim.fn.writefile({ 'object Workspace' }, temporary_root .. '/.metals/Workspace.scala')
    vim.fn.writefile({ 'not Scala' }, temporary_root .. '/src/README.md')

    local files
    workspace._test.discover_files(temporary_root, function(result)
      files = result
    end)

    assert.is_true(vim.wait(1000, function()
      return files ~= nil
    end, 10))
    table.sort(files)

    assert.are.same({
      vim.fs.normalize(temporary_root .. '/src/Main.scala'),
      vim.fs.normalize(temporary_root .. '/src/nested/Nested.scala'),
    }, files)
  end)

  it('resets discovery when Metals reconnects for the same root', function()
    local coordinator = {
      metals_client_id = 1,
      cancelled = true,
      discovery_started = true,
    }

    assert.is_true(workspace._test.update_metals_client(coordinator, 2))
    assert.are.equal(2, coordinator.metals_client_id)
    assert.is_false(coordinator.cancelled)
    assert.is_false(coordinator.discovery_started)
    assert.is_false(workspace._test.update_metals_client(coordinator, 2))
  end)

  it('uses path boundaries when matching a file to a workspace root', function()
    assert.is_true(workspace._test.is_within_root('/work/foo/A.scala', '/work/foo'))
    assert.is_false(workspace._test.is_within_root('/work/foo-bar/A.scala', '/work/foo'))
  end)

  it('recognizes only buffers explicitly managed by the workspace coordinator', function()
    bufnr = vim.api.nvim_create_buf(false, true)

    assert.is_false(workspace.is_managed(bufnr))
    vim.b[bufnr].scala_hints_workspace_managed = true
    assert.is_true(workspace.is_managed(bufnr))
  end)
end)
