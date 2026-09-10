--- Monix Treesitter query definitions and handlers
---
--- Patterns for monix.eval.Task and monix.reactive.Observable, mirroring the
--- ZIO and Cats-Effect catalogs: common effect-system smells rewritten with
--- the idiomatic Monix replacement.
---
--- Each entry has:
---   query   = parsed Treesitter query (TSQuery)
---   handler = function(bufnr, matches) -> results table
---
--- NOTE: `.void`, `.as`, `.tapEval`, `.redeem`, `.redeemWith` exist on Task
--- but NOT on Observable, so those handlers verify the receiver against
--- is_monix_task_type specifically.

local utils = require('scala-hints.utils')
local semantic = require('scala-hints.semantic')
local ts = vim.treesitter

--- Monix Task type detection: checks for monix.eval.Task in the definition URI
local function is_monix_task_type(uri_value)
  if not uri_value or type(uri_value) ~= 'string' then
    return false
  end

  return string.find(uri_value, '/monix/eval/Task%.scala$') ~= nil
    or string.find(uri_value, '/monix/eval/Task%$%.scala$') ~= nil
    or string.find(uri_value, '/monix/eval/package%.scala$') ~= nil
end

--- Monix Observable type detection: checks for monix.reactive.Observable in the definition URI
local function is_monix_observable_type(uri_value)
  if not uri_value or type(uri_value) ~= 'string' then
    return false
  end

  return string.find(uri_value, '/monix/reactive/Observable%.scala$') ~= nil
    or string.find(uri_value, '/monix/reactive/Observable%$%.scala$') ~= nil
    or string.find(uri_value, '/monix/reactive/observables/TypedObservable%.scala$') ~= nil
    or string.find(uri_value, '/monix/reactive/package%.scala$') ~= nil
end

--- Either Monix Task or Observable (used where the replacement is shared)
local function is_monix_type(uri_value)
  return is_monix_task_type(uri_value) or is_monix_observable_type(uri_value)
end

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

local function unwrap_single_expression_node(node)
  if node then
    local node_type = node:type()
    if node_type == 'block' or node_type == 'indented_block' then
      if node:named_child_count() == 1 then
        return node:named_child(0)
      end
    end
  end
  return node
end

local function is_task_unit_text(text)
  return vim.trim(text) == 'Task.unit'
end

--- Extract the error argument from a `Task.raiseError(e)` call node.
--- Returns nil if the node is not a Task.raiseError call.
local function get_task_raise_error_arg(bufnr, node)
  local call = unwrap_single_expression_node(node)
  if not call or call:type() ~= 'call_expression' then
    return nil
  end

  local func_node = call:field('function')[1]
  if not func_node or func_node:type() ~= 'field_expression' then
    return nil
  end

  local value_node = func_node:field('value')[1]
  local field_node = func_node:field('field')[1]
  if not value_node or not field_node then
    return nil
  end

  local value_text = utils.get_node_text(bufnr, value_node)
  local field_text = utils.get_node_text(bufnr, field_node)
  if value_text ~= 'Task' or field_text ~= 'raiseError' then
    return nil
  end

  local args_node = call:field('arguments')[1]
  if not args_node then
    return nil
  end

  local err_node = args_node:named_child(0)
  if not err_node then
    return nil
  end

  return utils.get_node_text(bufnr, err_node)
end

--- Return a copy of the item with the redeem replacement/title rewritten to
--- use the given method ('redeem' or 'redeemWith').
local function with_redeem_method(item, method)
  local copy = vim.deepcopy(item)
  copy.replacement = copy.replacement:gsub('^%.redeem', '.' .. method)
  copy.title = copy.title:gsub('%.redeem$', '.' .. method)
  return copy
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
      -- The body expression is the last named child of the case clause;
      -- keep the node so handlers can type-check it via Metals.
      local body_node = case_node:named_child(case_node:named_child_count() - 1)
      case_map[ctor] = { param = param, body = vim.trim(body), body_node = body_node }
    end
  end
  return case_map
end

