--- Tests for ZIO queries that do NOT require LSP interaction.
--- These handlers are purely Treesitter-based and return results synchronously.

local H = require('tests.helpers')
local queries = require('scala-hints.libs.zio.queries')

describe('ZIO pure queries (no LSP)', function()
  local bufnr

  after_each(function()
    if bufnr then
      H.cleanup_buf(bufnr)
      bufnr = nil
    end
  end)

  ---------------------------------------------------------------------------
  -- fail_exception_or_die
  ---------------------------------------------------------------------------
  describe('fail_exception_or_die', function()
    it('matches ZIO.fail(ex).orDie and suggests ZIO.die(ex)', function()
      local source = [[val x = ZIO.fail(new RuntimeException("boom")).orDie]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.fail_exception_or_die)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.die(new RuntimeException("boom"))',
        title = 'ZIO: replace ZIO.fail(new RuntimeException("boom")).orDie with ZIO.die(new RuntimeException("boom"))',
      })
    end)

    it('does not match ZIO.fail(ex) without .orDie', function()
      local source = [[val x = ZIO.fail(new Exception("err"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.fail_exception_or_die)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zip_right_unit
  ---------------------------------------------------------------------------
  describe('zip_right_unit', function()
    it('matches *> ZIO.unit and suggests .unit', function()
      local source = [[val x = effect *> ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_unit)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = '.unit',
      })
    end)

    it('does not match *> ZIO.succeed(v)', function()
      local source = [[val x = effect *> ZIO.succeed(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zip_right_unit)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- as_unit
  ---------------------------------------------------------------------------
  describe('as_unit', function()
    it('matches .as(()) and suggests .unit', function()
      local source = [[val x = effect.as(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.as_unit)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'unit',
        title = 'ZIO: replace .as(()) with .unit',
      })
    end)

    it('does not match .as(value)', function()
      local source = [[val x = effect.as(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.as_unit)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zip_right_value
  ---------------------------------------------------------------------------
  describe('zip_right_value', function()
    it('matches *> ZIO.succeed(v) and suggests .as(v)', function()
      local source = [[val x = effect *> ZIO.succeed(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_value)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = '.as(42)',
        title = 'ZIO: replace *> ZIO.succeed(42) with .as(42)',
      })
    end)

    it('does not match *> ZIO.succeed(()) (excluded by #not-eq?)', function()
      local source = [[val x = effect *> ZIO.succeed(())]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zip_right_value)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- or_else_fail3
  ---------------------------------------------------------------------------
  describe('or_else_fail3', function()
    it('matches .flatMapError(_ => ZIO.succeed(v)) and suggests .orElseFail(v)', function()
      local source = [[val x = effect.flatMapError(_ => ZIO.succeed(newErr))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.or_else_fail3)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'orElseFail(newErr)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- fold_cause_ignore
  ---------------------------------------------------------------------------
  describe('fold_cause_ignore', function()
    it('matches .foldCause(_ => (), _ => ()) and suggests .ignore', function()
      local source = [[val x = effect.foldCause(_ => (), _ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.fold_cause_ignore)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ignore',
        title = 'ZIO: replace .foldCause(_ => (), _ => ()) with .ignore',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_foreach
  ---------------------------------------------------------------------------
  describe('zio_foreach', function()
    it('matches ZIO.collectAll(coll.map(f)) and suggests ZIO.foreach(coll)(f)', function()
      local source = [[val x = ZIO.collectAll(items.map(process))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_foreach)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.foreach(items)(process)',
        title = 'ZIO: replace ZIO.collectAll with ZIO.foreach',
      })
    end)

    it('replaces collectAllPar with foreachPar', function()
      local source = [[val x = ZIO.collectAllPar(items.map(process))]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_foreach)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.foreachPar(items)(process)',
        title = 'ZIO: replace ZIO.collectAllPar with ZIO.foreachPar',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_type
  ---------------------------------------------------------------------------
  describe('zio_type', function()
    it('suggests UIO[A] for ZIO[Any, Nothing, A]', function()
      local source = [[def foo: ZIO[Any, Nothing, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_type)

      -- ZIO[Any, Nothing, A] matches 3 aliases: UIO, IO[Nothing, _], URIO[Any, _]
      assert.is_true(#ready >= 1)
      H.assert_result(ready[1], {
        replacement = 'UIO[Int]',
      })
    end)

    it('suggests Task[A] for ZIO[Any, Throwable, A]', function()
      local source = [[def foo: ZIO[Any, Throwable, String] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_type)

      -- ZIO[Any, Throwable, A] matches 3 aliases: Task, IO[Throwable, _], RIO[Any, _]
      assert.is_true(#ready >= 1)
      H.assert_result(ready[1], {
        replacement = 'Task[String]',
      })
    end)

    it('suggests IO[E, A] for ZIO[Any, E, A]', function()
      local source = [[def foo: ZIO[Any, AppError, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_type)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'IO[AppError, Int]',
      })
    end)

    it('suggests URIO[R, A] for ZIO[R, Nothing, A]', function()
      local source = [[def foo: ZIO[Env, Nothing, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_type)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'URIO[Env, Int]',
      })
    end)

    it('suggests RIO[R, A] for ZIO[R, Throwable, A]', function()
      local source = [[def foo: ZIO[Env, Throwable, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_type)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'RIO[Env, Int]',
      })
    end)

    it('returns nothing for ZIO[R, E, A] with no matching alias', function()
      local source = [[def foo: ZIO[Env, AppError, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_type)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zlayer_type
  ---------------------------------------------------------------------------
  describe('zlayer_type', function()
    it('suggests ULayer[A] for ZLayer[Any, Nothing, A]', function()
      local source = [[def layer: ZLayer[Any, Nothing, UserService] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zlayer_type)

      -- ZLayer[Any, Nothing, A] matches 3 aliases: ULayer, Layer[Nothing, _], URLayer[Any, _]
      assert.is_true(#ready >= 1)
      H.assert_result(ready[1], {
        replacement = 'ULayer[UserService]',
      })
    end)

    it('suggests TaskLayer[A] for ZLayer[Any, Throwable, A]', function()
      local source = [[def layer: ZLayer[Any, Throwable, UserService] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zlayer_type)

      -- ZLayer[Any, Throwable, A] matches 3 aliases: TaskLayer, Layer[Throwable, _], RLayer[Any, _]
      assert.is_true(#ready >= 1)
      H.assert_result(ready[1], {
        replacement = 'TaskLayer[UserService]',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_none
  ---------------------------------------------------------------------------
  describe('zio_none', function()
    it('matches ZIO.succeed(None) and suggests ZIO.none', function()
      local source = [[val x = ZIO.succeed(None)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_none)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.none',
        title = 'ZIO: replace ZIO.succeed(None) with ZIO.none',
      })
    end)

    it('matches ZIO.succeed(none) and suggests ZIO.none', function()
      local source = [[val x = ZIO.succeed(none)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_none)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.none',
        title = 'ZIO: replace ZIO.succeed(none) with ZIO.none',
      })
    end)

    it('does not match ZIO.succeed(Some(v))', function()
      local source = [[val x = ZIO.succeed(Some(42))]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_none)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_some
  ---------------------------------------------------------------------------
  describe('zio_some', function()
    it('matches ZIO.succeed(Some(v)) and suggests ZIO.some(v)', function()
      local source = [[val x = ZIO.succeed(Some(42))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_some)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.some(42)',
      })
    end)

    it('matches ZIO.succeed(Option(v)) and suggests ZIO.some(v)', function()
      local source = [[val x = ZIO.succeed(Option(value))]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_some)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.some(value)',
      })
    end)

    it('matches ZIO.succeed(v.some) and suggests ZIO.some(v)', function()
      local source = [[val x = ZIO.succeed(1.some)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_some)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.some(1)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_either
  ---------------------------------------------------------------------------
  describe('zio_either', function()
    it('matches ZIO.succeed(Left(v)) and suggests ZIO.left(v)', function()
      local source = [[val x = ZIO.succeed(Left(err))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(0, #pending)
      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.left(err)',
      })
    end)

    it('matches ZIO.succeed(Right(v)) and suggests ZIO.right(v)', function()
      local source = [[val x = ZIO.succeed(Right(ok))]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.right(ok)',
      })
    end)

    it('matches ZIO.succeed(v.asLeft) and suggests ZIO.left(v)', function()
      local source = [[val x = ZIO.succeed(err.asLeft)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.left(err)',
      })
    end)

    it('matches ZIO.succeed(v.asRight) and suggests ZIO.right(v)', function()
      local source = [[val x = ZIO.succeed(ok.asRight)]]
      bufnr, root = H.parse_scala(source)

      local ready, _ = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(1, #ready)
      H.assert_result(ready[1], {
        replacement = 'ZIO.right(ok)',
      })
    end)
  end)
end)
