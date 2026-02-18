--- Cats (tagless-final) Treesitter query definitions and handlers
---
--- Each entry has:
---   query   = parsed Treesitter query (TSQuery)
---   handler = function(bufnr, matches) -> results table

local utils = require('scala-hints.utils')
local evidence = require('scala-hints.cats.evidence')
local ts = vim.treesitter

local function parse_query(query)
  return ts.query.parse('scala', query)
end

local function normalize_condition_text(text)
  local trimmed = vim.trim(text)
  if trimmed:sub(1, 1) == '(' and trimmed:sub(-1) == ')' then
    trimmed = vim.trim(trimmed:sub(2, -2))
  end
  return trimmed
end

local function strip_negation(text)
  local trimmed = vim.trim(text)
  if trimmed:sub(1, 1) ~= '!' then
    return nil
  end
  local inner = vim.trim(trimmed:sub(2))
  if inner:sub(1, 1) == '(' and inner:sub(-1) == ')' then
    inner = vim.trim(inner:sub(2, -2))
  end
  return inner
end

local function unwrap_single_expression_block(bufnr, node)
  if node then
    local node_type = node:type()
    if node_type == 'block' or node_type == 'indented_block' then
      if node:named_child_count() == 1 then
        local child = node:named_child(0)
        return utils.get_node_text(bufnr, child)
      end
    end
  end
  return utils.get_node_text(bufnr, node)
end

local function collect_case_clauses(node, out)
  out = out or {}
  if not node then
    return out
  end
  if node:type() == 'case_clause' then
    table.insert(out, node)
    return out
  end
  for child in node:iter_children() do
    collect_case_clauses(child, out)
  end
  return out
end

local function extract_case_map(bufnr, match_node)
  local cases = collect_case_clauses(match_node, {})
  local case_map = {}
  for _, case_node in ipairs(cases) do
    local text = utils.get_node_text(bufnr, case_node)
    local ctor, param, body = text:match('case%s+([%w_]+)%s*%(([%w_]+)%)%s*=>%s*([%s%S]+)')
    if not ctor then
      ctor, body = text:match('case%s+([%w_]+)%s*=>%s*([%s%S]+)')
      param = '_'
    end
    if ctor and body then
      case_map[ctor] = { param = param, body = vim.trim(body) }
    end
  end
  return case_map
end

local function contains_identifier(text, ident)
  if not text or not ident or ident == '' then
    return false
  end
  local escaped = vim.pesc(ident)
  return text:find('%f[%w_]' .. escaped .. '%f[^%w_]') ~= nil
end

local function is_tagless_unit_text(text)
  local trimmed = vim.trim(text or '')
  if trimmed == '' then
    return false
  end

  if trimmed == 'F.unit' then
    return true
  end

  if trimmed:match('%.unit$') then
    if trimmed:match('Applicative%[') or trimmed:match('Monad%[') or trimmed:match('Sync%[') then
      return true
    end
  end

  return false
end

local function extract_raise_error_info(bufnr, node)
  if not node then
    return nil
  end

  local text = unwrap_single_expression_block(bufnr, node)
  if not text then
    return nil
  end

  local prefix = text:match('^(.-)%.raiseError')
  if not prefix or vim.trim(prefix) == '' then
    return nil
  end

  local argument = text:match('%.raiseError%((.+)%)')
  if not argument then
    return nil
  end

  return vim.trim(prefix), vim.trim(argument)
end