return {
  ---------------------------------------------------------------------------
  -- Task: lifting constants
  ---------------------------------------------------------------------------

  -- Task.now(()) / Task.pure(()) ~> Task.unit
  now_unit = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Task")
    field: (identifier) @_2 (#any-of? @_2 "now" "pure")
  ) @_3
  arguments: (arguments (unit)) @_4
)
]]),
    handler = function(bufnr, matches)
      local method_node = matches[2][1]
      local task_node = matches[1][1]
      local finish = matches[4][1]

      local start_row, start_col, _, _ = task_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.unit',
        title = 'Monix: replace Task.' .. utils.get_node_text(bufnr, method_node) .. '(()) with Task.unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, task_node, is_monix_task_type, function(is_monix)
              if is_monix then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Task.now(None) / Task.pure(None) ~> Task.none
  task_none = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Task")
    field: (identifier) @_2 (#any-of? @_2 "now" "pure")
  ) @_3
  arguments: (arguments (identifier) @_4 (#eq? @_4 "None")) @_5
)
]]),
    handler = function(bufnr, matches)
      local method_node = matches[2][1]
      local task_node = matches[1][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = task_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.none',
        title = 'Monix: replace Task.' .. utils.get_node_text(bufnr, method_node) .. '(None) with Task.none',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, task_node, is_monix_task_type, function(is_monix)
              if is_monix then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Task.now(Some(v)) / Task.pure(Some(v)) ~> Task.some(v)
  task_some = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Task")
    field: (identifier) @_2 (#any-of? @_2 "now" "pure")
  ) @_3
  arguments: (arguments
    (call_expression
      function: (identifier) @_4 (#eq? @_4 "Some")
      arguments: (arguments (_) @_5)
    ) @_6
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local method_node = matches[2][1]
      local task_node = matches[1][1]
      local value = matches[5][1]
      local finish = matches[7][1]

      local start_row, start_col, _, _ = task_node:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.some(' .. value_text .. ')',
        title = 'Monix: replace Task.' .. utils.get_node_text(bufnr, method_node) .. '(Some(v)) with Task.some(v)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, task_node, is_monix_task_type, function(is_monix)
              if is_monix then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Task.now(Left(v)) / Task.now(Right(v)) ~> Task.left(v) / Task.right(v)
  task_either = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Task")
    field: (identifier) @_2 (#any-of? @_2 "now" "pure")
  ) @_3
  arguments: (arguments
    (call_expression
      function: (identifier) @_4 (#any-of? @_4 "Left" "Right")
      arguments: (arguments (_) @_5)
    ) @_6
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local method_node = matches[2][1]
      local task_node = matches[1][1]
      local ctor = matches[4][1]
      local value = matches[5][1]
      local finish = matches[7][1]

      local start_row, start_col, _, _ = task_node:range()
      local _, _, end_row, end_col = finish:range()

      local ctor_text = utils.get_node_text(bufnr, ctor)
      local value_text = utils.get_node_text(bufnr, value)

      local method = 'right'
      if ctor_text == 'Left' then
        method = 'left'
      end

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.' .. method .. '(' .. value_text .. ')',
        title = 'Monix: replace Task.'
          .. utils.get_node_text(bufnr, method_node)
          .. '('
          .. ctor_text
          .. '(v)) with Task.'
          .. method
          .. '(v)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, task_node, is_monix_task_type, function(is_monix)
              if is_monix then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  ---------------------------------------------------------------------------
  -- Task: monadic combinators
  ---------------------------------------------------------------------------

  -- x.map(_ => ()) ~> x.void
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
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local finish = matches[3][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'void',
        title = 'Monix: replace .map(_ => ()) with .void',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- x.map(_ => v) ~> x.as(v)
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
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if not is_task then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = 'as(' .. value_text .. ')',
                title = 'Monix: replace .map(_ => ' .. value_text .. ') with .as(' .. value_text .. ')',
              })
            end)
          end,
        },
      }
    end,
  },

  -- x.map(v => { taskEffect(v); v }) ~> x.tapEval(v => taskEffect(v))
  -- Detects block-style lambdas where the last expression returns the parameter unchanged.
  tap_eval = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "map")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_3
      (block (_) (identifier) @_4 .) @_5
    )
  ) @_6
)

