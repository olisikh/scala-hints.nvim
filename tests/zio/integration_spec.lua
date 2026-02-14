--- Integration tests for the diagnostic and code-action callback pipelines.
---
--- These tests verify that every ZIO query handler produces results that
--- correctly transform through make_diagnostic and make_code_action.
--- They exercise the full path: query_def -> query engine -> callback -> final shape.

local H = require('tests.helpers')
local queries = require('scala-hints.libs.zio.queries')
local constants = require('scala-hints.constants')

--- Mirrors diagnostics.lua make_diagnostic
local function make_diagnostic(result)
  local diagnostic = result.diagnostic
  return {
    lnum = diagnostic.row,
    col = diagnostic.start_col,
    end_lnum = diagnostic.row,
    end_col = diagnostic.end_col,
    message = result.title,
    source = constants.source,
    severity = vim.diagnostic.severity.HINT,
  }
end

--- Mirrors actions.lua make_code_action
local function make_code_action(result)
  local action = result.action
  return {
    title = result.title,
    range = {
      start = { line = action.start_row, character = action.start_col },
      ['end'] = { line = action.end_row, character = action.end_col },
    },
    replacement = result.replacement,
  }
end

--- Helper: run a query through the engine with make_diagnostic callback
local function run_as_diagnostic(bufnr, root, query_name, query_def)
  return H.run_query_engine(bufnr, root, query_name, query_def, make_diagnostic)
end

--- Helper: run a query through the engine with make_code_action callback
local function run_as_action(bufnr, root, query_name, query_def)
  return H.run_query_engine(bufnr, root, query_name, query_def, make_code_action)
end

--- Assert a diagnostic has the expected shape
local function assert_diagnostic_shape(diag)
  assert(diag.lnum ~= nil, 'diagnostic missing lnum')
  assert(diag.col ~= nil, 'diagnostic missing col')
  assert(diag.end_lnum ~= nil, 'diagnostic missing end_lnum')
  assert(diag.end_col ~= nil, 'diagnostic missing end_col')
  assert(diag.message ~= nil, 'diagnostic missing message')
  assert.are.equal(constants.source, diag.source)
  assert.are.equal(vim.diagnostic.severity.HINT, diag.severity)
end

--- Assert a code action has the expected shape
local function assert_action_shape(action)
  assert(action.title ~= nil, 'action missing title')
  assert(action.replacement ~= nil, 'action missing replacement')
  assert(action.range ~= nil, 'action missing range')
  assert(action.range.start ~= nil, 'action missing range.start')
  assert(action.range.start.line ~= nil, 'action missing range.start.line')
  assert(action.range.start.character ~= nil, 'action missing range.start.character')
  assert(action.range['end'] ~= nil, 'action missing range.end')
  assert(action.range['end'].line ~= nil, 'action missing range.end.line')
  assert(action.range['end'].character ~= nil, 'action missing range.end.character')
end

