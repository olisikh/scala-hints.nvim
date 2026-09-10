--- Tests for Monix queries with type definition verification.
--- All handlers use semantic.type_definition_predicate (mocked to return true).

local H = require('tests.helpers')
local queries = require('scala-hints.libs.monix.queries')

describe('Monix queries with type definition verification', function()
  local bufnr
  local root

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
  -- now_unit
  ---------------------------------------------------------------------------
  describe('now_unit', function()
    it('matches Task.now(()) and suggests Task.unit', function()
      local source = [[val x = Task.now(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.now_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.unit',
        title = 'Monix: replace Task.now(()) with Task.unit',
      })
    end)

    it('matches Task.pure(()) and suggests Task.unit', function()
      local source = [[val x = Task.pure(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.now_unit)

      assert.are.equal(0, #ready)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.unit',
      })
    end)

    it('does not match Task.now(42)', function()
      local source = [[val x = Task.now(42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.now_unit)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- task_none
  ---------------------------------------------------------------------------
  describe('task_none', function()
    it('matches Task.now(None) and suggests Task.none', function()
      local source = [[val x = Task.now(None)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_none)

      local results = H.resolve_pending(pending)
      assert.are.equal(0, #ready)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.none',
        title = 'Monix: replace Task.now(None) with Task.none',
      })
    end)

    it('does not match Task.now(Some(1))', function()
      local source = [[val x = Task.now(Some(1))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_none)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- task_some
  ---------------------------------------------------------------------------
  describe('task_some', function()
    it('matches Task.now(Some(v)) and suggests Task.some(v)', function()
      local source = [[val x = Task.now(Some(42))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_some)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.some(42)',
        title = 'Monix: replace Task.now(Some(v)) with Task.some(v)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- task_either
  ---------------------------------------------------------------------------
  describe('task_either', function()
    it('matches Task.now(Right(v)) and suggests Task.right(v)', function()
      local source = [[val x = Task.now(Right(42))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_either)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.right(42)',
      })
    end)

    it('matches Task.now(Left(v)) and suggests Task.left(v)', function()
      local source = [[val x = Task.now(Left("err"))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_either)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.left("err")',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- map_unit
  ---------------------------------------------------------------------------
  describe('map_unit', function()
    it('matches .map(_ => ()) and suggests .void', function()
      local source = [[val x = Task(1).map(_ => ())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_unit)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'void',
        title = 'Monix: replace .map(_ => ()) with .void',
      })
    end)

    it('does not match .map(x => ())', function()
      local source = [[val x = Task(1).map(x => ())]]
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
      local source = [[val x = Task(1).map(_ => 42)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.map_value)

      assert.are.equal(0, #ready)
      assert.are.equal(1, #pending)
      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'as(42)',
        title = 'Monix: replace .map(_ => 42) with .as(42)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- tap_eval
  ---------------------------------------------------------------------------
  describe('tap_eval', function()
    it('matches .map(v => { eff(v); v }) and suggests .tapEval', function()
      -- Body expression is Task-typed (logTask), matching what the handler
      -- verifies against Metals in real usage.
      local source = [[val x = Task(1).map(v => { logTask(v); v })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_eval)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'tapEval(v => logTask(v))',
        title = 'Monix: replace .map returning its parameter with .tapEval',
      })
    end)

    it('does not match when last expression is not the parameter', function()
      local source = [[val x = Task(1).map(v => { logTask(v); other })]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.tap_eval)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- flat_tap_eval
  ---------------------------------------------------------------------------
  describe('flat_tap_eval', function()
    it('matches .flatMap(a => effect.as(a)) and suggests .tapEval', function()
      local source = [[val x = Task(1).flatMap(a => Task.evalAsync(println(a)).as(a))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.flat_tap_eval)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.tapEval(a => Task.evalAsync(println(a)))',
        title = 'Monix: replace .flatMap returning its parameter with .tapEval',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- redeem
  ---------------------------------------------------------------------------
  describe('redeem', function()
    it('matches .attempt.map { Right/Left } and suggests .redeem', function()
      local source = [[val x = Task(1).attempt.map {
  case Right(v) => v + 1
  case Left(e) => 0
}]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.redeem)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.redeem(e => 0, v => v + 1)',
        title = 'Monix: replace .attempt.map with .redeem',
      })
    end)

    it('chooses redeemWith when a case body returns a Task', function()
      local source = [[val x = Task(1).attempt.map {
  case Right(v) => Task.now(v)
  case Left(e) => Task.raiseError(e)
}]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.redeem)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      assert.is_truthy(results[1].replacement:find('^%.redeemWith%('))
    end)

    it('does not match attempt.map with only one case', function()
      local source = [[val x = Task(1).attempt.map {
  case Right(v) => v + 1
}]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.redeem)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- redeem_with
  ---------------------------------------------------------------------------
  describe('redeem_with', function()
    it('matches .attempt.flatMap { Right/Left } and suggests .redeemWith', function()
      local source = [[val x = Task(1).attempt.flatMap {
  case Right(v) => Task.now(v + 1)
  case Left(e) => Task.now(0)
}]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.redeem_with)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = '.redeemWith(e => Task.now(0), v => Task.now(v + 1))',
        title = 'Monix: replace .attempt.flatMap with .redeemWith',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- from_either
  ---------------------------------------------------------------------------
  describe('from_either', function()
    it('matches either.fold(Task.raiseError, Task.now) and suggests Task.fromEither', function()
      local source = [[val x = either.fold(Task.raiseError, Task.now)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_either)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.fromEither(either)',
        title = 'Monix: replace .fold(Task.raiseError, Task.now) with Task.fromEither',
      })
    end)

    it('does not match when the fold functions are not Task combinators', function()
      local source = [[val x = either.fold(Task.raiseError, other)]]
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
    it('matches Try(x).fold(Task.raiseError, Task.now) and suggests Task.fromTry', function()
      local source = [[val x = Try(1).fold(Task.raiseError, Task.now)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_try)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.fromTry(Try(1))',
        title = 'Monix: replace .fold(Task.raiseError, Task.now) with Task.fromTry',
      })
    end)

    it('does not match a non-Try fold', function()
      local source = [[val x = other(1).fold(Task.raiseError, Task.now)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.from_try)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- sequence_traverse
  ---------------------------------------------------------------------------
  describe('sequence_traverse', function()
    it('matches Task.sequence(coll.map(f)) and suggests Task.traverse', function()
      local source = [[val x = Task.sequence(list.map(f))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.sequence_traverse)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.traverse(list)(f)',
        title = 'Monix: replace Task.sequence(coll.map(f)) with Task.traverse(coll)(f)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- par_traverse_n
  ---------------------------------------------------------------------------
  describe('par_traverse_n', function()
    it('matches Task.parTraverse(coll)(f) and suggests parTraverseN', function()
      local source = [[val x = Task.parTraverse(list)(f)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.par_traverse_n)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.parTraverseN(n)(list)(f)',
        title = 'Monix: replace Task.parTraverse with Task.parTraverseN (specify parallelism)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- par_sequence_n
  ---------------------------------------------------------------------------
  describe('par_sequence_n', function()
    it('matches Task.parSequence(coll) and suggests parSequenceN', function()
      local source = [[val x = Task.parSequence(list)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.par_sequence_n)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.parSequenceN(n)(list)',
        title = 'Monix: replace Task.parSequence with Task.parSequenceN (specify parallelism)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- delay_execution
  ---------------------------------------------------------------------------
  describe('delay_execution', function()
    it('matches Task.sleep(d) *> effect and suggests effect.delayExecution(d)', function()
      local source = [[val x = Task.sleep(5.seconds) *> loadUser(1)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay_execution)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'loadUser(1).delayExecution(5.seconds)',
        title = 'Monix: replace Task.sleep(d) *> effect with effect.delayExecution(d)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- delay_execution_flatmap
  ---------------------------------------------------------------------------
  describe('delay_execution_flatmap', function()
    it('matches Task.sleep(d).flatMap(_ => effect) and suggests delayExecution', function()
      local source = [[val x = Task.sleep(5.seconds).flatMap(_ => loadUser(1))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.delay_execution_flatmap)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'loadUser(1).delayExecution(5.seconds)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- task_when
  ---------------------------------------------------------------------------
  describe('task_when', function()
    it('matches if (cond) effect else Task.unit and suggests Task.when', function()
      local source = [[val x = if (cond) save(u) else Task.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_when)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.when(cond)(save(u))',
        title = 'Monix: replace if/else with Task.when(cond)(effect)',
      })
    end)

    it('matches if (!cond) Task.unit else effect (flipped branches)', function()
      local source = [[val x = if (!cond) Task.unit else save(u)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_when)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.when(cond)(save(u))',
      })
    end)

    it('does not match when neither branch is Task.unit', function()
      local source = [[val x = if (cond) save(u) else loadUser(1)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_when)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- task_unless
  ---------------------------------------------------------------------------
  describe('task_unless', function()
    it('matches if (!cond) effect else Task.unit and suggests Task.unless', function()
      local source = [[val x = if (!cond) save(u) else Task.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_unless)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.unless(cond)(save(u))',
      })
    end)

    it('matches if (cond) Task.unit else effect (flipped branches)', function()
      local source = [[val x = if (cond) Task.unit else save(u)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.task_unless)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.unless(cond)(save(u))',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- raise_when
  ---------------------------------------------------------------------------
  describe('raise_when', function()
    it('matches if (cond) Task.raiseError(e) else Task.unit and suggests Task.raiseWhen', function()
      local source = [[val x = if (cond) Task.raiseError(err) else Task.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_when)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.raiseWhen(cond)(err)',
        title = 'Monix: replace if (cond) Task.raiseError(e) else Task.unit with Task.raiseWhen(cond)(e)',
      })
    end)

    it('does not match when the consequence is not Task.raiseError', function()
      local source = [[val x = if (cond) save(u) else Task.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_when)
      assert.are.equal(0, #ready)
      assert.are.equal(0, #pending)
    end)
  end)

  ---------------------------------------------------------------------------
  -- raise_unless
  ---------------------------------------------------------------------------
  describe('raise_unless', function()
    it('matches if (!cond) Task.raiseError(e) else Task.unit and suggests Task.raiseUnless', function()
      local source = [[val x = if (!cond) Task.raiseError(err) else Task.unit]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.raise_unless)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Task.raiseUnless(cond)(err)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- obs_now_unit
  ---------------------------------------------------------------------------
  describe('obs_now_unit', function()
    it('matches Observable.now(()) and suggests Observable.unit', function()
      local source = [[val x = Observable.now(())]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.obs_now_unit)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'Observable.unit',
        title = 'Monix: replace Observable.now(()) with Observable.unit',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- obs_map_eval_now
  ---------------------------------------------------------------------------
  describe('obs_map_eval_now', function()
    it('matches .mapEval(a => Task.now(v)) and suggests .map', function()
      local source = [[val x = obs.mapEval(a => Task.now(a + 1))]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.obs_map_eval_now)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'map(a => a + 1)',
        title = 'Monix: replace .mapEval(a => Task.now(v)) with .map(a => v)',
      })
    end)
  end)

  ---------------------------------------------------------------------------
  -- obs_switch_if_empty
  ---------------------------------------------------------------------------
  describe('obs_switch_if_empty', function()
    it('matches .switchIfEmpty(Observable.empty) and suggests removing it', function()
      local source = [[val x = obs.switchIfEmpty(Observable.empty)]]
      bufnr, root = H.parse_scala(source)

      local ready, pending = H.run_handler(bufnr, root, queries.obs_switch_if_empty)

      local results = H.resolve_pending(pending)
      assert.are.equal(1, #results)
      H.assert_result(results[1], {
        replacement = 'obs',
        title = 'Monix: remove no-op .switchIfEmpty(Observable.empty)',
      })
    end)
  end)
end)