(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "map")
  )
  arguments: (block
    (lambda_expression
      parameters: (identifier) @_3
      (indented_block (_) (identifier) @_4 .) @_5
    )
  ) @_6
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local last_expr = matches[4][1]
      local body_block = matches[5][1]
      local finish = matches[6][1]

      -- Verify last expression equals the parameter (handler-side check)
      local param_text = utils.get_node_text(bufnr, param)
      local last_text = utils.get_node_text(bufnr, last_expr)
      if param_text ~= last_text then
        return {}
      end

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      -- Build body without the trailing parameter return
      local body_parts = {}
      local child_count = body_block:named_child_count()
      for i = 0, child_count - 2 do
        local child = body_block:named_child(i)
        table.insert(body_parts, utils.get_node_text(bufnr, child))
      end
      local body_text = table.concat(body_parts, '; ')

      -- The lambda body passed to .tapEval evaluates to its LAST
      -- expression, so that expression (not the first) must be a Monix
      -- Task for the replacement to typecheck.
      local last_body_expr = body_block:named_child(child_count - 2)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'tapEval(' .. param_text .. ' => ' .. body_text .. ')',
        title = 'Monix: replace .map returning its parameter with .tapEval',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if not is_task then
                done(nil)
                return
              end
              semantic.type_definition_predicate(bufnr, last_body_expr, is_monix_task_type, function(body_is_task)
                if body_is_task then
                  done(item)
                else
                  done(nil)
                end
              end)
            end)
          end,
        },
      }
    end,
  },

  -- x.flatMap(a => effect.as(a)) ~> x.tapEval(a => effect)
  flat_tap_eval = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "flatMap")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_3
      (call_expression
        function: (field_expression
          value: (_) @_4
          field: (identifier) @_5 (#eq? @_5 "as")
        )
        arguments: (arguments
          (identifier) @_6
        )
      ) @_7
    )
  ) @_8
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local effect = matches[4][1]
      local param_value = matches[6][1]
      local finish = matches[8][1]

      local param_text = utils.get_node_text(bufnr, param)
      local value_text = utils.get_node_text(bufnr, param_value)
      if param_text ~= value_text then
        return {}
      end

      local effect_text = utils.get_node_text(bufnr, effect)

      -- Start range at ".flatMap" (back up 1 for the dot)
      local dstart_row, dstart_col, _, _ = target:range()
      local start_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.tapEval(' .. param_text .. ' => ' .. effect_text .. ')',
        title = 'Monix: replace .flatMap returning its parameter with .tapEval',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- x.attempt.map { case Right(a) => f(a); case Left(e) => g(e) } ~> x.redeem(g, f)
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
) @_6
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]
      local finish = matches[6][1]

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local left_fn = left.param .. ' => ' .. left.body
      local right_fn = right.param .. ' => ' .. right.body

      -- Start range at ".attempt" to remove it (the dot before attempt)
      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = finish:range()

      local redeem_item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = '.redeem(' .. left_fn .. ', ' .. right_fn .. ')',
        title = 'Monix: replace .attempt.map with .redeem',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if not is_task then
                done(nil)
                return
              end
              -- Decide redeem vs redeemWith by the actual type of the case
              -- bodies: if either body evaluates to a Monix Task, the
              -- functions return Task[...] and redeemWith is required.
              semantic.type_definition_predicate(bufnr, left.body_node, is_monix_task_type, function(left_is_task)
                if left_is_task then
                  done(with_redeem_method(redeem_item, 'redeemWith'))
                  return
                end
                semantic.type_definition_predicate(bufnr, right.body_node, is_monix_task_type, function(right_is_task)
                  if right_is_task then
                    done(with_redeem_method(redeem_item, 'redeemWith'))
                  else
                    done(redeem_item)
                  end
                end)
              end)
            end)
          end,
        },
      }
    end,
  },

  -- x.attempt.flatMap { case Right(a) => fa(a); case Left(e) => fe(e) } ~> x.redeemWith(fe, fa)
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
) @_6
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]
      local finish = matches[6][1]

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local left_fn = left.param .. ' => ' .. left.body
      local right_fn = right.param .. ' => ' .. right.body

      -- Start range at ".attempt" to remove it (the dot before attempt)
      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = '.redeemWith(' .. left_fn .. ', ' .. right_fn .. ')',
        title = 'Monix: replace .attempt.flatMap with .redeemWith',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  ---------------------------------------------------------------------------
  -- Task: conversions
  ---------------------------------------------------------------------------

  -- either.fold(Task.raiseError, Task.now) ~> Task.fromEither(either)
  from_either = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "fold")
  )
  arguments: (arguments
    (field_expression
      value: (identifier) @_3 (#eq? @_3 "Task")
      field: (identifier) @_4 (#eq? @_4 "raiseError")
    )
    (field_expression
      value: (identifier) @_5 (#eq? @_5 "Task")
      field: (identifier) @_6 (#any-of? @_6 "now" "pure" "apply")
    )
  ) @_7
) @_8
]]),
    handler = function(bufnr, matches)
      local either = matches[1][1]
      local task_target = matches[3][1]
      local lift_method = matches[6][1]
      local finish = matches[8][1]

      -- Skip if the value is a Try(...) call — that's handled by from_try
      if either:type() == 'call_expression' then
        local func = either:field('function')[1]
        if func then
          local func_text = utils.get_node_text(bufnr, func)
          if func_text == 'Try' or (func_text and func_text:match('%.Try$')) then
            return {}
          end
        end
      end

      local either_text = utils.get_node_text(bufnr, either)

      local start_row, start_col, _, _ = either:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.fromEither(' .. either_text .. ')',
        title = 'Monix: replace .fold(Task.raiseError, Task.'
          .. utils.get_node_text(bufnr, lift_method)
          .. ') with Task.fromEither',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, task_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Try(x).fold(Task.raiseError, Task.now) ~> Task.fromTry(Try(x))
  -- Also matches qualified scala.util.Try(x)
  from_try = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (call_expression
      function: (_) @_1
      arguments: (arguments (_) @_2)
    ) @_3
    field: (identifier) @_4 (#eq? @_4 "fold")
  )
  arguments: (arguments
    (field_expression
      value: (identifier) @_5 (#eq? @_5 "Task")
      field: (identifier) @_6 (#eq? @_6 "raiseError")
    )
    (field_expression
      value: (identifier) @_7 (#eq? @_7 "Task")
      field: (identifier) @_8 (#any-of? @_8 "now" "pure" "apply")
    )
  ) @_9
) @_10
]]),
    handler = function(bufnr, matches)
      local try_func = matches[1][1]
      local try_call = matches[3][1]
      local task_target = matches[5][1]
      local lift_method = matches[8][1]
      local finish = matches[10][1]

      -- Verify the function is Try (bare or qualified like scala.util.Try)
      local func_text = utils.get_node_text(bufnr, try_func)
      if func_text ~= 'Try' and not (func_text and func_text:match('%.Try$')) then
        return {}
      end

      local try_text = utils.get_node_text(bufnr, try_call)

      local start_row, start_col, _, _ = try_call:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.fromTry(' .. try_text .. ')',
        title = 'Monix: replace .fold(Task.raiseError, Task.'
          .. utils.get_node_text(bufnr, lift_method)
          .. ') with Task.fromTry',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, task_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  ---------------------------------------------------------------------------
  -- Task: collections
  ---------------------------------------------------------------------------

  -- Task.sequence(coll.map(f)) ~> Task.traverse(coll)(f)
  sequence_traverse = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Task")
    field: (identifier) @_2 (#eq? @_2 "sequence")
  ) @_3
  arguments: (_
    (call_expression
      function: (field_expression
        value: (_) @_4
        field: (_) @_5 (#eq? @_5 "map")
      )
      arguments: (_ (_)) @_6
    )
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local collection = matches[4][1]
      local fn_arg = matches[6][1]
      local finish = matches[7][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local collection_text = utils.get_node_text(bufnr, collection)
      local fn_arg_node = fn_arg:named_child(0) or fn_arg
      local fn_text = utils.get_node_text(bufnr, fn_arg_node)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.traverse(' .. collection_text .. ')(' .. fn_text .. ')',
        title = 'Monix: replace Task.sequence(coll.map(f)) with Task.traverse(coll)(f)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Task.parTraverse(coll)(f) ~> Task.parTraverseN(n)(coll)(f)
  -- parTraverse is unbounded; parTraverseN limits parallelism.
  par_traverse_n = {
    query = parse_query([[
(call_expression
  function: (call_expression
    function: (field_expression
      value: (identifier) @_1 (#eq? @_1 "Task")
      field: (identifier) @_2 (#eq? @_2 "parTraverse")
    ) @_3
    arguments: (arguments (_) @_4) @_5
  ) @_6
  arguments: (arguments (_) @_7) @_8
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local collection = matches[4][1]
      local fn_arg = matches[7][1]
      local finish = matches[8][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local collection_text = utils.get_node_text(bufnr, collection)
      local fn_text = utils.get_node_text(bufnr, fn_arg)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.parTraverseN(n)(' .. collection_text .. ')(' .. fn_text .. ')',
        title = 'Monix: replace Task.parTraverse with Task.parTraverseN (specify parallelism)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Task.parSequence(coll) ~> Task.parSequenceN(n)(coll)
  par_sequence_n = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Task")
    field: (identifier) @_2 (#eq? @_2 "parSequence")
  ) @_3
  arguments: (arguments (_) @_4) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local collection = matches[4][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local collection_text = utils.get_node_text(bufnr, collection)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.parSequenceN(n)(' .. collection_text .. ')',
        title = 'Monix: replace Task.parSequence with Task.parSequenceN (specify parallelism)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  ---------------------------------------------------------------------------
  -- Task: timing and control structures
  ---------------------------------------------------------------------------

  -- Task.sleep(d) *> effect ~> effect.delayExecution(d)
  delay_execution = {
    query = parse_query([[
(infix_expression
  left: (call_expression
    function: (field_expression
      value: (identifier) @_1 (#eq? @_1 "Task")
      field: (identifier) @_2 (#eq? @_2 "sleep")
    )
    arguments: (arguments (_) @_3)
  ) @_4
  operator: (operator_identifier) @_5 (#eq? @_5 "*>")
  right: (_) @_6
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[4][1]
      local duration = matches[3][1]
      local effect = matches[6][1]

      local duration_text = utils.get_node_text(bufnr, duration)
      local effect_text = utils.get_node_text(bufnr, effect)

      local start_row, start_col, _, _ = verify_target:range()
      local _, _, end_row, end_col = effect:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.delayExecution(' .. duration_text .. ')',
        title = 'Monix: replace Task.sleep(d) *> effect with effect.delayExecution(d)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- Task.sleep(d).flatMap(_ => effect) ~> effect.delayExecution(d)
  delay_execution_flatmap = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (call_expression
      function: (field_expression
        value: (identifier) @_1 (#eq? @_1 "Task")
        field: (identifier) @_2 (#eq? @_2 "sleep")
      )
      arguments: (arguments (_) @_3)
    ) @_4
    field: (identifier) @_5 (#eq? @_5 "flatMap")
  ) @_6
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard) (_) @_7
    )
  ) @_8
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[4][1]
      local duration = matches[3][1]
      local effect = matches[7][1]
      local finish = matches[8][1]

      local duration_text = utils.get_node_text(bufnr, duration)
      local effect_text = utils.get_node_text(bufnr, effect)

      local start_row, start_col, _, _ = verify_target:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.delayExecution(' .. duration_text .. ')',
        title = 'Monix: replace Task.sleep(d).flatMap(_ => effect) with effect.delayExecution(d)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- if (cond) effect else Task.unit ~> Task.when(cond)(effect)
  -- if (!cond) Task.unit else effect ~> Task.when(cond)(effect)
  task_when = {
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

      local consequence_is_unit = is_task_unit_text(consequence_text)
      local alternative_is_unit = is_task_unit_text(alternative_text)

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

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.when(' .. replacement_condition .. ')(' .. replacement_effect .. ')',
        title = 'Monix: replace if/else with Task.when(cond)(effect)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            local verify_node = unwrap_single_expression_node(verify_target)
            semantic.type_definition_predicate(bufnr, verify_node, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- if (!cond) effect else Task.unit ~> Task.unless(cond)(effect)
  -- if (cond) Task.unit else effect ~> Task.unless(cond)(effect)
  task_unless = {
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

      local consequence_is_unit = is_task_unit_text(consequence_text)
      local alternative_is_unit = is_task_unit_text(alternative_text)

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

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.unless(' .. replacement_condition .. ')(' .. replacement_effect .. ')',
        title = 'Monix: replace if/else with Task.unless(cond)(effect)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            local verify_node = unwrap_single_expression_node(verify_target)
            semantic.type_definition_predicate(bufnr, verify_node, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- if (cond) Task.raiseError(e) else Task.unit ~> Task.raiseWhen(cond)(e)
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

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local negated_inner = strip_negation(condition_text)
      if negated_inner then
        return {}
      end

      local alternative_text = unwrap_single_expression_block(bufnr, alternative)
      if not is_task_unit_text(alternative_text) then
        return {}
      end

      local err_text = get_task_raise_error_arg(bufnr, consequence)
      if not err_text then
        return {}
      end

      local start_row, start_col, end_row, end_col = node:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.raiseWhen(' .. condition_text .. ')(' .. err_text .. ')',
        title = 'Monix: replace if (cond) Task.raiseError(e) else Task.unit with Task.raiseWhen(cond)(e)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            -- Unwrap single-expression blocks so typeDefinition resolves
            -- against the Task.raiseError call, not the block node.
            local verify_node = unwrap_single_expression_node(consequence)
            semantic.type_definition_predicate(bufnr, verify_node, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- if (!cond) Task.raiseError(e) else Task.unit ~> Task.raiseUnless(cond)(e)
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

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local negated_inner = strip_negation(condition_text)
      if not negated_inner then
        return {}
      end

      local alternative_text = unwrap_single_expression_block(bufnr, alternative)
      if not is_task_unit_text(alternative_text) then
        return {}
      end

      local err_text = get_task_raise_error_arg(bufnr, consequence)
      if not err_text then
        return {}
      end

      local start_row, start_col, end_row, end_col = node:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Task.raiseUnless(' .. negated_inner .. ')(' .. err_text .. ')',
        title = 'Monix: replace if (!cond) Task.raiseError(e) else Task.unit with Task.raiseUnless(cond)(e)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            -- Unwrap single-expression blocks so typeDefinition resolves
            -- against the Task.raiseError call, not the block node.
            local verify_node = unwrap_single_expression_node(consequence)
            semantic.type_definition_predicate(bufnr, verify_node, is_monix_task_type, function(is_task)
              if is_task then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  ---------------------------------------------------------------------------
  -- Observable
  ---------------------------------------------------------------------------

  -- Observable.now(()) / Observable.pure(()) ~> Observable.unit
  obs_now_unit = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "Observable")
    field: (identifier) @_2 (#any-of? @_2 "now" "pure")
  ) @_3
  arguments: (arguments (unit)) @_4
)
]]),
    handler = function(bufnr, matches)
      local obs_node = matches[1][1]
      local finish = matches[4][1]

      local start_row, start_col, _, _ = obs_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'Observable.unit',
        title = 'Monix: replace Observable.now(()) with Observable.unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, obs_node, is_monix_observable_type, function(is_obs)
              if is_obs then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- obs.mapEval(a => Task.now(v)) ~> obs.map(a => v)
  -- Task.now inside mapEval builds a needless Task per element.
  obs_map_eval_now = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "mapEval")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (_) @_3
      (call_expression
        function: (field_expression
          value: (identifier) @_4 (#eq? @_4 "Task")
          field: (identifier) @_5 (#eq? @_5 "now")
        )
        arguments: (arguments (_) @_6)
      ) @_7
    )
  ) @_8
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local task_node = matches[4][1]
      local value = matches[6][1]
      local finish = matches[8][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local param_text = utils.get_node_text(bufnr, param)
      local value_text = utils.get_node_text(bufnr, value)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'map(' .. param_text .. ' => ' .. value_text .. ')',
        title = 'Monix: replace .mapEval(a => Task.now(v)) with .map(a => v)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_observable_type, function(is_obs)
              if not is_obs then
                done(nil)
                return
              end
              semantic.type_definition_predicate(bufnr, task_node, is_monix_task_type, function(is_task)
                if is_task then
                  done(item)
                else
                  done(nil)
                end
              end)
            end)
          end,
        },
      }
    end,
  },

  -- obs.switchIfEmpty(Observable.empty) ~> obs
  -- Falling back to the empty observable is a no-op.
  obs_switch_if_empty = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "switchIfEmpty")
  )
  arguments: (arguments
    (field_expression
      value: (identifier) @_3 (#eq? @_3 "Observable")
      field: (identifier) @_4 (#eq? @_4 "empty")
    )
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local finish = matches[5][1]

      -- Replace the whole call expression (receiver + .switchIfEmpty(...))
      -- with the receiver, so the range must start at the receiver, not at
      -- the switchIfEmpty identifier (otherwise the leading dot survives).
      local start_row, start_col, _, _ = verify_target:range()
      local _, _, end_row, end_col = finish:range()

      local receiver_text = utils.get_node_text(bufnr, verify_target)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = receiver_text,
        title = 'Monix: remove no-op .switchIfEmpty(Observable.empty)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_monix_observable_type, function(is_obs)
              if is_obs then
                done(item)
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },
}