describe('ZIO diagnostics/actions integration', function()
  local bufnr

  after_each(function()
    H.restore_mocks()
    if bufnr then
      H.cleanup_buf(bufnr)
      bufnr = nil
    end
  end)

  ---------------------------------------------------------------------------
  -- succeed_unit (uses semantic.hover_predicate — async pending pattern)
  ---------------------------------------------------------------------------
  describe('succeed_unit (pending pattern)', function()
    it('produces valid diagnostic when hover confirms ZIO', function()
      H.mock_hover_predicate(true)
      bufnr, root = H.parse_scala([[val x = ZIO.succeed(())]])
      local diags = run_as_diagnostic(bufnr, root, 'succeed_unit', queries.succeed_unit)

      assert.are.equal(1, #diags)
      assert_diagnostic_shape(diags[1])
    end)

    it('produces valid action when hover confirms ZIO', function()
      H.mock_hover_predicate(true)
      bufnr, root = H.parse_scala([[val x = ZIO.succeed(())]])
      local actions = run_as_action(bufnr, root, 'succeed_unit', queries.succeed_unit)

      assert.are.equal(1, #actions)
      assert_action_shape(actions[1])
      assert.are.equal('unit', actions[1].replacement)
    end)

    it('produces nothing when hover says not ZIO', function()
      H.mock_hover_predicate(false)
      bufnr, root = H.parse_scala([[val x = ZIO.succeed(())]])
      local diags = run_as_diagnostic(bufnr, root, 'succeed_unit', queries.succeed_unit)

      assert.are.equal(0, #diags)
    end)
  end)

  ---------------------------------------------------------------------------
  -- Pure queries (no LSP mock needed)
  ---------------------------------------------------------------------------
  describe('pure queries produce valid diagnostics and actions', function()
    local pure_cases = {
      {
        name = 'fail_exception_or_die',
        source = [[val x = ZIO.fail(new Exception("err")).orDie]],
        query_name = 'fail_exception_or_die',
        query_def = queries.fail_exception_or_die,
        expected_count = 1,
        expected_replacement = 'ZIO.die(new Exception("err"))',
      },
      {
        name = 'zip_right_unit',
        source = [[val x = effect *> ZIO.unit]],
        query_name = 'zip_right_unit',
        query_def = queries.zip_right_unit,
        expected_count = 1,
        expected_replacement = '.unit',
      },
      {
        name = 'as_unit',
        source = [[val x = effect.as(())]],
        query_name = 'as_unit',
        query_def = queries.as_unit,
        expected_count = 1,
        expected_replacement = 'unit',
      },
      {
        name = 'zip_right_value',
        source = [[val x = effect *> ZIO.succeed(42)]],
        query_name = 'zip_right_value',
        query_def = queries.zip_right_value,
        expected_count = 1,
        expected_replacement = '.as(42)',
      },
      {
        name = 'or_else_fail3',
        source = [[val x = effect.flatMapError(_ => ZIO.succeed(newErr))]],
        query_name = 'or_else_fail3',
        query_def = queries.or_else_fail3,
        expected_count = 1,
        expected_replacement = 'orElseFail(newErr)',
      },
      {
        name = 'fold_cause_ignore',
        source = [[val x = effect.foldCause(_ => (), _ => ())]],
        query_name = 'fold_cause_ignore',
        query_def = queries.fold_cause_ignore,
        expected_count = 1,
        expected_replacement = 'ignore',
      },
      {
        name = 'zio_foreach',
        source = [[val x = ZIO.collectAll(items.map(process))]],
        query_name = 'zio_foreach',
        query_def = queries.zio_foreach,
        expected_count = 1,
        expected_replacement = 'ZIO.foreach(items)(process)',
      },
      {
        name = 'zio_none',
        source = [[val x = ZIO.succeed(None)]],
        query_name = 'zio_none',
        query_def = queries.zio_none,
        expected_count = 1,
        expected_replacement = 'ZIO.none',
      },
      {
        name = 'zio_some',
        source = [[val x = ZIO.succeed(Some(42))]],
        query_name = 'zio_some',
        query_def = queries.zio_some,
        expected_count = 1,
        expected_replacement = 'ZIO.some(42)',
      },
      {
        name = 'zio_either (Left)',
        source = [[val x = ZIO.succeed(Left(err))]],
        query_name = 'zio_either',
        query_def = queries.zio_either,
        expected_count = 1,
        expected_replacement = 'ZIO.left(err)',
      },
      {
        name = 'zio_either (Right)',
        source = [[val x = ZIO.succeed(Right(ok))]],
        query_name = 'zio_either',
        query_def = queries.zio_either,
        expected_count = 1,
        expected_replacement = 'ZIO.right(ok)',
      },
      {
        name = 'zio_either (asLeft)',
        source = [[val x = ZIO.succeed(err.asLeft)]],
        query_name = 'zio_either',
        query_def = queries.zio_either,
        expected_count = 1,
        expected_replacement = 'ZIO.left(err)',
      },
      {
        name = 'zio_either (asRight)',
        source = [[val x = ZIO.succeed(ok.asRight)]],
        query_name = 'zio_either',
        query_def = queries.zio_either,
        expected_count = 1,
        expected_replacement = 'ZIO.right(ok)',
      },
    }

    for _, tc in ipairs(pure_cases) do
      it(tc.name .. ' -> diagnostic', function()
        bufnr, root = H.parse_scala(tc.source)
        local diags = run_as_diagnostic(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(tc.expected_count, #diags, tc.name .. ': wrong diagnostic count')
        for _, d in ipairs(diags) do
          assert_diagnostic_shape(d)
        end
        if tc.expected_replacement then
          -- The replacement is in the message title, not directly accessible
          -- but we can verify it passes through make_diagnostic without error
          assert.is_truthy(diags[1].message)
        end
      end)

      it(tc.name .. ' -> action', function()
        bufnr, root = H.parse_scala(tc.source)
        local actions = run_as_action(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(tc.expected_count, #actions, tc.name .. ': wrong action count')
        for _, a in ipairs(actions) do
          assert_action_shape(a)
        end
        if tc.expected_replacement then
          assert.are.equal(tc.expected_replacement, actions[1].replacement)
        end
      end)
    end
  end)

  ---------------------------------------------------------------------------
  -- zio_type produces multiple diagnostics/actions for matching aliases
  ---------------------------------------------------------------------------
  describe('zio_type', function()
    it('produces valid diagnostics for ZIO[Any, Nothing, Int]', function()
      bufnr, root = H.parse_scala([[def foo: ZIO[Any, Nothing, Int] = ???]])
      local diags = run_as_diagnostic(bufnr, root, 'zio_type', queries.zio_type)

      -- Should produce 3 matches: UIO, IO, URIO
      assert.are.equal(3, #diags)
      for _, d in ipairs(diags) do
        assert_diagnostic_shape(d)
      end
    end)

    it('produces valid actions for ZIO[Any, Nothing, Int]', function()
      bufnr, root = H.parse_scala([[def foo: ZIO[Any, Nothing, Int] = ???]])
      local actions = run_as_action(bufnr, root, 'zio_type', queries.zio_type)

      assert.are.equal(3, #actions)
      local replacements = {}
      for _, a in ipairs(actions) do
        assert_action_shape(a)
        table.insert(replacements, a.replacement)
      end
      assert.is_truthy(vim.tbl_contains(replacements, 'UIO[Int]'))
      assert.is_truthy(vim.tbl_contains(replacements, 'IO[Nothing, Int]'))
      assert.is_truthy(vim.tbl_contains(replacements, 'URIO[Any, Int]'))
    end)

    it('produces 1 action for ZIO[Env, Nothing, Int] (URIO only)', function()
      bufnr, root = H.parse_scala([[def foo: ZIO[Env, Nothing, Int] = ???]])
      local actions = run_as_action(bufnr, root, 'zio_type', queries.zio_type)

      assert.are.equal(1, #actions)
      assert.are.equal('URIO[Env, Int]', actions[1].replacement)
    end)

    it('produces 0 actions for ZIO[Env, AppError, Int]', function()
      bufnr, root = H.parse_scala([[def foo: ZIO[Env, AppError, Int] = ???]])
      local actions = run_as_action(bufnr, root, 'zio_type', queries.zio_type)

      assert.are.equal(0, #actions)
    end)
  end)

  ---------------------------------------------------------------------------
  -- zlayer_type
  ---------------------------------------------------------------------------
  describe('zlayer_type', function()
    it('produces valid actions for ZLayer[Any, Nothing, UserService]', function()
      bufnr, root = H.parse_scala([[def layer: ZLayer[Any, Nothing, UserService] = ???]])
      local actions = run_as_action(bufnr, root, 'zlayer_type', queries.zlayer_type)

      assert.are.equal(3, #actions)
      local replacements = {}
      for _, a in ipairs(actions) do
        assert_action_shape(a)
        table.insert(replacements, a.replacement)
      end
      assert.is_truthy(vim.tbl_contains(replacements, 'ULayer[UserService]'))
      assert.is_truthy(vim.tbl_contains(replacements, 'Layer[Nothing, UserService]'))
      assert.is_truthy(vim.tbl_contains(replacements, 'URLayer[Any, UserService]'))
    end)

    it('produces 1 action for ZLayer[Any, AppError, Svc] (Layer only)', function()
      bufnr, root = H.parse_scala([[def layer: ZLayer[Any, AppError, Svc] = ???]])
      local actions = run_as_action(bufnr, root, 'zlayer_type', queries.zlayer_type)

      assert.are.equal(1, #actions)
      assert.are.equal('Layer[AppError, Svc]', actions[1].replacement)
    end)
  end)

  ---------------------------------------------------------------------------
  -- LSP-dependent queries produce valid shapes when mocked true
  ---------------------------------------------------------------------------
  describe('LSP-dependent queries produce valid diagnostics and actions', function()
    local lsp_cases = {
      {
        name = 'map_unit',
        source = [[val x = effect.map(_ => ())]],
        query_name = 'map_unit',
        query_def = queries.map_unit,
        expected_count = 1,
        expected_replacement = 'unit',
      },
      {
        name = 'zip_left_value',
        source = [[val x = effect.tap(_ => sideEffect)]],
        query_name = 'zip_left_value',
        query_def = queries.zip_left_value,
        expected_count = 2, -- <* and .zipLeft
      },
      {
        name = 'flat_map_value',
        source = [[val x = effect.flatMap(_ => otherEffect)]],
        query_name = 'flat_map_value',
        query_def = queries.flat_map_value,
        expected_count = 2, -- *> and .zipRight
      },
      {
        name = 'map_value',
        source = [[val x = effect.map(_ => 42)]],
        query_name = 'map_value',
        query_def = queries.map_value,
        expected_count = 1,
        expected_replacement = 'as(42)',
      },
      {
        name = 'catch_all_unit',
        source = [[val x = effect.catchAll(_ => ZIO.unit)]],
        query_name = 'catch_all_unit',
        query_def = queries.catch_all_unit,
        expected_count = 1,
        expected_replacement = 'ignore',
      },
      {
        name = 'or_else_fail',
        source = [[val x = effect.mapError(_ => newErr)]],
        query_name = 'or_else_fail',
        query_def = queries.or_else_fail,
        expected_count = 1,
        expected_replacement = 'orElseFail(newErr)',
      },
      {
        name = 'or_else_fail2',
        source = [[val x = effect.orElse(ZIO.fail(newErr))]],
        query_name = 'or_else_fail2',
        query_def = queries.or_else_fail2,
        expected_count = 1,
        expected_replacement = 'orElseFail(newErr)',
      },
    }

    for _, tc in ipairs(lsp_cases) do
      it(tc.name .. ' -> diagnostic (hover=true)', function()
        H.mock_hover_node_and_match(true)
        bufnr, root = H.parse_scala(tc.source)
        local diags = run_as_diagnostic(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(tc.expected_count, #diags, tc.name .. ': wrong diagnostic count')
        for _, d in ipairs(diags) do
          assert_diagnostic_shape(d)
        end
      end)

      it(tc.name .. ' -> action (hover=true)', function()
        H.mock_hover_node_and_match(true)
        bufnr, root = H.parse_scala(tc.source)
        local actions = run_as_action(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(tc.expected_count, #actions, tc.name .. ': wrong action count')
        for _, a in ipairs(actions) do
          assert_action_shape(a)
        end
        if tc.expected_replacement then
          assert.are.equal(tc.expected_replacement, actions[1].replacement)
        end
      end)

      it(tc.name .. ' -> diagnostic (hover=false)', function()
        H.mock_hover_node_and_match(false)
        bufnr, root = H.parse_scala(tc.source)
        local diags = run_as_diagnostic(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(0, #diags, tc.name .. ': should produce 0 diagnostics when hover=false')
      end)

      it(tc.name .. ' -> action (hover=false)', function()
        H.mock_hover_node_and_match(false)
        bufnr, root = H.parse_scala(tc.source)
        local actions = run_as_action(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(0, #actions, tc.name .. ': should produce 0 actions when hover=false')
      end)
    end
  end)

  ---------------------------------------------------------------------------
  -- Action range consistency: start < end
  ---------------------------------------------------------------------------
  describe('action ranges are consistent', function()
    local range_cases = {
      { name = 'as_unit', source = [[val x = effect.as(())]], qd = queries.as_unit },
      { name = 'zip_right_unit', source = [[val x = effect *> ZIO.unit]], qd = queries.zip_right_unit },
      { name = 'zip_right_value', source = [[val x = effect *> ZIO.succeed(42)]], qd = queries.zip_right_value },
      { name = 'fold_cause_ignore', source = [[val x = effect.foldCause(_ => (), _ => ())]], qd = queries.fold_cause_ignore },
      { name = 'zio_none', source = [[val x = ZIO.succeed(None)]], qd = queries.zio_none },
      { name = 'zio_some', source = [[val x = ZIO.succeed(Some(42))]], qd = queries.zio_some },
    }

    for _, tc in ipairs(range_cases) do
      it(tc.name .. ' has valid range (start <= end)', function()
        bufnr, root = H.parse_scala(tc.source)
        local actions = run_as_action(bufnr, root, tc.name, tc.qd)

        assert.is_true(#actions >= 1, tc.name .. ': expected at least 1 action')
        for _, a in ipairs(actions) do
          local s = a.range.start
          local e = a.range['end']
          local start_before_end = (s.line < e.line) or (s.line == e.line and s.character <= e.character)
          assert.is_true(start_before_end, tc.name .. ': range start must be <= end')
        end
      end)
    end
  end)
end)