return {
  -- fa.map(_ => ()) ~> fa.void
  map_unit = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "map")
  )
  (arguments
    (lambda_expression
      parameters: (wildcard)
      (unit)
    )
  ) @_3
)
]]),
    handler = function(bufnr, matches)
      local target = matches[2][1]
      local finish = matches[3][1]

      if not evidence.has_capability(bufnr, target, 'Functor') then
        return {}
      end

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = 'void',
          title = 'Cats: replace .map(_ => ()) with .void',
        },
      }
    end,
  },

  -- fa.map(_ => value) ~> fa.as(value)
  map_value = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "map")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard)
      (_) @_3 (#not-eq? @_3 "()")
    )
  ) @_4
)
]]),
    handler = function(bufnr, matches)
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      if not evidence.has_capability(bufnr, target, 'Functor') then
        return {}
      end

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()
      local value_text = utils.get_node_text(bufnr, value)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'as(' .. value_text .. ')',
          title = 'Cats: replace .map(_ => ' .. value_text .. ') with .as(' .. value_text .. ')',
        },
      }
    end,
  },

  -- fa.flatMap(_ => fb) ~> fa *> fb
  flat_map_value = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "flatMap")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard) (_) @_3
    )
  ) @_4
)
]]),
    handler = function(bufnr, matches)
      local start = matches[1][1]
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      if not evidence.has_capability(bufnr, target, 'Apply') then
        return {}
      end

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)
      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = ' *> ' .. value_text,
          title = 'Cats: replace .flatMap(_ => ' .. value_text .. ') with *> ' .. value_text,
        },
      }
    end,
  },

  -- if (condition) effect else F.unit ~> effect.whenA(condition)
  when_a = {
    query = parse_query([[
(if_expression
  condition: (_) @_1
  consequence: (_) @_2
  alternative: (_) @_3
) @_6
]]),
    handler = function(bufnr, matches)
      local condition = matches[1][1]
      local consequence = matches[2][1]
      local alternative = matches[3][1]
      local node = matches[4][1]

      local start_row, start_col, end_row, end_col = node:range()

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local negated_inner = strip_negation(condition_text)

      local consequence_text = unwrap_single_expression_block(bufnr, consequence)
      local alternative_text = unwrap_single_expression_block(bufnr, alternative)

      local consequence_is_unit = is_tagless_unit_text(consequence_text)
      local alternative_is_unit = is_tagless_unit_text(alternative_text)

      local replacement_effect
      local replacement_condition
      local verify_target
      if alternative_is_unit and not negated_inner then
        replacement_effect = consequence_text
        replacement_condition = condition_text
        verify_target = consequence
      elseif consequence_is_unit and negated_inner then
        replacement_effect = alternative_text
        replacement_condition = negated_inner
        verify_target = alternative
      else
        return {}
      end

      if not evidence.has_capability(bufnr, verify_target, 'Applicative') then
        return {}
      end

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = replacement_effect .. '.whenA(' .. replacement_condition .. ')',
          title = 'Cats: replace if (...) effect else F.unit with effect.whenA(...)',
        },
      }
    end,
  },

  -- if (!cond) fa else F.unit ~> fa.unlessA(cond)
  -- if (cond) F.unit else fa ~> fa.unlessA(cond)
  unless_a = {
    query = parse_query([[
(if_expression
  condition: (_) @_1
  consequence: (_) @_2
  alternative: (_) @_3
) @_6
]]),
    handler = function(bufnr, matches)
      local condition = matches[1][1]
      local consequence = matches[2][1]
      local alternative = matches[3][1]
      local node = matches[4][1]

      local start_row, start_col, end_row, end_col = node:range()

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local negated_inner = strip_negation(condition_text)

      local consequence_text = unwrap_single_expression_block(bufnr, consequence)
      local alternative_text = unwrap_single_expression_block(bufnr, alternative)

      local consequence_is_unit = is_tagless_unit_text(consequence_text)
      local alternative_is_unit = is_tagless_unit_text(alternative_text)

      local replacement_effect
      local replacement_condition
      local verify_target

      if alternative_is_unit and negated_inner then
        replacement_effect = consequence_text
        replacement_condition = negated_inner
        verify_target = consequence
      elseif consequence_is_unit and not negated_inner then
        replacement_effect = alternative_text
        replacement_condition = condition_text
        verify_target = alternative
      else
        return {}
      end

      if not evidence.has_capability(bufnr, verify_target, 'Applicative') then
        return {}
      end

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = replacement_effect .. '.unlessA(' .. replacement_condition .. ')',
          title = 'Cats: replace if (...) F.unit with effect.unlessA(...)',
        },
      }
    end,
  },

  -- fb.flatMap(b => if (b) fa else fc) ~> fb.ifM(fa, fc)
  if_m = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "flatMap")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_3
      (if_expression
        condition: (_) @_4
        consequence: (_) @_5
        alternative: (_) @_6
      )
    )
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local target = matches[2][1]
      local param = matches[3][1]
      local condition = matches[4][1]
      local consequence = matches[5][1]
      local alternative = matches[6][1]
      local finish = matches[7][1]

      local param_text = utils.get_node_text(bufnr, param)
      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      if condition_text ~= param_text then
        return {}
      end

      if not evidence.has_capability(bufnr, target, 'Monad') then
        return {}
      end

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local consequence_text = unwrap_single_expression_block(bufnr, consequence)
      local alternative_text = unwrap_single_expression_block(bufnr, alternative)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'ifM(' .. consequence_text .. ', ' .. alternative_text .. ')',
          title = 'Cats: replace .flatMap(b => if (b) ...) with .ifM',
        },
      }
    end,
  },

  -- fa.attempt.flatMap { case Right(a) => F.pure(a); case Left(e) => F.pure(default) }
  --   ~> fa.handleError(_ => default) or fa.handleErrorWith(e => F.pure(default(e)))
  handle_error = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "attempt")
    ) @_3
    field: (identifier) @_4 (#eq? @_4 "flatMap")
  )
  arguments: (_) @_5
)
]]),
    handler = function(bufnr, matches)
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]

      if not evidence.has_capability(bufnr, attempt_id, 'MonadError') then
        return {}
      end

      local case_map = extract_case_map(bufnr, match_node)

      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local right_prefix, right_pure = right.body:match('^(.-)%.pure%((.+)%)$')
      if not right_pure or vim.trim(right_pure) ~= right.param then
        return {}
      end

      local left_prefix, left_pure = left.body:match('^(.-)%.pure%((.+)%)$')
      if not left_pure then
        return {}
      end

      local pure_prefix = left_prefix ~= '' and left_prefix or right_prefix

      local replacement
      if left.param ~= '_' and contains_identifier(left_pure, left.param) and pure_prefix then
        replacement = 'handleErrorWith(' .. left.param .. ' => ' .. pure_prefix .. '.pure(' .. left_pure .. '))'
      else
        replacement = 'handleError(_ => ' .. left_pure .. ')'
      end

      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = match_node:range()

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = '.' .. replacement,
          title = 'Cats: replace .attempt.flatMap with .handleError',
        },
      }
    end,
  },
  -- if (cond) F.raiseError(err) else F.unit ~> F.raiseWhen(cond)(err)
  raise_when = {
    query = parse_query([[
(if_expression
  condition: (_) @_1
  consequence: (_) @_2
  alternative: (_) @_3
) @_6
]]),
    handler = function(bufnr, matches)
      local condition = matches[1][1]
      local consequence = matches[2][1]
      local alternative = matches[3][1]
      local node = matches[4][1]

      local start_row, start_col, end_row, end_col = node:range()

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local negated_inner = strip_negation(condition_text)

      local consequence_text = unwrap_single_expression_block(bufnr, consequence)
      local alternative_text = unwrap_single_expression_block(bufnr, alternative)

      local consequence_is_unit = is_tagless_unit_text(consequence_text)
      local alternative_is_unit = is_tagless_unit_text(alternative_text)

      local error_node
      local replacement_condition

      if alternative_is_unit and not consequence_is_unit and not negated_inner then
        error_node = consequence
        replacement_condition = condition_text
      elseif consequence_is_unit and not alternative_is_unit and negated_inner then
        error_node = alternative
        replacement_condition = negated_inner
      else
        return {}
      end

      local prefix, error_text = extract_raise_error_info(bufnr, error_node)
      if not prefix or not error_text then
        return {}
      end

      if not evidence.has_capability(bufnr, error_node, 'MonadError') then
        return {}
      end

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = prefix .. '.raiseWhen(' .. replacement_condition .. ')(' .. error_text .. ')',
          title = 'Cats: replace if (...) raiseError/F.unit with raiseWhen',
        },
      }
    end,
  },
  -- if (cond) F.unit else F.raiseError(err) ~> F.raiseUnless(cond)(err)
  raise_unless = {
    query = parse_query([[
(if_expression
  condition: (_) @_1
  consequence: (_) @_2
  alternative: (_) @_3
) @_6
]]),
    handler = function(bufnr, matches)
      local condition = matches[1][1]
      local consequence = matches[2][1]
      local alternative = matches[3][1]
      local node = matches[4][1]

      local start_row, start_col, end_row, end_col = node:range()

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local negated_inner = strip_negation(condition_text)

      local consequence_text = unwrap_single_expression_block(bufnr, consequence)
      local alternative_text = unwrap_single_expression_block(bufnr, alternative)

      local consequence_is_unit = is_tagless_unit_text(consequence_text)
      local alternative_is_unit = is_tagless_unit_text(alternative_text)

      local error_node
      local replacement_condition

      if consequence_is_unit and not alternative_is_unit and not negated_inner then
        error_node = alternative
        replacement_condition = condition_text
      elseif alternative_is_unit and not consequence_is_unit and negated_inner then
        error_node = consequence
        replacement_condition = negated_inner
      else
        return {}
      end

      local prefix, error_text = extract_raise_error_info(bufnr, error_node)
      if not prefix or not error_text then
        return {}
      end

      if not evidence.has_capability(bufnr, error_node, 'MonadError') then
        return {}
      end

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = prefix .. '.raiseUnless(' .. replacement_condition .. ')(' .. error_text .. ')',
          title = 'Cats: replace if (...) unit/raiseError with raiseUnless',
        },
      }
    end,
  },
  -- opt.fold(F.raiseError(err))(F.pure) ~> F.fromOption(opt)(err)
  from_option = {
    query = parse_query([[
(call_expression
  function: (call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "fold")
    )
    arguments: (arguments
      (call_expression
        function: (field_expression
          value: (identifier) @_3 (#eq? @_3 "F")
          field: (identifier) @_4 (#eq? @_4 "raiseError")
        )
        arguments: (arguments
          (_) @_5
        )
      )
    )
  )
  arguments: (arguments
    (_) @_6
  )
) @_7
]]),
    handler = function(bufnr, matches)
      local opt = matches[1][1]
      local err = matches[5][1]
      local success_handler = matches[6][1]
      local finish = matches[7][1]

      local success_text = utils.get_node_text(bufnr, success_handler)
      if not success_text or not success_text:match('F%.pure') then
        return {}
      end

      local opt_text = utils.get_node_text(bufnr, opt)
      local err_text = utils.get_node_text(bufnr, err)
      if not opt_text or not err_text then
        return {}
      end

      local verify_target = finish
      if not evidence.has_capability(bufnr, verify_target, 'MonadError') then
        return {}
      end

      local start_row, start_col, _, _ = opt:range()
      local _, _, end_row, end_col = finish:range()

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = 'F.fromOption(' .. opt_text .. ')(' .. err_text .. ')',
          title = 'Cats: replace .fold(F.raiseError)(F.pure) with F.fromOption',
        },
      }
    end,
  },
  -- either.fold(F.raiseError, F.pure) ~> F.fromEither(either)
  from_either = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_either
    field: (identifier) @_fold (#eq? @_fold "fold")
  )
  arguments: (arguments
    (_) @_raise_handler
    (_) @_pure_handler
  )
) @_finish
]]),
    handler = function(bufnr, matches)
      local either = matches[1][1]
      local raise_handler = matches[3][1]
      local pure_handler = matches[4][1]
      local finish = matches[5][1]

      local raise_text = utils.get_node_text(bufnr, raise_handler)
      local pure_text = utils.get_node_text(bufnr, pure_handler)
      if not raise_text or not pure_text then
        return {}
      end

      if not raise_text:match('F%.raiseError') then
        return {}
      end

      if not pure_text:match('F%.pure') then
        return {}
      end

      local either_text = utils.get_node_text(bufnr, either)
      if not either_text then
        return {}
      end

      local verify_target = finish
      if not evidence.has_capability(bufnr, verify_target, 'MonadError') then
        return {}
      end

      local start_row, start_col, _, _ = either:range()
      local _, _, end_row, end_col = finish:range()

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = 'F.fromEither(' .. either_text .. ')',
          title = 'Cats: replace .fold(F.raiseError, F.pure) with F.fromEither',
        },
      }
    end,
  },
  -- fa.attempt.map { case Right(a) => f(a); case Left(e) => g(e) } ~> fa.redeem(g, a => f(a))
  redeem = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "attempt")
    ) @_3
    field: (identifier) @_4 (#eq? @_4 "map")
  )
  arguments: (_) @_5
)
]]),
    handler = function(bufnr, matches)
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]

      if not match_node then
        return {}
      end

      if not evidence.has_capability(bufnr, attempt_id, 'MonadError') then
        return {}
      end

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local left_fn = left.param .. ' => ' .. left.body
      local right_fn = right.param .. ' => ' .. right.body

      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = match_node:range()

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = '.redeem(' .. left_fn .. ', ' .. right_fn .. ')',
          title = 'Cats: replace .attempt.map with .redeem',
        },
      }
    end,
  },
  -- fa.attempt.flatMap { case Right(a) => fb; case Left(e) => fc(e) } ~> fa.redeemWith(fc, a => fb)
  redeem_with = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "attempt")
    ) @_3
    field: (identifier) @_4 (#eq? @_4 "flatMap")
  )
  arguments: (_) @_5
)
]]),
    handler = function(bufnr, matches)
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]

      if not match_node then
        return {}
      end

      if not evidence.has_capability(bufnr, attempt_id, 'MonadError') then
        return {}
      end

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local left_fn = left.param .. ' => ' .. left.body
      local right_fn = right.param .. ' => ' .. right.body

      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = match_node:range()

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = '.redeemWith(' .. left_fn .. ', ' .. right_fn .. ')',
          title = 'Cats: replace .attempt.flatMap with .redeemWith',
        },
      }
    end,
  },
  -- fa.flatMap(a => fb.as(a)) ~> fa <* fb
  -- fa.flatMap(a => fb.map(_ => a)) ~> fa <* fb
  product_l = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "flatMap")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_3
      (_) @_4
    )
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local start = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local body = matches[4][1]
      local finish = matches[5][1]

      if not evidence.has_capability(bufnr, target, 'Apply') then
        return {}
      end

      local param_text = utils.get_node_text(bufnr, param)
      local body_text = utils.get_node_text(bufnr, body)

      -- Check if body is fb.as(a) or fb.map(_ => a)
      local effect_text

      -- Match fb.as(a) where a is the parameter
      local as_match = body_text:match('^(.-)%.as%(' .. vim.pesc(param_text) .. '%)$')
      if as_match then
        effect_text = vim.trim(as_match)
      end

      -- Match fb.map(_ => a) where a is the parameter
      if not effect_text then
        local map_match = body_text:match('^(.-)%.map%(_%s*=>%s*' .. vim.pesc(param_text) .. '%)$')
        if map_match then
          effect_text = vim.trim(map_match)
        end
      end

      if not effect_text then
        return {}
      end

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = ' <* ' .. effect_text,
          title = 'Cats: replace .flatMap(a => fb.as(a)) with fa <* fb',
        },
      }
    end,
  },
}
