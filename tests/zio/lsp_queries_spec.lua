--- Tests for ZIO queries that require mocking LSP hover.
---
--- These handlers call utils.hover_node_and_match() (synchronous) or
--- semantic.hover_predicate() (async/callback). We mock both to return
--- true so the handlers proceed with their replacement logic, and also
--- test the false path to verify no results are emitted.

local H = require('tests.helpers')
local queries = require('scala-hints.libs.zio.queries')

describe('ZIO queries with LSP hover mock', function()
  local bufnr

  after_each(function()
    H.restore_mocks()
    if bufnr then
      H.cleanup_buf(bufnr)
      bufnr = nil
    end
  end)

  ---------------------------------------------------------------------------
  -- succeed_unit (uses semantic.hover_predicate — async/pending)
  ---------------------------------------------------------------------------
  describe('succeed_unit', function()
    it('returns a pending thunk that resolves when hover confirms ZIO', function()
      H.mock_hover_predicate(true)
      local source = [[val x = ZIO.succeed(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.succeed_unit)

      -- succeed_unit uses semantic.hover_predicate so results come via pending
      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      -- Resolve the pending thunk
      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'unit',
      })
    end)

    it('emits nothing when hover says not ZIO', function()
      H.mock_hover_predicate(false)
      local source = [[val x = ZIO.succeed(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.succeed_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)
      assert.are.equal(0, #published)
    end)
  end)

  ---------------------------------------------------------------------------
  -- map_unit (uses utils.hover_node_and_match)
  ---------------------------------------------------------------------------
  describe('map_unit', function()
    it('matches .map(_ => ()) with ZIO hover and suggests .unit', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.map(_ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.map_unit)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'unit',
        title = 'ZIO: replace .map(_ => ()) with .unit',
      })
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.map(_ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.map_unit)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zip_left_value (uses utils.hover_node_and_match, returns 2 actions)
  ---------------------------------------------------------------------------
  describe('zip_left_value', function()
    it('matches .tap(_ => v) and suggests two replacements', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.tap(_ => sideEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zip_left_value)

      assert.are.equal(2, #ready)

      -- First option: <* v
      assert.is_truthy(string.find(ready[1].replacement, '<*'))

      -- Second option: .zipLeft(v)
      assert.is_truthy(string.find(ready[2].replacement, 'zipLeft'))
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.tap(_ => sideEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zip_left_value)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- flat_map_value (uses utils.hover_node_and_match, returns 2 actions)
  ---------------------------------------------------------------------------
  describe('flat_map_value', function()
    it('matches .flatMap(_ => v) and suggests two replacements', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.flatMap(_ => otherEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.flat_map_value)

      assert.are.equal(2, #ready)

      -- First option: *> v
      assert.is_truthy(string.find(ready[1].replacement, '*>'))
      -- Second option: .zipRight(v)
      assert.is_truthy(string.find(ready[2].replacement, 'zipRight'))
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.flatMap(_ => otherEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.flat_map_value)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- map_value (uses utils.hover_node_and_match)
  ---------------------------------------------------------------------------
  describe('map_value', function()
    it('matches .map(_ => v) and suggests .as(v)', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.map(_ => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.map_value)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'as(42)',
      })
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.map(_ => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.map_value)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- catch_all_unit (uses utils.hover_node_and_match)
  ---------------------------------------------------------------------------
  describe('catch_all_unit', function()
    it('matches .catchAll(_ => ZIO.unit) and suggests .ignore', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.catchAll(_ => ZIO.unit)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.catch_all_unit)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ignore',
      })
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.catchAll(_ => ZIO.unit)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.catch_all_unit)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- or_else_fail (uses utils.hover_node_and_match)
  ---------------------------------------------------------------------------
  describe('or_else_fail', function()
    it('matches .mapError(_ => v) and suggests .orElseFail(v)', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.mapError(_ => newErr)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.or_else_fail)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'orElseFail(newErr)',
      })
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.mapError(_ => newErr)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.or_else_fail)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- or_else_fail2 (uses utils.hover_node_and_match)
  ---------------------------------------------------------------------------
  describe('or_else_fail2', function()
    it('matches .orElse(ZIO.fail(v)) and suggests .orElseFail(v)', function()
      H.mock_hover_node_and_match(true)
      local source = [[val x = effect.orElse(ZIO.fail(newErr))]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.or_else_fail2)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'orElseFail(newErr)',
      })
    end)

    it('returns nothing when hover says not ZIO', function()
      H.mock_hover_node_and_match(false)
      local source = [[val x = effect.orElse(ZIO.fail(newErr))]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.or_else_fail2)
      assert.are.equal(0, #ready)
    end)
  end)
end)
