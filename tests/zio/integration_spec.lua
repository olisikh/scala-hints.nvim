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
  -- succeed_unit, map_unit, zip_left_value, flat_map_value, map_value,
  -- catch_all_unit, or_else_fail, or_else_fail2 (all use async pending pattern)
  ---------------------------------------------------------------------------
  describe('LSP-dependent queries with semantic.hover_predicate', function()
    local lsp_cases = {
      {
        name = 'succeed_unit',
        source = [[val x = ZIO.succeed(())]],
        query_name = 'succeed_unit',
        query_def = queries.succeed_unit,
        expected_count = 1,
        expected_replacement = 'unit',
      },
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
        H.mock_hover_predicate(true)
        bufnr, root = H.parse_scala(tc.source)
        local diags = run_as_diagnostic(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(tc.expected_count, #diags, tc.name .. ': wrong diagnostic count')
        for _, d in ipairs(diags) do
          assert_diagnostic_shape(d)
        end
      end)

      it(tc.name .. ' -> action (hover=true)', function()
        H.mock_hover_predicate(true)
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
        H.mock_hover_predicate(false)
        bufnr, root = H.parse_scala(tc.source)
        local diags = run_as_diagnostic(bufnr, root, tc.query_name, tc.query_def)

        assert.are.equal(0, #diags, tc.name .. ': should produce 0 diagnostics when hover=false')
      end)

      it(tc.name .. ' -> action (hover=false)', function()
        H.mock_hover_predicate(false)
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
      { name = 'zio_none_lower', source = [[val x = ZIO.succeed(none)]], qd = queries.zio_none },
      { name = 'zio_some', source = [[val x = ZIO.succeed(Some(42))]], qd = queries.zio_some },
      { name = 'zio_some_extension', source = [[val x = ZIO.succeed(1.some)]], qd = queries.zio_some },
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
