--- Tests for Cats-Effect queries with type definition verification.
--- All handlers use semantic.type_definition_predicate (mocked to return true).

local H = require('tests.helpers')
local queries = require('scala-hints.libs.cats-effect.queries')

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
        replacement = '.flatTap(a => Console[IO].println(a))',
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

    it('does not match Try(x).fold(IO.raiseError, IO.pure)', function()
      local source = [[val x = Try(boom).fold(IO.raiseError, IO.pure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either)

      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)

    it('does not match scala.util.Try(x).fold(IO.raiseError, IO.pure)', function()
      local source = [[val x = scala.util.Try(boom).fold(IO.raiseError, IO.pure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either)

      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
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

    it('matches scala.util.Try(x).fold(IO.raiseError, IO.pure) and suggests IO.fromTry', function()
      local source = [[val x = scala.util.Try(boom).fold(IO.raiseError, IO.pure)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_try)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.fromTry(scala.util.Try(boom))',
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
        replacement = '.handleError(_ => default)',
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
        replacement = '.handleErrorWith(e => IO.pure(default(e)))',
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
        replacement = '.redeem(e => g(e), a => f(a))',
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
        replacement = '.redeemWith(e => IO.raiseError(g(e)), a => IO.pure(f(a)))',
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

  ---------------------------------------------------------------------------
  -- pure_unit
  ---------------------------------------------------------------------------
  describe('pure_unit', function()
    it('matches IO.pure(()) and suggests IO.unit', function()
      local source = [[val x = IO.pure(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.pure_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'unit',
        title = 'CE: replace IO.pure(()) with IO.unit',
      })
    end)

    it('does not match IO.pure(value)', function()
      local source = [[val x = IO.pure(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.pure_unit)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- as_unit
  ---------------------------------------------------------------------------
  describe('as_unit', function()
    it('matches .as(()) and suggests .void', function()
      local source = [[val x = IO(1).as(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.as_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'void',
        title = 'CE: replace .as(()) with .void',
      })
    end)

    it('does not match .as(value)', function()
      local source = [[val x = IO(1).as(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.as_unit)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zip_right_unit
  ---------------------------------------------------------------------------
  describe('zip_right_unit', function()
    it('matches *> IO.unit and suggests .void', function()
      local source = [[val x = fa *> IO.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.void',
        title = 'CE: replace *> IO.unit with .void',
      })
    end)

    it('does not match *> IO.pure(v)', function()
      local source = [[val x = fa *> IO.pure(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_unit)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zip_right_value
  ---------------------------------------------------------------------------
  describe('zip_right_value', function()
    it('matches *> IO.pure(v) and suggests .as(v)', function()
      local source = [[val x = fa *> IO.pure(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.as(42)',
        title = 'CE: replace *> IO.pure(42) with .as(42)',
      })
    end)

    it('does not match *> IO.pure(())', function()
      local source = [[val x = fa *> IO.pure(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.zip_right_value)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- if_m
  ---------------------------------------------------------------------------
  describe('if_m', function()
    it('matches .flatMap(b => if (b) fa else fb) and suggests .ifM', function()
      local source = [[val x = pred.flatMap(b => if (b) fa else fb)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.if_m)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'ifM(fa, fb)',
        title = 'CE: replace .flatMap(b => if (b) ...) with .ifM',
      })
    end)

    it('does not match when condition differs from param', function()
      local source = [[val x = pred.flatMap(b => if (other) fa else fb)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.if_m)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- traverse
  ---------------------------------------------------------------------------
  describe('traverse', function()
    it('matches .map(f).sequence and suggests .traverse(f)', function()
      local source = [[val x = coll.map(x => IO(f(x))).sequence]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.traverse)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'coll.traverse(x => IO(f(x)))',
        title = 'CE: replace .map(f).sequence with .traverse(f)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- traverse_
  ---------------------------------------------------------------------------
  describe('traverse_', function()
    it('matches .map(f).sequence_ and suggests .traverse_(f)', function()
      local source = [[val x = coll.map(x => IO(f(x))).sequence_]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.traverse_)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'coll.traverse_(x => IO(f(x)))',
        title = 'CE: replace .map(f).sequence_ with .traverse_(f)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- option_traverse
  ---------------------------------------------------------------------------
  describe('option_traverse', function()
    it('matches Option match with Some/None and suggests .traverse_', function()
      local source = [[val x = opt match { case Some(a) => f(a); case None => IO.unit }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.option_traverse)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'opt.traverse_(f)',
        title = 'CE: replace Option match with .traverse_',
      })
    end)

    it('does not match when None branch is not IO.unit', function()
      local source = [[val x = opt match { case Some(a) => f(a); case None => IO.pure(0) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.option_traverse)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)

    it('uses lambda form when body is complex', function()
      local source = [[val x = opt match { case Some(a) => g(a, b); case None => IO.unit }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.option_traverse)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'opt.traverse_(a => g(a, b))',
        title = 'CE: replace Option match with .traverse_',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- recover_with
  ---------------------------------------------------------------------------
  describe('recover_with', function()
    it('matches attempt.flatMap with typed Left and suggests recoverWith', function()
      local source = [[
        val x = fa.attempt.flatMap {
          case Left(e: MyEx) => recover(e)
          case Left(e)       => IO.raiseError(e)
          case Right(a)      => IO.pure(a)
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.recover_with)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.recoverWith { case e: MyEx => recover(e) }',
        title = 'CE: replace .attempt.flatMap with .recoverWith',
      })
    end)

    it('does not match when only 2 cases', function()
      local source = [[
        val x = fa.attempt.flatMap {
          case Right(a) => IO.pure(a)
          case Left(e)  => IO.pure(default)
        }
      ]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.recover_with)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- par_tupled_fibers
  ---------------------------------------------------------------------------
  describe('par_tupled_fibers', function()
    it('matches start/joinWithNever pattern and suggests parTupled', function()
      local source =
        [[val x = for { fA <- fa.start; fB <- fb.start; a <- fA.joinWithNever; b <- fB.joinWithNever } yield (a, b)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.par_tupled_fibers)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '(fa, fb).parTupled',
        title = 'CE: replace fiber start/joinWithNever with .parTupled',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- from_option_match
  ---------------------------------------------------------------------------
  describe('from_option_match', function()
    it('matches Option match with IO.pure/IO.raiseError and suggests IO.fromOption', function()
      local source = [[val x = opt match { case Some(x) => IO.pure(x); case None => IO.raiseError(err) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_option_match)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.fromOption(opt)(err)',
        title = 'CE: replace Option match with IO.fromOption',
      })
    end)

    it('does not match when Some body is not IO.pure(param)', function()
      local source = [[val x = opt match { case Some(x) => IO.pure(42); case None => IO.raiseError(err) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_option_match)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- from_either_match
  ---------------------------------------------------------------------------
  describe('from_either_match', function()
    it('matches Either match with IO.pure/IO.raiseError and suggests IO.fromEither', function()
      local source =
        [[val x = either match { case Right(y) => IO.pure(y); case Left(e) => IO.raiseError(e) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either_match)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.fromEither(either)',
        title = 'CE: replace Either match with IO.fromEither',
      })
    end)

    it('does not match when Left body does not use param', function()
      local source =
        [[val x = either match { case Right(y) => IO.pure(y); case Left(e) => IO.raiseError(otherErr) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either_match)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- adapt_error
  ---------------------------------------------------------------------------
  describe('adapt_error', function()
    it('matches .handleErrorWith(e => IO.raiseError(wrap)) and suggests .adaptError', function()
      local source = [[val x = IO(thunk).handleErrorWith(e => IO.raiseError(new Exception(e)))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.adapt_error)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.adaptError { case e => new Exception(e) }',
        title = 'CE: replace .handleErrorWith(IO.raiseError) with .adaptError',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- bracket
  ---------------------------------------------------------------------------
  describe('bracket', function()
    it('matches flatMap { a => use(a).guarantee(release(a)) } and suggests bracket', function()
      local source = [[val x = acquire.flatMap { a => use(a).guarantee(release(a)) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.bracket)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.bracket(use)(release)',
        title = 'CE: replace .flatMap { .guarantee } with .bracket',
      })
    end)

    it('uses lambda when use is complex', function()
      local source = [[val x = acquire.flatMap { a => service.process(a).guarantee(release(a)) }]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.bracket)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.bracket(a => service.process(a))(release)',
        title = 'CE: replace .flatMap { .guarantee } with .bracket',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- map_n
  ---------------------------------------------------------------------------
  describe('map_n', function()
    it('matches for-comprehension with constructor yield and suggests mapN', function()
      local source = [[val x = for { a <- fa; b <- fb; c <- fc } yield My(a, b, c)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_n)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '(fa, fb, fc).mapN(My.apply)',
        title = 'CE: replace for-comprehension with .mapN',
      })
    end)

    it('matches for-comprehension with tuple yield and suggests tupled', function()
      local source = [[val x = for { a <- fa; b <- fb } yield (a, b)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_n)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '(fa, fb).tupled',
        title = 'CE: replace for-comprehension with .mapN',
      })
    end)

    it('does not match when yield uses different params', function()
      local source = [[val x = for { a <- fa; b <- fb } yield My(a, z)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_n)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)

    it('does not match single enumerator', function()
      local source = [[val x = for { a <- fa } yield a]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_n)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- println
  ---------------------------------------------------------------------------
  describe('println', function()
    it('matches IO(println(x)) and suggests IO.println(x)', function()
      local source = [[val x = IO(println("hello"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.println)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.println("hello")',
        title = 'CE: replace IO(println(...)) with IO.println(...)',
      })
    end)

    it('matches IO(println(x)) with variable', function()
      local source = [[val x = IO(println(msg))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.println)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.println(msg)',
        title = 'CE: replace IO(println(...)) with IO.println(...)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- println_apply
  ---------------------------------------------------------------------------
  describe('println_apply', function()
    it('matches IO.apply(println(x)) and suggests IO.println(x)', function()
      local source = [[val x = IO.apply(println("hello"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.println_apply)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.println("hello")',
        title = 'CE: replace IO.apply(println(...)) with IO.println(...)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- print
  ---------------------------------------------------------------------------
  describe('print', function()
    it('matches IO(print(x)) and suggests IO.print(x)', function()
      local source = [[val x = IO(print("hello"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.print)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.print("hello")',
        title = 'CE: replace IO(print(...)) with IO.print(...)',
      })
    end)

    it('matches IO(print(x)) with variable', function()
      local source = [[val x = IO(print(msg))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.print)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.print(msg)',
        title = 'CE: replace IO(print(...)) with IO.print(...)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- print_apply
  ---------------------------------------------------------------------------
  describe('print_apply', function()
    it('matches IO.apply(print(x)) and suggests IO.print(x)', function()
      local source = [[val x = IO.apply(print("hello"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.print_apply)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'IO.print("hello")',
        title = 'CE: replace IO.apply(print(...)) with IO.print(...)',
      })
    end)
  end)
end)
