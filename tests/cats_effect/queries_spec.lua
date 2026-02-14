--- Tests for Cats-Effect queries with type definition verification.
--- All handlers use semantic.type_definition_predicate (mocked to return true).

local H = require('tests.helpers')
local queries = require('scala-hints.libs.cats_effect.queries')

describe('Cats-Effect queries with type definition verification', function()
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
  -- map_unit
  ---------------------------------------------------------------------------
  describe('map_unit', function()
    it('matches .map(_ => ()) and suggests .void', function()
      local source = [[val x = IO(1).map(_ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'void',
        title = 'CE: replace .map(_ => ()) with .void',
      })
    end)

    it('does not match .map(x => ())', function()
      local source = [[val x = IO(1).map(x => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- map_value
  ---------------------------------------------------------------------------
  describe('map_value', function()
    it('matches .map(_ => v) and suggests .as(v)', function()
      local source = [[val x = IO(1).map(_ => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'as(42)',
        title = 'CE: replace .map(_ => 42) with .as(42)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- flat_map_value
  ---------------------------------------------------------------------------
  describe('flat_map_value', function()
    it('matches .flatMap(_ => v) and suggests >> v', function()
      local source = [[val x = IO(1).flatMap(_ => IO(2))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_map_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = ' >> IO(2)',
        title = 'CE: replace .flatMap(_ => IO(2)) with >> IO(2)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- when_a
  ---------------------------------------------------------------------------
  describe('when_a', function()
    it('matches if (cond) effect else IO.unit and suggests whenA', function()
      local source = [[val x = if (cond) IO(1) else IO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when_a)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO(1).whenA(cond)',
        title = 'CE: replace if (cond) effect else IO.unit with effect.whenA(cond)',
      })
    end)

    it('does not match if without IO.unit alternative', function()
      local source = [[val x = if (cond) IO(1) else IO(2)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.when_a)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- unless_a
  ---------------------------------------------------------------------------
  describe('unless_a', function()
    it('matches if (!cond) effect else IO.unit and suggests unlessA', function()
      local source = [[val x = if (!cond) IO(1) else IO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.unless_a)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO(1).unlessA(cond)',
        title = 'CE: replace if (!cond) effect else IO.unit with effect.unlessA(cond)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- flat_tap
  ---------------------------------------------------------------------------
  describe('flat_tap', function()
    it('matches .flatMap(a => effect.as(a)) and suggests .flatTap', function()
      local source = [[val x = IO(1).flatMap(a => Console[IO].println(a).as(a))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_tap)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'flatTap(a => Console[IO].println(a))',
        title = 'CE: replace .flatMap returning its parameter with .flatTap',
      })
    end)

    it('does not match .flatMap when .as uses a different value', function()
      local source = [[val x = IO(1).flatMap(a => IO(a).as(42))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_tap)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- raise_unless
  ---------------------------------------------------------------------------
  describe('raise_unless', function()
    it('matches if (cond) IO.unit else IO.raiseError(err) and suggests raiseUnless', function()
      local source = [[val x = if (cond) IO.unit else IO.raiseError(err)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_unless)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.raiseUnless(cond)(err)',
        title = 'CE: replace if (...) IO.unit/raiseError with IO.raiseUnless',
      })
    end)

    it('matches if (!cond) IO.raiseError(err) else IO.unit and suggests raiseUnless', function()
      local source = [[val x = if (!cond) IO.raiseError(err) else IO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_unless)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.raiseUnless(cond)(err)',
        title = 'CE: replace if (...) IO.unit/raiseError with IO.raiseUnless',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- raise_when
  ---------------------------------------------------------------------------
  describe('raise_when', function()
    it('matches if (cond) IO.raiseError(err) else IO.unit and suggests raiseWhen', function()
      local source = [[val x = if (cond) IO.raiseError(err) else IO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_when)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.raiseWhen(cond)(err)',
        title = 'CE: replace if (...) raiseError/IO.unit with IO.raiseWhen',
      })
    end)

    it('matches if (!cond) IO.unit else IO.raiseError(err) and suggests raiseWhen', function()
      local source = [[val x = if (!cond) IO.unit else IO.raiseError(err)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_when)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.raiseWhen(cond)(err)',
        title = 'CE: replace if (...) raiseError/IO.unit with IO.raiseWhen',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- from_option
  ---------------------------------------------------------------------------
  describe('from_option', function()
    it('matches opt.fold(IO.raiseError(err))(IO.pure) and suggests IO.fromOption', function()
      local source = [[val x = opt.fold(IO.raiseError(err))(IO.pure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_option)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.fromOption(opt)(err)',
        title = 'CE: replace .fold(IO.raiseError(err))(IO.pure) with IO.fromOption',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- from_either
  ---------------------------------------------------------------------------
  describe('from_either', function()
    it('matches either.fold(IO.raiseError, IO.pure) and suggests IO.fromEither', function()
      local source = [[val x = either.fold(IO.raiseError, IO.pure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.fromEither(either)',
        title = 'CE: replace .fold(IO.raiseError, IO.pure) with IO.fromEither',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- from_try
  ---------------------------------------------------------------------------
  describe('from_try', function()
    it('matches Try(x).fold(IO.raiseError, IO.pure) and suggests IO.fromTry', function()
      local source = [[val x = Try(boom).fold(IO.raiseError, IO.pure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_try)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.fromTry(Try(boom))',
        title = 'CE: replace .fold(IO.raiseError, IO.pure) with IO.fromTry',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- handle_error
  ---------------------------------------------------------------------------
  describe('handle_error', function()
    it('matches attempt.flatMap with IO.pure branches and suggests handleError', function()
      local source = [[
        val x = IO(1).attempt.flatMap {
          case Right(a) => IO.pure(a)
          case Left(e)  => IO.pure(default)
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.handle_error)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'handleError(_ => default)',
        title = 'CE: replace .attempt.flatMap with .handleError',
      })
    end)

    it('matches attempt.flatMap with param in left branch and suggests handleErrorWith', function()
      local source = [[
        val x = IO(1).attempt.flatMap {
          case Right(a) => IO.pure(a)
          case Left(e)  => IO.pure(default(e))
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.handle_error)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'handleErrorWith(e => IO.pure(default(e)))',
        title = 'CE: replace .attempt.flatMap with .handleError',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- redeem
  ---------------------------------------------------------------------------
  describe('redeem', function()
    it('matches attempt.map with Right/Left cases and suggests redeem', function()
      local source = [[
        val x = IO(1).attempt.map {
          case Right(a) => f(a)
          case Left(e)  => g(e)
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.redeem)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'redeem(e => g(e), a => f(a))',
        title = 'CE: replace .attempt.map with .redeem',
      })
    end)

    it('uses redeemWith when branches are effectful', function()
      local source = [[
        val x = IO(1).attempt.map {
          case Right(a) => IO.pure(f(a))
          case Left(e)  => IO.raiseError(g(e))
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.redeem)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'redeemWith(e => IO.raiseError(g(e)), a => IO.pure(f(a)))',
        title = 'CE: replace .attempt.map with .redeemWith',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- delay_by
  ---------------------------------------------------------------------------
  describe('delay_by', function()
    it('matches Temporal[IO].sleep(d) *> effect and suggests delayBy', function()
      local source = [[val x = Temporal[IO].sleep(500.millis) *> IO(1)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay_by)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO(1).delayBy(500.millis)',
        title = 'CE: replace sleep *> effect with effect.delayBy',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- timeout
  ---------------------------------------------------------------------------
  describe('timeout', function()
    it('matches IO.race(...sleep...).flatMap and suggests timeout', function()
      local source = [[
        val x = IO.race(fa, Temporal[IO].sleep(1.second)).flatMap {
          case Left(a)  => IO.pure(a)
          case Right(_) => IO.raiseError(new TimeoutException)
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.timeout)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'fa.timeout(1.second)',
        title = 'CE: replace IO.race sleep pattern with .timeout',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- tupled
  ---------------------------------------------------------------------------
  describe('tupled', function()
    it('matches flatMap/map tuple and suggests tupled', function()
      local source = [[val x = fa.flatMap(a => fb.map(b => (a, b)))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tupled)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '(fa, fb).tupled',
        title = 'CE: replace flatMap/map tuple with .tupled',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- par_tupled
  ---------------------------------------------------------------------------
  describe('par_tupled', function()
    it('matches flatMap/map tuple with parTupled and suggests (fa, fb).parTupled', function()
      local source = [[val x = fa.flatMap(a => fb.map(b => (a, b))).parTupled]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.par_tupled)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '(fa, fb).parTupled',
        title = 'CE: replace flatMap/map tuple with .parTupled',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- par_sequence
  ---------------------------------------------------------------------------
  describe('par_sequence', function()
    it('matches list.map(f).parSequence and suggests parTraverse', function()
      local source = [[val x = list.map(process).parSequence]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.par_sequence)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'list.parTraverse(process)',
        title = 'CE: replace .map(f).parSequence with .parTraverse(f)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- par_sequence_
  ---------------------------------------------------------------------------
  describe('par_sequence_', function()
    it('matches list.map(f).parSequence_ and suggests parTraverse_', function()
      local source = [[val x = list.map(process).parSequence_]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.par_sequence_)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'list.parTraverse_(process)',
        title = 'CE: replace .map(f).parSequence_ with .parTraverse_(f)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- replicate_a_
  ---------------------------------------------------------------------------
  describe('replicate_a_', function()
    it('matches range.toList.traverse and suggests replicateA_', function()
      local source = [[val x = (1 to n).toList.traverse(_ => IO(1))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.replicate_a_)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO(1).replicateA_(n)',
        title = 'CE: replace traverse range with replicateA_',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- forever_m
  ---------------------------------------------------------------------------
  describe('forever_m', function()
    it('matches recursive flatMap and suggests foreverM', function()
      local source = [[def loop = IO(1).flatMap(_ => loop)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.forever_m)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO(1).foreverM',
        title = 'CE: replace recursive flatMap with .foreverM',
      })
    end)
  end)
end)
