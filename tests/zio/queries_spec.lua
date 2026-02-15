--- Tests for ZIO queries with type definition verification.
--- All handlers use semantic.type_definition_predicate (mocked to return true).

local H = require('tests.helpers')
local queries = require('scala-hints.libs.zio.queries')

describe('ZIO queries with type definition verification', function()
  local bufnr

  before_each(function()
    H.mock_type_definition_predicate(true)
  end)

  after_each(function()
    H.restore_mocks()
    if bufnr then
      H.cleanup_buf(bufnr)
      bufnr = nil
    end
  end)

  ---------------------------------------------------------------------------
  -- zio_die
  ---------------------------------------------------------------------------
  describe('zio_die', function()
    it('matches ZIO.fail(ex).orDie and suggests ZIO.die(ex)', function()
      local source = [[val x = ZIO.fail(new RuntimeException("boom")).orDie]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_die)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.die(new RuntimeException("boom"))',
        title = 'ZIO: replace ZIO.fail(new RuntimeException("boom")).orDie with ZIO.die(new RuntimeException("boom"))',
      })
    end)

    it('does not match ZIO.fail(ex) without .orDie', function()
      local source = [[val x = ZIO.fail(new Exception("err"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_die)
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.unit',
      })
    end)

    it('does not match *> ZIO.succeed(v)', function()
      local source = [[val x = effect *> ZIO.succeed(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_unit)
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'unit',
        title = 'ZIO: replace .as(()) with .unit',
      })
    end)

    it('does not match .as(value)', function()
      local source = [[val x = effect.as(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.as_unit)
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.as(42)',
        title = 'ZIO: replace *> ZIO.succeed(42) with .as(42)',
      })
    end)

    it('does not match *> ZIO.succeed(()) (excluded by #not-eq?)', function()
      local source = [[val x = effect *> ZIO.succeed(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_value)
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.foreach(items)(process)',
        title = 'ZIO: replace ZIO.collectAll with ZIO.foreach',
      })
    end)

    it('replaces collectAllPar with foreachPar', function()
      local source = [[val x = ZIO.collectAllPar(items.map(process))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_foreach)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.foreachPar(items)(process)',
        title = 'ZIO: replace ZIO.collectAllPar with ZIO.foreachPar',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- foreach_par_n
  ---------------------------------------------------------------------------
  describe('foreach_par_n', function()
    it('matches ZIO.foreachPar(coll)(f) and suggests ZIO.foreachParN', function()
      local source = [[val x = ZIO.foreachPar(items)(process)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.foreach_par_n)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.foreachParN(n)(items)(process)',
        title = 'ZIO: replace ZIO.foreachPar with ZIO.foreachParN (specify parallelism)',
      })
    end)

    it('does not match ZIO.foreach', function()
      local source = [[val x = ZIO.foreach(items)(process)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.foreach_par_n)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_type
  ---------------------------------------------------------------------------
  describe('zio_type', function()
    it('suggests UIO[A] for ZIO[Any, Nothing, A]', function()
      local source = [[def foo: ZIO[Any, Nothing, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_type)

      -- ZIO[Any, Nothing, A] matches 3 aliases: UIO, IO[Nothing, _], URIO[Any, _]
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.is_true(#results >= 1)
      H.assert_result(results[1], {
        replacement = 'UIO[Int]',
      })
    end)

    it('suggests Task[A] for ZIO[Any, Throwable, A]', function()
      local source = [[def foo: ZIO[Any, Throwable, String] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_type)

      -- ZIO[Any, Throwable, A] matches 3 aliases: Task, IO[Throwable, _], RIO[Any, _]
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.is_true(#results >= 1)
      H.assert_result(results[1], {
        replacement = 'Task[String]',
      })
    end)

    it('suggests IO[E, A] for ZIO[Any, E, A]', function()
      local source = [[def foo: ZIO[Any, AppError, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_type)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO[AppError, Int]',
      })
    end)

    it('suggests URIO[R, A] for ZIO[R, Nothing, A]', function()
      local source = [[def foo: ZIO[Env, Nothing, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_type)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'URIO[Env, Int]',
      })
    end)

    it('suggests RIO[R, A] for ZIO[R, Throwable, A]', function()
      local source = [[def foo: ZIO[Env, Throwable, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_type)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'RIO[Env, Int]',
      })
    end)

    it('returns nothing for ZIO[R, E, A] with no matching alias', function()
      local source = [[def foo: ZIO[Env, AppError, Int] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_type)
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

      local ready, pending = H.run_handler(bufnr, root, queries.zlayer_type)

      -- ZLayer[Any, Nothing, A] matches 3 aliases: ULayer, Layer[Nothing, _], URLayer[Any, _]
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.is_true(#results >= 1)
      H.assert_result(results[1], {
        replacement = 'ULayer[UserService]',
      })
    end)

    it('suggests TaskLayer[A] for ZLayer[Any, Throwable, A]', function()
      local source = [[def layer: ZLayer[Any, Throwable, UserService] = ???]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zlayer_type)

      -- ZLayer[Any, Throwable, A] matches 3 aliases: TaskLayer, Layer[Throwable, _], RLayer[Any, _]
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.is_true(#results >= 1)
      H.assert_result(results[1], {
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.none',
        title = 'ZIO: replace ZIO.succeed(None) with ZIO.none',
      })
    end)

    it('matches ZIO.succeed(none) and suggests ZIO.none', function()
      local source = [[val x = ZIO.succeed(none)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_none)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.none',
        title = 'ZIO: replace ZIO.succeed(none) with ZIO.none',
      })
    end)

    it('does not match ZIO.succeed(Some(v))', function()
      local source = [[val x = ZIO.succeed(Some(42))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_none)
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.some(42)',
      })
    end)

    it('matches ZIO.succeed(Option(v)) and suggests ZIO.some(v)', function()
      local source = [[val x = ZIO.succeed(Option(value))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_some)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.some(value)',
      })
    end)

    it('matches ZIO.succeed(v.some) and suggests ZIO.some(v)', function()
      local source = [[val x = ZIO.succeed(1.some)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_some)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
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

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.left(err)',
      })
    end)

    it('matches ZIO.succeed(Right(v)) and suggests ZIO.right(v)', function()
      local source = [[val x = ZIO.succeed(Right(ok))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.right(ok)',
      })
    end)

    it('matches ZIO.succeed(v.asLeft) and suggests ZIO.left(v)', function()
      local source = [[val x = ZIO.succeed(err.asLeft)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.left(err)',
      })
    end)

    it('matches ZIO.succeed(v.asRight) and suggests ZIO.right(v)', function()
      local source = [[val x = ZIO.succeed(ok.asRight)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_either)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.right(ok)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- delay
  ---------------------------------------------------------------------------
  describe('delay', function()
    it('matches ZIO.sleep(duration) *> effect and suggests effect.delay(duration)', function()
      local source = [[val x = ZIO.sleep(5.seconds) *> effect]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.delay(5.seconds)',
        title = 'ZIO: replace ZIO.sleep(5.seconds) *> effect with effect.delay(5.seconds)',
      })
    end)

    it('matches ZIO.sleep(Duration.fromMillis(100)) *> effect', function()
      local source = [[val result = ZIO.sleep(Duration.fromMillis(100)) *> otherZIO]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.delay(Duration.fromMillis(100))',
      })
    end)

    it('does not match without *> operator', function()
      local source = [[val x = ZIO.sleep(5.seconds)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay)
      assert.are.equal(0, #ready)
    end)

    it('does not match other infix operators', function()
      local source = [[val x = ZIO.sleep(5.seconds) >> effect]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- to_layer
  ---------------------------------------------------------------------------
  describe('to_layer', function()
    it('matches ZLayer.fromEffect(effect) and suggests effect.toLayer', function()
      local source = [[val layer = ZLayer.fromEffect(myEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.to_layer)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.toLayer',
        title = 'ZIO: replace ZLayer.fromEffect(myEffect) with myEffect.toLayer',
      })
    end)

    it('does not match ZLayer.fromManaged', function()
      local source = [[val layer = ZLayer.fromManaged(managed)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.to_layer)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- provide_layer
  ---------------------------------------------------------------------------
  describe('provide_layer', function()
    it('matches layer.build.use(effect.provide) and suggests effect.provideLayer(layer)', function()
      local source = [[val x = layer.build.use(effect.provide)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.provide_layer)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'effect.provideLayer(layer)',
        title = 'ZIO: replace layer.build.use(effect.provide) with effect.provideLayer(layer)',
      })
    end)

    it('matches layer.build.use(effect.provideLayer) and suggests effect.provideLayer(layer)', function()
      local source = [[val x = layer.build.use(effect.provideLayer)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.provide_layer)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'effect.provideLayer(layer)',
      })
    end)

    it('does not match effect.provideLayer(layer)', function()
      local source = [[val x = effect.provideLayer(layer)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.provide_layer)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zio_service
  ---------------------------------------------------------------------------
  describe('zio_service', function()
    it('matches ZIO.access(identity) and suggests ZIO.service', function()
      local source = [[val svc = ZIO.access(identity)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_service)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.service',
      })
    end)

    it('does not match ZIO.access without identity', function()
      local source = [[val svc = ZIO.access(_.get)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_service)
      assert.are.equal(0, #ready)
    end)

    it('does not match ZIO.access with other expressions', function()
      local source = [[val svc = ZIO.access(_.foo)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_service)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- exit_code_map
  ---------------------------------------------------------------------------
  describe('exit_code_map', function()
    it('matches .map(_ => ExitCode.success) and suggests .exitCode', function()
      local source = [[val x = effect.map(_ => ExitCode.success)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_map)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'exitCode',
        title = 'ZIO: replace .map(_ => ExitCode.success) with .exitCode',
      })
    end)

    it('does not match .map(_ => ExitCode.failure)', function()
      local source = [[val x = effect.map(_ => ExitCode.failure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_map)
      assert.are.equal(0, #ready)
    end)

    it('does not match .map(x => x * 2)', function()
      local source = [[val x = effect.map(x => x * 2)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_map)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- exit_code_as
  ---------------------------------------------------------------------------
  describe('exit_code_as', function()
    it('matches .as(ExitCode.success) and suggests .exitCode', function()
      local source = [[val x = effect.as(ExitCode.success)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_as)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'exitCode',
        title = 'ZIO: replace .as(ExitCode.success) with .exitCode',
      })
    end)

    it('does not match .as(ExitCode.failure)', function()
      local source = [[val x = effect.as(ExitCode.failure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_as)
      assert.are.equal(0, #ready)
    end)

    it('does not match .as(42)', function()
      local source = [[val x = effect.as(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_as)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- exit_code_fold
  ---------------------------------------------------------------------------
  describe('exit_code_fold', function()
    it('matches .fold(_ => ExitCode.failure, _ => ExitCode.success)', function()
      local source = [[val x = effect.fold(_ => ExitCode.failure, _ => ExitCode.success)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_fold)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'exitCode',
        title = 'ZIO: replace .fold(_ => ExitCode.failure, _ => ExitCode.success) with .exitCode',
      })
    end)

    it('does not match .fold with wrong ExitCode order', function()
      local source = [[val x = effect.fold(_ => ExitCode.success, _ => ExitCode.failure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_fold)
      assert.are.equal(0, #ready)
    end)

    it('does not match .fold with non-ExitCode values', function()
      local source = [[val x = effect.fold(_ => left, _ => right)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.exit_code_fold)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- tap
  ---------------------------------------------------------------------------
  describe('tap', function()
    it('matches .map with block returning parameter (paren-style)', function()
      local source = [[val x = effect.map(v => { sideEffect(v); v })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tap(v => sideEffect(v))',
        title = 'ZIO: replace .map returning its parameter with .tap',
      })
    end)

    it('matches .map with block returning parameter (brace-style)', function()
      local source = "val x = effect.map { v =>\n  sideEffect(v)\n  v\n}"
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tap(v => sideEffect(v))',
      })
    end)

    it('matches .map with multi-statement block', function()
      local source = [[val x = effect.map(v => { log(v); notify(v); v })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tap(v => log(v); notify(v))',
      })
    end)

    it('does not match .map without block (simple transform)', function()
      local source = [[val x = effect.map(v => v * 2)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)
      assert.are.equal(0, #ready)
    end)

    it('does not match .map with wildcard parameter', function()
      local source = [[val x = effect.map(_ => sideEffect())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)
      assert.are.equal(0, #ready)
    end)

    it('does not match when last expr differs from parameter', function()
      local source = [[val x = effect.map(v => { sideEffect(v); otherVal })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)
      assert.are.equal(0, #ready)
    end)

    it('does not match .mapError', function()
      local source = [[val x = effect.mapError(e => { logError(e); e })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- tap_error
  ---------------------------------------------------------------------------
  describe('tap_error', function()
    it('matches .mapError with block returning parameter (paren-style)', function()
      local source = [[val x = effect.mapError(e => { logError(e); e })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_error)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tapError(e => logError(e))',
        title = 'ZIO: replace .mapError returning its parameter with .tapError',
      })
    end)

    it('matches .mapError with block returning parameter (brace-style)', function()
      local source = "val x = effect.mapError { e =>\n  logError(e)\n  e\n}"
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_error)
      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tapError(e => logError(e))',
      })
    end)

    it('does not match .mapError without block', function()
      local source = [[val x = effect.mapError(e => newError)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_error)
      assert.are.equal(0, #ready)
    end)

    it('does not match .map', function()
      local source = [[val x = effect.map(v => { sideEffect(v); v })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_error)
      assert.are.equal(0, #ready)
    end)

    it('does not match when last expr differs from parameter', function()
      local source = [[val x = effect.mapError(e => { logError(e); newErr })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_error)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- tap_both
  ---------------------------------------------------------------------------
  describe('tap_both', function()
    it('matches map then mapError with side-effect blocks', function()
      local source = [[val x = effect.map(v => { log(v); v }).mapError(e => { logError(e); e })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_both)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tapBoth(e => logError(e), v => log(v))',
      })
    end)

    it('matches mapError then map with side-effect blocks', function()
      local source = [[val x = effect.mapError(e => { logError(e); e }).map(v => { log(v); v })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_both)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tapBoth(e => logError(e), v => log(v))',
      })
    end)

    it('does not match when map body is not a block', function()
      local source = [[val x = effect.map(v => v * 2).mapError(e => { logError(e); e })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_both)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- when
  ---------------------------------------------------------------------------
  describe('zio_cond', function()
    it('matches ZIO.cond(cond, (), err) and suggests ZIO.fail(err).unless(cond)', function()
      local source = [[val x = ZIO.cond(check, (), "fail")]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_cond)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ZIO.fail("fail").unless(check)',
      })
    end)

    it('does not match ZIO.cond when success is not unit', function()
      local source = [[val x = ZIO.cond(check, 1, "fail")]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zio_cond)
      assert.are.equal(0, #ready)
    end)
  end)

  ---------------------------------------------------------------------------
  -- when
  ---------------------------------------------------------------------------
  describe('when', function()
    it('matches if (condition) effect else ZIO.unit and suggests when', function()
      local source = [[val x = if (check) effect else ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'effect.when(check)',
      })
    end)

    it('matches block consequence and suggests when', function()
      local source = [[val x = if (cond) { succeed } else ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.when(cond)',
      })
    end)

    it('matches negated condition with unit consequence and suggests when', function()
      local source = [[val x = if (!cond) ZIO.unit else succeed]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.when(cond)',
      })
    end)

    it('does not match if without ZIO.unit alternative', function()
      local source = [[val x = if (check) effect else other]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)
      assert.are.equal(0, #ready)
    end)

    it('does not match without if-else structure', function()
      local source = [[val x = effect.when(check)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)
      assert.are.equal(0, #ready)
    end)

    it('matches Scala 3 if-then-else and suggests when', function()
      local source = [[val x = if check then succeed else ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.when(check)',
      })
    end)

    it('matches Scala 3 negated condition with unit consequence and suggests when', function()
      local source = [[val x = if !cond then ZIO.unit else succeed]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.when(cond)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- unless
  ---------------------------------------------------------------------------
  describe('unless', function()
    it('matches if (!condition) effect else ZIO.unit and suggests unless', function()
      local source = [[val x = if (!check) effect else ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'effect.unless(check)',
      })
    end)

    it('matches if (!(condition)) effect else ZIO.unit and suggests unless', function()
      local source = [[val x = if (!(check)) effect else ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'effect.unless(check)',
      })
    end)

    it('matches if (condition) ZIO.unit else effect and suggests unless', function()
      local source = [[val x = if (cond) ZIO.unit else succeed]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.unless(cond)',
      })
    end)

    it('matches block alternative and suggests unless', function()
      local source = [[val x = if (cond) ZIO.unit else { succeed }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.unless(cond)',
      })
    end)

    it('does not match if (condition) effect else ZIO.unit', function()
      local source = [[val x = if (check) effect else ZIO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)
      assert.are.equal(0, #ready)
    end)

    it('does not match if (!condition) effect else other', function()
      local source = [[val x = if (!check) effect else other]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)
      assert.are.equal(0, #ready)
    end)

    it('matches Scala 3 if-then-else with unit consequence and suggests unless', function()
      local source = [[val x = if cond then ZIO.unit else succeed]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'succeed.unless(cond)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- succeed_unit
  ---------------------------------------------------------------------------
  describe('succeed_unit', function()
    it('returns a pending thunk that resolves when type definition confirms ZIO', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = ZIO.succeed(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.succeed_unit)

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

    it('emits nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
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
  -- map_unit
  ---------------------------------------------------------------------------
  describe('map_unit', function()
    it('matches .map(_ => ()) with ZIO type definition and suggests .unit', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.map(_ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'unit',
        title = 'ZIO: replace .map(_ => ()) with .unit',
      })
    end)

    it('does not match .map(x => ()) (only wildcard parameters)', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.map(x => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.map(_ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)
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
  -- zip_left_value
  ---------------------------------------------------------------------------
  describe('zip_left_value', function()
    it('matches .tap(_ => v) and suggests two replacements', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.tap(_ => sideEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_left_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(2, #published)

      -- First option: <* v
      assert.is_truthy(string.find(published[1].replacement, '<*'))

      -- Second option: .zipLeft(v)
      assert.is_truthy(string.find(published[2].replacement, 'zipLeft'))
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.tap(_ => sideEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_left_value)
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
  -- flat_map_value
  ---------------------------------------------------------------------------
  describe('flat_map_value', function()
    it('matches .flatMap(_ => v) and suggests two replacements', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.flatMap(_ => otherEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_map_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(2, #published)

      -- First option: *> v
      assert.is_truthy(string.find(published[1].replacement, '*>'))
      -- Second option: .zipRight(v)
      assert.is_truthy(string.find(published[2].replacement, 'zipRight'))
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.flatMap(_ => otherEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_map_value)
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
  -- zip_right_operator
  ---------------------------------------------------------------------------
  describe('zip_right_operator', function()
    it('matches .zipRight(v) and suggests *> v', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.zipRight(otherEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_operator)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      assert.is_truthy(string.find(published[1].replacement, '*>'))
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.zipRight(otherEffect)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_operator)
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
  -- map_value
  ---------------------------------------------------------------------------
  describe('map_value', function()
    it('matches .map(_ => v) and suggests .as(v)', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.map(_ => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'as(42)',
      })
    end)

    it('does not match .map(x => v) (only wildcard parameters)', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.map(x => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_value)

      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.map(_ => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_value)
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
  -- catch_all_unit
  ---------------------------------------------------------------------------
  describe('catch_all_unit', function()
    it('matches .catchAll(_ => ZIO.unit) and suggests .ignore', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.catchAll(_ => ZIO.unit)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.catch_all_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'ignore',
      })
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.catchAll(_ => ZIO.unit)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.catch_all_unit)
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
  -- or_else_fail
  ---------------------------------------------------------------------------
  describe('or_else_fail', function()
    it('matches .mapError(_ => v) and suggests .orElseFail(v)', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.mapError(_ => newErr)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.or_else_fail)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'orElseFail(newErr)',
      })
    end)

    it('matches .mapError(err => v) and suggests .orElseFail(v)', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.mapError(err => newErr)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.or_else_fail)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'orElseFail(newErr)',
      })
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.mapError(_ => newErr)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.or_else_fail)
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
  -- or_else_fail2
  ---------------------------------------------------------------------------
  describe('or_else_fail2', function()
    it('matches .orElse(ZIO.fail(v)) and suggests .orElseFail(v)', function()
      H.mock_type_definition_predicate(true)
      local source = [[val x = effect.orElse(ZIO.fail(newErr))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.or_else_fail2)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)

      assert.are.equal(1, #published)
      H.assert_result(published[1], {
        replacement = 'orElseFail(newErr)',
      })
    end)

    it('returns nothing when type definition says not ZIO', function()
      H.mock_type_definition_predicate(false)
      local source = [[val x = effect.orElse(ZIO.fail(newErr))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.or_else_fail2)
      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)

      local published = {}
      pending[1](function(item)
        table.insert(published, item)
      end)
      assert.are.equal(0, #published)
    end)
  end)
end)
