--- Cats-Effect Treesitter query definitions and handlers
---
--- Each entry has:
---   query   = parsed Treesitter query (TSQuery)
---   handler = function(bufnr, matches) -> results table

local utils = require('scala-hints.utils')
local semantic = require('scala-hints.semantic')
local ts = vim.treesitter

--- Basic CE type detection: checks for IO/Resource type patterns in definition URI
local function is_cats_io_type(uri_value)
  if not uri_value or type(uri_value) ~= 'string' then
    return false
  end

  return string.find(uri_value, '/cats/effect/IO%.scala$') ~= nil
    or string.find(uri_value, '/cats/effect/Resource%.scala$') ~= nil
    or string.find(uri_value, '/cats/effect/kernel/Resource%.scala$') ~= nil
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

local function is_io_unit_text(text)
  return vim.trim(text) == 'IO.unit'
end

local function get_io_raise_error_arg(bufnr, node)
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
  if value_text ~= 'IO' or field_text ~= 'raiseError' then
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

return {
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
        title = 'CE: replace .map(_ => ()) with .void',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- x.map(_ => value) ~> x.as(value)
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
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if not is_ce then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = 'as(' .. value_text .. ')',
                title = 'CE: replace .map(_ => ' .. value_text .. ') with .as(' .. value_text .. ')',
              })
            end)
          end,
        },
      }
    end,
  },

  -- x.flatMap(_ => v) ~> x >> v
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
      local verify_target = matches[1][1]
      local start = matches[1][1]
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if not is_ce then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
                replacement = ' >> ' .. value_text,
                title = 'CE: replace .flatMap(_ => ' .. value_text .. ') with >> ' .. value_text,
              })
            end)
          end,
        },
      }
    end,
  },

  -- if (condition) effect else IO.unit ~> effect.whenA(condition)
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

      local consequence_is_unit = is_io_unit_text(consequence_text)
      local alternative_is_unit = is_io_unit_text(alternative_text)

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
        replacement = replacement_effect .. '.whenA(' .. replacement_condition .. ')',
        title = 'CE: replace if ('
          .. condition_text
          .. ') effect else IO.unit with effect.whenA('
          .. replacement_condition
          .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- if (!condition) effect else IO.unit ~> effect.unlessA(condition)
  -- if (condition) IO.unit else effect ~> effect.unlessA(condition)
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

      local consequence_is_unit = is_io_unit_text(consequence_text)
      local alternative_is_unit = is_io_unit_text(alternative_text)

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
        replacement = replacement_effect .. '.unlessA(' .. replacement_condition .. ')',
        title = 'CE: replace if ('
          .. condition_text
          .. ') effect else IO.unit with effect.unlessA('
          .. replacement_condition
          .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- x.flatMap(a => effect.as(a)) ~> x.flatTap(a => effect)
  flat_tap = {
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
        replacement = '.flatTap(' .. param_text .. ' => ' .. effect_text .. ')',
        title = 'CE: replace .flatMap returning its parameter with .flatTap',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- if (cond) IO.unit else IO.raiseError(err) ~> IO.raiseUnless(cond)(err)
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

      local consequence_is_unit = is_io_unit_text(consequence_text)
      local alternative_is_unit = is_io_unit_text(alternative_text)

      local error_text
      local verify_target
      local replacement_condition

      if consequence_is_unit and not alternative_is_unit and not negated_inner then
        -- if (cond) IO.unit else IO.raiseError(err)
        error_text = get_io_raise_error_arg(bufnr, alternative)
        verify_target = unwrap_single_expression_node(alternative)
        replacement_condition = condition_text
      elseif alternative_is_unit and not consequence_is_unit and negated_inner then
        -- if (!cond) IO.raiseError(err) else IO.unit
        error_text = get_io_raise_error_arg(bufnr, consequence)
        verify_target = unwrap_single_expression_node(consequence)
        replacement_condition = negated_inner
      else
        return {}
      end

      if not error_text then
        return {}
      end

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.raiseUnless(' .. replacement_condition .. ')(' .. error_text .. ')',
        title = 'CE: replace if (...) IO.unit/raiseError with IO.raiseUnless',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- if (cond) IO.raiseError(err) else IO.unit ~> IO.raiseWhen(cond)(err)
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

      local consequence_is_unit = is_io_unit_text(consequence_text)
      local alternative_is_unit = is_io_unit_text(alternative_text)

      local error_text
      local verify_target
      local replacement_condition

      if alternative_is_unit and not consequence_is_unit and not negated_inner then
        -- if (cond) IO.raiseError(err) else IO.unit
        error_text = get_io_raise_error_arg(bufnr, consequence)
        verify_target = unwrap_single_expression_node(consequence)
        replacement_condition = condition_text
      elseif consequence_is_unit and not alternative_is_unit and negated_inner then
        -- if (!cond) IO.unit else IO.raiseError(err)
        error_text = get_io_raise_error_arg(bufnr, alternative)
        verify_target = unwrap_single_expression_node(alternative)
        replacement_condition = negated_inner
      else
        return {}
      end

      if not error_text then
        return {}
      end

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.raiseWhen(' .. replacement_condition .. ')(' .. error_text .. ')',
        title = 'CE: replace if (...) raiseError/IO.unit with IO.raiseWhen',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- opt.fold(IO.raiseError(err))(IO.pure) ~> IO.fromOption(opt)(err)
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
          value: (identifier) @_3 (#eq? @_3 "IO")
          field: (identifier) @_4 (#eq? @_4 "raiseError")
        )
        arguments: (arguments
          (_) @_5
        )
      )
    )
  )
  arguments: (arguments
    (field_expression
      value: (identifier) @_6 (#eq? @_6 "IO")
      field: (identifier) @_7 (#eq? @_7 "pure")
    )
  ) @_8
) @_9
]]),
    handler = function(bufnr, matches)
      local opt = matches[1][1]
      local io_target = matches[3][1]
      local err = matches[5][1]
      local finish = matches[9][1]

      local opt_text = utils.get_node_text(bufnr, opt)
      local err_text = utils.get_node_text(bufnr, err)

      local start_row, start_col, _, _ = opt:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.fromOption(' .. opt_text .. ')(' .. err_text .. ')',
        title = 'CE: replace .fold(IO.raiseError(err))(IO.pure) with IO.fromOption',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- either.fold(IO.raiseError, IO.pure) ~> IO.fromEither(either)
  from_either = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "fold")
  )
  arguments: (arguments
    (field_expression
      value: (identifier) @_3 (#eq? @_3 "IO")
      field: (identifier) @_4 (#eq? @_4 "raiseError")
    )
    (field_expression
      value: (identifier) @_5 (#eq? @_5 "IO")
      field: (identifier) @_6 (#eq? @_6 "pure")
    )
  ) @_7
) @_8
]]),
    handler = function(bufnr, matches)
      local either = matches[1][1]
      local io_target = matches[3][1]
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
        replacement = 'IO.fromEither(' .. either_text .. ')',
        title = 'CE: replace .fold(IO.raiseError, IO.pure) with IO.fromEither',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- Try(x).fold(IO.raiseError, IO.pure) ~> IO.fromTry(Try(x))
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
      value: (identifier) @_5 (#eq? @_5 "IO")
      field: (identifier) @_6 (#eq? @_6 "raiseError")
    )
    (field_expression
      value: (identifier) @_7 (#eq? @_7 "IO")
      field: (identifier) @_8 (#eq? @_8 "pure")
    )
  ) @_9
) @_10
]]),
    handler = function(bufnr, matches)
      local try_func = matches[1][1]
      local try_call = matches[3][1]
      local io_target = matches[5][1]
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
        replacement = 'IO.fromTry(' .. try_text .. ')',
        title = 'CE: replace .fold(IO.raiseError, IO.pure) with IO.fromTry',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- fa.attempt.flatMap { case Right(a) => IO.pure(a); case Left(e) => IO.pure(default) }
  --   ~> fa.handleError(_ => default) or fa.handleErrorWith(e => IO.pure(default(e)))
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
      local verify_target = matches[1][1]
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local right_pure = right.body:match('IO%.pure%((.+)%)')
      if not right_pure or vim.trim(right_pure) ~= right.param then
        return {}
      end

      local left_pure = left.body:match('IO%.pure%((.+)%)')
      if not left_pure then
        return {}
      end

      local replacement
      if left.param ~= '_' and contains_identifier(left_pure, left.param) then
        replacement = 'handleErrorWith(' .. left.param .. ' => IO.pure(' .. left_pure .. '))'
      else
        replacement = 'handleError(_ => ' .. left_pure .. ')'
      end

      -- Start range at ".attempt" to remove it (the dot before attempt)
      local dstart_row, dstart_col, _, _ = attempt_id:range()
      -- Back up one character to include the dot before "attempt"
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = match_node:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = '.' .. replacement,
        title = 'CE: replace .attempt.flatMap with .handleError',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- fa.attempt.map { case Right(a) => f(a); case Left(e) => g(e) }
  --   ~> fa.redeem(g, f) or fa.redeemWith(g, f)
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
      local verify_target = matches[1][1]
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local left_fn = left.param .. ' => ' .. left.body
      local right_fn = right.param .. ' => ' .. right.body

      local method = 'redeem'
      if string.find(left.body, 'IO%.') or string.find(right.body, 'IO%.') then
        method = 'redeemWith'
      end

      -- Start range at ".attempt" to remove it (the dot before attempt)
      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = match_node:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = '.' .. method .. '(' .. left_fn .. ', ' .. right_fn .. ')',
        title = 'CE: replace .attempt.map with .' .. method,
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- Temporal[IO].sleep(d) *> effect ~> effect.delayBy(d)
  delay_by = {
    query = parse_query([[
(infix_expression
  left: (call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "sleep")
    )
    arguments: (arguments (_) @_3)
  ) @_4
  operator: (operator_identifier) @_5 (#eq? @_5 "*>")
  right: (_) @_6
)
]]),
    handler = function(bufnr, matches)
      local left_call = matches[4][1]
      local duration = matches[3][1]
      local effect = matches[6][1]

      local duration_text = utils.get_node_text(bufnr, duration)
      local effect_text = utils.get_node_text(bufnr, effect)

      local start_row, start_col, _, _ = left_call:range()
      local _, _, end_row, end_col = effect:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.delayBy(' .. duration_text .. ')',
        title = 'CE: replace sleep *> effect with effect.delayBy',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, effect, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- IO.race(fa, Temporal[IO].sleep(d)).flatMap { ... } ~> fa.timeout(d)
  timeout = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (call_expression
      function: (field_expression
        value: (identifier) @_1 (#eq? @_1 "IO")
        field: (identifier) @_2 (#eq? @_2 "race")
      )
      arguments: (arguments
        (_) @_3
        (call_expression
          function: (field_expression
            value: (_) @_4
            field: (identifier) @_5 (#eq? @_5 "sleep")
          )
          arguments: (arguments (_) @_6)
        )
      )
    ) @_7
    field: (identifier) @_8 (#eq? @_8 "flatMap")
  )
  arguments: (_) @_9
)
]]),
    handler = function(bufnr, matches)
      local effect = matches[3][1]
      local duration = matches[6][1]
      local race_call = matches[7][1]
      local match_node = matches[9][1]

      local case_map = extract_case_map(bufnr, match_node)
      local right = case_map.Right
      local left = case_map.Left
      if not (right and left) then
        return {}
      end

      local right_err = right.body:match('IO%.raiseError%((.+)%)')
      if not right_err then
        return {}
      end

      local left_pure = left.body:match('IO%.pure%((.+)%)')
      if not left_pure then
        return {}
      end
      if left.param ~= '_' and vim.trim(left_pure) ~= left.param then
        return {}
      end

      local duration_text = utils.get_node_text(bufnr, duration)
      local effect_text = utils.get_node_text(bufnr, effect)

      local start_row, start_col, _, _ = race_call:range()
      local _, _, end_row, end_col = match_node:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.timeout(' .. duration_text .. ')',
        title = 'CE: replace IO.race sleep pattern with .timeout',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, effect, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- fa.flatMap(a => fb.map(b => (a, b))) ~> (fa, fb).tupled
  tupled = {
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
          field: (identifier) @_5 (#eq? @_5 "map")
        )
        arguments: (arguments
          (lambda_expression
            parameters: (identifier) @_6
            (tuple_expression
              (identifier) @_7
              (identifier) @_8
            )
          )
        )
      )
    )
  ) @_9
)
]]),
    handler = function(bufnr, matches)
      local fa = matches[1][1]
      local a_param = matches[3][1]
      local fb = matches[4][1]
      local b_param = matches[6][1]
      local tuple_a = matches[7][1]
      local tuple_b = matches[8][1]
      local finish = matches[9][1]

      if utils.get_node_text(bufnr, a_param) ~= utils.get_node_text(bufnr, tuple_a) then
        return {}
      end
      if utils.get_node_text(bufnr, b_param) ~= utils.get_node_text(bufnr, tuple_b) then
        return {}
      end

      local fa_text = utils.get_node_text(bufnr, fa)
      local fb_text = utils.get_node_text(bufnr, fb)

      local start_row, start_col, _, _ = fa:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '(' .. fa_text .. ', ' .. fb_text .. ').tupled',
        title = 'CE: replace flatMap/map tuple with .tupled',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, fa, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- fa.flatMap(a => fb.map(b => (a, b))).parTupled ~> (fa, fb).parTupled
  par_tupled = {
    query = parse_query([[
(field_expression
  value: (call_expression
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
            field: (identifier) @_5 (#eq? @_5 "map")
          )
          arguments: (arguments
            (lambda_expression
              parameters: (identifier) @_6
              (tuple_expression
                (identifier) @_7
                (identifier) @_8
              )
            )
          )
        )
      )
    )
  ) @_9
  field: (identifier) @_10 (#eq? @_10 "parTupled")
) @_11
]]),
    handler = function(bufnr, matches)
      local fa = matches[1][1]
      local a_param = matches[3][1]
      local fb = matches[4][1]
      local b_param = matches[6][1]
      local tuple_a = matches[7][1]
      local tuple_b = matches[8][1]
      local finish = matches[11][1]

      if utils.get_node_text(bufnr, a_param) ~= utils.get_node_text(bufnr, tuple_a) then
        return {}
      end
      if utils.get_node_text(bufnr, b_param) ~= utils.get_node_text(bufnr, tuple_b) then
        return {}
      end

      local fa_text = utils.get_node_text(bufnr, fa)
      local fb_text = utils.get_node_text(bufnr, fb)

      local start_row, start_col, _, _ = fa:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '(' .. fa_text .. ', ' .. fb_text .. ').parTupled',
        title = 'CE: replace flatMap/map tuple with .parTupled',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, fa, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- list.map(f).parSequence ~> list.parTraverse(f)
  par_sequence = {
    query = parse_query([[
(field_expression
  value: (call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "map")
    )
    arguments: (arguments (_) @_3)
  ) @_4
  field: (identifier) @_5 (#eq? @_5 "parSequence")
) @_6
]]),
    handler = function(bufnr, matches)
      local list = matches[1][1]
      local func = matches[3][1]
      local full = matches[6][1]

      local list_text = utils.get_node_text(bufnr, list)
      local func_text = utils.get_node_text(bufnr, func)

      local start_row, start_col, _, _ = list:range()
      local _, _, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = list_text .. '.parTraverse(' .. func_text .. ')',
        title = 'CE: replace .map(f).parSequence with .parTraverse(f)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, full, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- list.map(f).parSequence_ ~> list.parTraverse_(f)
  par_sequence_ = {
    query = parse_query([[
(field_expression
  value: (call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "map")
    )
    arguments: (arguments (_) @_3)
  ) @_4
  field: (identifier) @_5 (#eq? @_5 "parSequence_")
) @_6
]]),
    handler = function(bufnr, matches)
      local list = matches[1][1]
      local func = matches[3][1]
      local full = matches[6][1]

      local list_text = utils.get_node_text(bufnr, list)
      local func_text = utils.get_node_text(bufnr, func)

      local start_row, start_col, _, _ = list:range()
      local _, _, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = list_text .. '.parTraverse_(' .. func_text .. ')',
        title = 'CE: replace .map(f).parSequence_ with .parTraverse_(f)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, full, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- (1 to n).toList.traverse(_ => fa) ~> fa.replicateA_(n)
  replicate_a_ = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "toList")
    )
    field: (identifier) @_3 (#eq? @_3 "traverse")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard)
      (_) @_4
    )
  )
) @_5
]]),
    handler = function(bufnr, matches)
      local range = matches[1][1]
      local effect = matches[4][1]
      local finish = matches[5][1]

      local range_text = utils.get_node_text(bufnr, range)
      local count_text = range_text:match('^%s*%(?1%s+to%s+(.+)%s*%)?$')
      if not count_text then
        return {}
      end
      count_text = vim.trim(count_text):gsub('%)%s*$', '')

      local effect_text = utils.get_node_text(bufnr, effect)

      local start_row, start_col, _, _ = effect:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.replicateA_(' .. count_text .. ')',
        title = 'CE: replace traverse range with replicateA_',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, effect, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- def loop = fa.flatMap(_ => loop) ~> fa.foreverM
  forever_m = {
    query = parse_query([[
(function_definition
  (identifier) @_1
  (call_expression
    function: (field_expression
      value: (_) @_2
      field: (identifier) @_3 (#eq? @_3 "flatMap")
    )
    arguments: (arguments
      (lambda_expression
        parameters: (wildcard)
        (identifier) @_4
      )
    )
  ) @_5
) @_6

(val_definition
  (identifier) @_1
  (call_expression
    function: (field_expression
      value: (_) @_2
      field: (identifier) @_3 (#eq? @_3 "flatMap")
    )
    arguments: (arguments
      (lambda_expression
        parameters: (wildcard)
        (identifier) @_4
      )
    )
  ) @_5
) @_6
]]),
    handler = function(bufnr, matches)
      local name = matches[1][1]
      local effect = matches[2][1]
      local loop_ref = matches[4][1]
      local finish = matches[6][1]

      local name_text = utils.get_node_text(bufnr, name)
      local loop_text = utils.get_node_text(bufnr, loop_ref)
      if name_text ~= loop_text then
        return {}
      end

      local effect_text = utils.get_node_text(bufnr, effect)

      local start_row, start_col, _, _ = effect:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.foreverM',
        title = 'CE: replace recursive flatMap with .foreverM',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, effect, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- IO.pure(()) ~> IO.unit
  pure_unit = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1 (#eq? @_1 "IO")
    field: (identifier) @_2 (#eq? @_2 "pure")
  )
  arguments: (arguments (unit)) @_3
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
        replacement = 'unit',
        title = 'CE: replace IO.pure(()) with IO.unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- x.as(()) ~> x.void
  as_unit = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "as")
  )
  arguments: (arguments (unit)) @_3
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
        title = 'CE: replace .as(()) with .void',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- effect *> IO.unit ~> effect.void
  zip_right_unit = {
    query = parse_query([[
(infix_expression
  left: (_) @_1
  operator: (operator_identifier) @_2 (#eq? @_2 "*>")
  right: (field_expression
    value: (identifier) @_3 (#eq? @_3 "IO")
    field: (identifier) @_4 (#eq? @_4 "unit")
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[1][1]
      local finish = matches[5][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.void',
        title = 'CE: replace *> IO.unit with .void',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- effect *> IO.pure(value) ~> effect.as(value)
  zip_right_value = {
    query = parse_query([[
(infix_expression
  left: (_) @_1
  operator: (operator_identifier) @_2 (#eq? @_2 "*>")
  right: (call_expression
    function: (field_expression
      value: (identifier) @_3 (#eq? @_3 "IO")
      field: (identifier) @_4 (#eq? @_4 "pure")
    ) @_5
    arguments: (arguments (_) @_6 (#not-eq? @_6 "()"))
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[1][1]
      local target = matches[5][1]
      local value = matches[6][1]
      local finish = matches[7][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.as(' .. value_text .. ')',
        title = 'CE: replace *> IO.pure(' .. value_text .. ') with .as(' .. value_text .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- pred.flatMap(b => if (b) fa else fb) ~> pred.ifM(fa, fb)
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
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local condition = matches[4][1]
      local consequence = matches[5][1]
      local alternative = matches[6][1]
      local finish = matches[7][1]

      -- The condition must simply reference the lambda parameter
      local param_text = utils.get_node_text(bufnr, param)
      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      if condition_text ~= param_text then
        return {}
      end

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local consequence_text = unwrap_single_expression_block(bufnr, consequence)
      local alternative_text = unwrap_single_expression_block(bufnr, alternative)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'ifM(' .. consequence_text .. ', ' .. alternative_text .. ')',
        title = 'CE: replace .flatMap(b => if (b) ...) with .ifM',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- coll.map(f).sequence ~> coll.traverse(f)
  traverse = {
    query = parse_query([[
(field_expression
  value: (call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "map")
    )
    arguments: (arguments (_) @_3)
  ) @_4
  field: (identifier) @_5 (#eq? @_5 "sequence")
) @_6
]]),
    handler = function(bufnr, matches)
      local coll = matches[1][1]
      local func = matches[3][1]
      local full = matches[6][1]

      local coll_text = utils.get_node_text(bufnr, coll)
      local func_text = utils.get_node_text(bufnr, func)

      local start_row, start_col, _, _ = coll:range()
      local _, _, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = coll_text .. '.traverse(' .. func_text .. ')',
        title = 'CE: replace .map(f).sequence with .traverse(f)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, full, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- coll.map(f).sequence_ ~> coll.traverse_(f)
  traverse_ = {
    query = parse_query([[
(field_expression
  value: (call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "map")
    )
    arguments: (arguments (_) @_3)
  ) @_4
  field: (identifier) @_5 (#eq? @_5 "sequence_")
) @_6
]]),
    handler = function(bufnr, matches)
      local coll = matches[1][1]
      local func = matches[3][1]
      local full = matches[6][1]

      local coll_text = utils.get_node_text(bufnr, coll)
      local func_text = utils.get_node_text(bufnr, func)

      local start_row, start_col, _, _ = coll:range()
      local _, _, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = coll_text .. '.traverse_(' .. func_text .. ')',
        title = 'CE: replace .map(f).sequence_ with .traverse_(f)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, full, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- opt match { case Some(a) => f(a); case None => IO.unit } ~> opt.traverse_(f)
  option_traverse = {
    query = parse_query([[
(match_expression
  value: (_) @_1
  body: (case_block
    (case_clause
      pattern: (case_class_pattern
        type: (type_identifier) @_2 (#eq? @_2 "Some")
        pattern: (identifier) @_3
      )
      body: (_) @_4
    )
    (case_clause
      pattern: (identifier) @_5 (#eq? @_5 "None")
      body: (_) @_6
    )
  )
) @_7
]]),
    handler = function(bufnr, matches)
      local opt = matches[1][1]
      local param = matches[3][1]
      local some_body = matches[4][1]
      local none_body = matches[6][1]
      local full = matches[7][1]

      local none_text = unwrap_single_expression_block(bufnr, none_body)
      if not is_io_unit_text(none_text) then
        return {}
      end

      local param_text = utils.get_node_text(bufnr, param)
      local some_text = unwrap_single_expression_block(bufnr, some_body)

      local opt_text = utils.get_node_text(bufnr, opt)

      local start_row, start_col, _, _ = opt:range()
      local _, _, end_row, end_col = full:range()

      -- Determine if the Some body is a simple function call with the param
      -- e.g., f(a) where a is the parameter → opt.traverse_(f)
      -- Otherwise use lambda form → opt.traverse_(a => body)
      local func_text
      if some_body:type() == 'call_expression' then
        local func_node = some_body:field('function')[1]
        local args_node = some_body:field('arguments')[1]
        if func_node and args_node and args_node:named_child_count() == 1 then
          local arg = args_node:named_child(0)
          if utils.get_node_text(bufnr, arg) == param_text then
            func_text = utils.get_node_text(bufnr, func_node)
          end
        end
      end

      if not func_text then
        func_text = param_text .. ' => ' .. some_text
      end

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = opt_text .. '.traverse_(' .. func_text .. ')',
        title = 'CE: replace Option match with .traverse_',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, some_body, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- fa.attempt.flatMap { case Left(e: T) => recover(e); case Left(e) => IO.raiseError(e); case Right(a) => IO.pure(a) }
  -- ~> fa.recoverWith { case e: T => recover(e) }
  recover_with = {
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
      local verify_target = matches[1][1]
      local attempt_id = matches[2][1]
      local match_node = matches[5][1]

      local cases = collect_case_clauses(match_node, {})
      if #cases ~= 3 then
        return {}
      end

      -- Find typed Left (e.g. Left(e: MyEx)), plain Left, and Right cases
      local typed_left, plain_left, right_case
      for _, case_node in ipairs(cases) do
        local pattern_node = case_node:field('pattern')[1]
        if not pattern_node or pattern_node:type() ~= 'case_class_pattern' then
          return {}
        end

        local type_node = pattern_node:field('type')[1]
        local pat_node = pattern_node:field('pattern')[1]
        if not type_node or not pat_node then
          return {}
        end

        local type_text = utils.get_node_text(bufnr, type_node)

        if type_text == 'Left' and pat_node:type() == 'typed_pattern' then
          typed_left = case_node
        elseif type_text == 'Left' and pat_node:type() == 'identifier' then
          plain_left = case_node
        elseif type_text == 'Right' then
          right_case = case_node
        end
      end

      if not (typed_left and plain_left and right_case) then
        return {}
      end

      -- Verify Right(a) => IO.pure(a)
      local right_pat = right_case:field('pattern')[1]:field('pattern')[1]
      local right_param = utils.get_node_text(bufnr, right_pat)
      local right_body = right_case:field('body')[1]
      local right_body_text = unwrap_single_expression_block(bufnr, right_body)
      local right_pure_arg = right_body_text:match('IO%.pure%((.+)%)')
      if not right_pure_arg or vim.trim(right_pure_arg) ~= right_param then
        return {}
      end

      -- Verify Left(e) => IO.raiseError(e)
      local plain_left_pat = plain_left:field('pattern')[1]:field('pattern')[1]
      local plain_left_param = utils.get_node_text(bufnr, plain_left_pat)
      local plain_left_body = plain_left:field('body')[1]
      local plain_left_body_text = unwrap_single_expression_block(bufnr, plain_left_body)
      local raise_arg = plain_left_body_text:match('IO%.raiseError%((.+)%)')
      if not raise_arg or vim.trim(raise_arg) ~= plain_left_param then
        return {}
      end

      -- Extract typed Left: Left(e: T) => body
      local typed_pat = typed_left:field('pattern')[1]:field('pattern')[1] -- typed_pattern
      local typed_param_node = typed_pat:field('pattern')[1]
      local typed_type_node = typed_pat:field('type')[1]
      local typed_param = utils.get_node_text(bufnr, typed_param_node)
      local typed_type = utils.get_node_text(bufnr, typed_type_node)
      local typed_left_body = typed_left:field('body')[1]
      local typed_left_body_text = unwrap_single_expression_block(bufnr, typed_left_body)

      local replacement = '.recoverWith { case '
        .. typed_param
        .. ': '
        .. typed_type
        .. ' => '
        .. typed_left_body_text
        .. ' }'

      -- Range from .attempt to end
      local dstart_row, dstart_col, _, _ = attempt_id:range()
      dstart_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = match_node:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = replacement,
        title = 'CE: replace .attempt.flatMap with .recoverWith',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- for { fA <- fa.start; fB <- fb.start; a <- fA.joinWithNever; b <- fB.joinWithNever } yield (a, b)
  -- ~> (fa, fb).parTupled
  par_tupled_fibers = {
    query = parse_query([[
(for_expression
  enumerators: (enumerators
    (enumerator
      (identifier) @_1
      (field_expression
        value: (_) @_2
        field: (identifier) @_3 (#eq? @_3 "start")
      )
    )
    (enumerator
      (identifier) @_4
      (field_expression
        value: (_) @_5
        field: (identifier) @_6 (#eq? @_6 "start")
      )
    )
    (enumerator
      (identifier) @_7
      (field_expression
        value: (identifier) @_8
        field: (identifier) @_9 (#eq? @_9 "joinWithNever")
      )
    )
    (enumerator
      (identifier) @_10
      (field_expression
        value: (identifier) @_11
        field: (identifier) @_12 (#eq? @_12 "joinWithNever")
      )
    )
  )
  body: (tuple_expression
    (identifier) @_13
    (identifier) @_14
  )
) @_15
]]),
    handler = function(bufnr, matches)
      local fiber_a = matches[1][1]
      local fa = matches[2][1]
      local fiber_b = matches[4][1]
      local fb = matches[5][1]
      local join_a_target = matches[8][1]
      local result_a = matches[7][1]
      local join_b_target = matches[11][1]
      local result_b = matches[10][1]
      local yield_a = matches[13][1]
      local yield_b = matches[14][1]
      local full = matches[15][1]

      -- Verify fiber names match join targets
      if utils.get_node_text(bufnr, fiber_a) ~= utils.get_node_text(bufnr, join_a_target) then
        return {}
      end
      if utils.get_node_text(bufnr, fiber_b) ~= utils.get_node_text(bufnr, join_b_target) then
        return {}
      end
      -- Verify yield params match join result names
      if utils.get_node_text(bufnr, result_a) ~= utils.get_node_text(bufnr, yield_a) then
        return {}
      end
      if utils.get_node_text(bufnr, result_b) ~= utils.get_node_text(bufnr, yield_b) then
        return {}
      end

      local fa_text = utils.get_node_text(bufnr, fa)
      local fb_text = utils.get_node_text(bufnr, fb)
      local start_row, start_col, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '(' .. fa_text .. ', ' .. fb_text .. ').parTupled',
        title = 'CE: replace fiber start/joinWithNever with .parTupled',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, fa, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- opt match { case Some(x) => IO.pure(x); case None => IO.raiseError(err) }
  -- ~> IO.fromOption(opt)(err)
  from_option_match = {
    query = parse_query([[
(match_expression
  value: (_) @_1
  body: (case_block
    (case_clause
      pattern: (case_class_pattern
        type: (type_identifier) @_2 (#eq? @_2 "Some")
        pattern: (identifier) @_3
      )
      body: (_) @_4
    )
    (case_clause
      pattern: (identifier) @_5 (#eq? @_5 "None")
      body: (_) @_6
    )
  )
) @_7
]]),
    handler = function(bufnr, matches)
      local opt = matches[1][1]
      local param = matches[3][1]
      local some_body = matches[4][1]
      local none_body = matches[6][1]
      local full = matches[7][1]

      -- Some body must be IO.pure(x) where x is the param
      local some_text = unwrap_single_expression_block(bufnr, some_body)
      local param_text = utils.get_node_text(bufnr, param)
      local pure_arg = some_text:match('IO%.pure%((.+)%)')
      if not pure_arg or vim.trim(pure_arg) ~= param_text then
        return {}
      end

      -- None body must be IO.raiseError(err)
      local none_text = unwrap_single_expression_block(bufnr, none_body)
      local err_arg = none_text:match('IO%.raiseError%((.+)%)')
      if not err_arg then
        return {}
      end

      local opt_text = utils.get_node_text(bufnr, opt)
      local start_row, start_col, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.fromOption(' .. opt_text .. ')(' .. vim.trim(err_arg) .. ')',
        title = 'CE: replace Option match with IO.fromOption',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, some_body, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- either match { case Right(y) => IO.pure(y); case Left(e) => IO.raiseError(e) }
  -- ~> IO.fromEither(either)
  from_either_match = {
    query = parse_query([[
(match_expression
  value: (_) @_1
  body: (case_block
    (case_clause
      pattern: (case_class_pattern
        type: (type_identifier) @_2 (#eq? @_2 "Right")
        pattern: (identifier) @_3
      )
      body: (_) @_4
    )
    (case_clause
      pattern: (case_class_pattern
        type: (type_identifier) @_5 (#eq? @_5 "Left")
        pattern: (identifier) @_6
      )
      body: (_) @_7
    )
  )
) @_8
]]),
    handler = function(bufnr, matches)
      local either = matches[1][1]
      local right_param = matches[3][1]
      local right_body = matches[4][1]
      local left_param = matches[6][1]
      local left_body = matches[7][1]
      local full = matches[8][1]

      -- Right body must be IO.pure(y) where y is the param
      local right_text = unwrap_single_expression_block(bufnr, right_body)
      local right_param_text = utils.get_node_text(bufnr, right_param)
      local pure_arg = right_text:match('IO%.pure%((.+)%)')
      if not pure_arg or vim.trim(pure_arg) ~= right_param_text then
        return {}
      end

      -- Left body must be IO.raiseError(e) where e is the param
      local left_text = unwrap_single_expression_block(bufnr, left_body)
      local left_param_text = utils.get_node_text(bufnr, left_param)
      local raise_arg = left_text:match('IO%.raiseError%((.+)%)')
      if not raise_arg or vim.trim(raise_arg) ~= left_param_text then
        return {}
      end

      local either_text = utils.get_node_text(bufnr, either)
      local start_row, start_col, end_row, end_col = full:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.fromEither(' .. either_text .. ')',
        title = 'CE: replace Either match with IO.fromEither',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, right_body, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- x.handleErrorWith(e => IO.raiseError(wrap(e)))
  -- ~> x.adaptError { case e => wrap(e) }
  adapt_error = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "handleErrorWith")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_3
      (call_expression
        function: (field_expression
          value: (identifier) @_4 (#eq? @_4 "IO")
          field: (identifier) @_5 (#eq? @_5 "raiseError")
        )
        arguments: (arguments (_) @_6)
      )
    )
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local wrap_expr = matches[6][1]
      local finish = matches[7][1]

      local param_text = utils.get_node_text(bufnr, param)
      local wrap_text = utils.get_node_text(bufnr, wrap_expr)

      -- Start at ".handleErrorWith" (back up 1 for the dot)
      local dstart_row, dstart_col, _, _ = target:range()
      local start_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.adaptError { case ' .. param_text .. ' => ' .. wrap_text .. ' }',
        title = 'CE: replace .handleErrorWith(IO.raiseError) with .adaptError',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- acquire.flatMap { a => use(a).guarantee(release(a)) }
  -- ~> acquire.bracket(a => use(a))(a => release(a))
  bracket = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "flatMap")
  )
  arguments: (block
    (lambda_expression
      parameters: (identifier) @_3
      (call_expression
        function: (field_expression
          value: (_) @_4
          field: (identifier) @_5 (#eq? @_5 "guarantee")
        )
        arguments: (arguments (_) @_6)
      )
    )
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local use_expr = matches[4][1]
      local release_expr = matches[6][1]
      local finish = matches[7][1]

      local param_text = utils.get_node_text(bufnr, param)
      local use_text = utils.get_node_text(bufnr, use_expr)
      local release_text = utils.get_node_text(bufnr, release_expr)

      -- Build use function: if use is a simple call like use(a), extract function name
      local use_fn
      if use_expr:type() == 'call_expression' then
        local func_node = use_expr:field('function')[1]
        local args_node = use_expr:field('arguments')[1]
        if func_node and func_node:type() == 'identifier' and args_node and args_node:named_child_count() == 1 then
          local arg = args_node:named_child(0)
          if utils.get_node_text(bufnr, arg) == param_text then
            use_fn = utils.get_node_text(bufnr, func_node)
          end
        end
      end
      if not use_fn then
        use_fn = param_text .. ' => ' .. use_text
      end

      -- Build release function: same logic
      local release_fn
      if release_expr:type() == 'call_expression' then
        local func_node = release_expr:field('function')[1]
        local args_node = release_expr:field('arguments')[1]
        if func_node and func_node:type() == 'identifier' and args_node and args_node:named_child_count() == 1 then
          local arg = args_node:named_child(0)
          if utils.get_node_text(bufnr, arg) == param_text then
            release_fn = utils.get_node_text(bufnr, func_node)
          end
        end
      end
      if not release_fn then
        release_fn = param_text .. ' => ' .. release_text
      end

      -- Start at ".flatMap" (back up 1 for the dot)
      local dstart_row, dstart_col, _, _ = target:range()
      local start_col = math.max(0, dstart_col - 1)
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.bracket(' .. use_fn .. ')(' .. release_fn .. ')',
        title = 'CE: replace .flatMap { .guarantee } with .bracket',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- for { a <- fa; b <- fb; ... } yield Constructor(a, b, ...)
  -- ~> (fa, fb, ...).mapN(Constructor.apply)
  -- for { a <- fa; b <- fb; ... } yield (a, b, ...)
  -- ~> (fa, fb, ...).tupled
  map_n = {
    query = parse_query([[
(for_expression
  enumerators: (enumerators) @_1
  body: (_) @_2
) @_3
]]),
    handler = function(bufnr, matches)
      local enums_node = matches[1][1]
      local body = matches[2][1]
      local full = matches[3][1]

      -- Collect enumerators: each must be simple param <- effect
      local params = {}
      local effects = {}
      local effect_nodes = {}
      for child in enums_node:iter_children() do
        if child:type() == 'enumerator' then
          local named_count = child:named_child_count()
          if named_count ~= 2 then
            return {}
          end
          local param_node = child:named_child(0)
          local effect_node = child:named_child(1)
          if param_node:type() ~= 'identifier' then
            return {}
          end
          table.insert(params, utils.get_node_text(bufnr, param_node))
          table.insert(effects, utils.get_node_text(bufnr, effect_node))
          table.insert(effect_nodes, effect_node)
        end
      end

      if #params < 2 then
        return {}
      end

      -- Check body type: constructor call or tuple
      local replacement
      local actual_body = unwrap_single_expression_node(body)

      if actual_body:type() == 'tuple_expression' then
        -- Verify tuple contains exactly the params in order
        local tuple_count = actual_body:named_child_count()
        if tuple_count ~= #params then
          return {}
        end
        for i = 0, tuple_count - 1 do
          local elem = actual_body:named_child(i)
          if elem:type() ~= 'identifier' or utils.get_node_text(bufnr, elem) ~= params[i + 1] then
            return {}
          end
        end
        replacement = '(' .. table.concat(effects, ', ') .. ').tupled'
      elseif actual_body:type() == 'call_expression' then
        local func_node = actual_body:field('function')[1]
        local args_node = actual_body:field('arguments')[1]
        if not func_node or not args_node then
          return {}
        end
        -- Arguments must match params exactly in order
        local arg_count = args_node:named_child_count()
        if arg_count ~= #params then
          return {}
        end
        for i = 0, arg_count - 1 do
          local arg = args_node:named_child(i)
          if arg:type() ~= 'identifier' or utils.get_node_text(bufnr, arg) ~= params[i + 1] then
            return {}
          end
        end
        local func_text = utils.get_node_text(bufnr, func_node)
        replacement = '(' .. table.concat(effects, ', ') .. ').mapN(' .. func_text .. '.apply)'
      else
        return {}
      end

      local start_row, start_col, end_row, end_col = full:range()
      local verify_target = effect_nodes[1]

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = replacement,
        title = 'CE: replace for-comprehension with .mapN',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- IO(println(x)) ~> IO.println(x)
  println = {
    query = parse_query([[
(call_expression
  function: (identifier) @_io (#eq? @_io "IO")
  arguments: (arguments
    (call_expression
      function: (identifier) @_println (#eq? @_println "println")
      arguments: (arguments) @_args
    ) @_inner
  )
) @_finish
]]),
    handler = function(bufnr, matches)
      local io_node = matches[1][1]
      local args_node = matches[3][1]
      local finish = matches[4][1]

      local args_text = utils.get_node_text(bufnr, args_node)
      local start_row, start_col, _, _ = io_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.println' .. args_text,
        title = 'CE: replace IO(println(...)) with IO.println(...)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_node, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- IO.apply(println(x)) ~> IO.println(x)
  println_apply = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_io (#eq? @_io "IO")
    field: (identifier) @_apply (#eq? @_apply "apply")
  )
  arguments: (arguments
    (call_expression
      function: (identifier) @_println (#eq? @_println "println")
      arguments: (arguments) @_args
    ) @_inner
  )
) @_finish
]]),
    handler = function(bufnr, matches)
      local io_node = matches[1][1]
      local args_node = matches[4][1]
      local finish = matches[5][1]

      local args_text = utils.get_node_text(bufnr, args_node)
      local start_row, start_col, _, _ = io_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'IO.println' .. args_text,
        title = 'CE: replace IO.apply(println(...)) with IO.println(...)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_node, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- IO(print(x)) ~> IO.print(x)
  print = {
    query = parse_query([[
(call_expression
  function: (identifier) @_io (#eq? @_io "IO")
  arguments: (arguments
    (call_expression
      function: (identifier) @_print (#eq? @_print "print")
      arguments: (arguments) @_args
    ) @_inner
  )
) @_finish
]]),
    handler = function(bufnr, matches)
      local io_node = matches[1][1]
      local args_node = matches[3][1]
      local finish = matches[4][1]

      local args_text = utils.get_node_text(bufnr, args_node)
      local start_row, start_col, _, _ = io_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        diagnostic_severity = 'INFO',
        replacement = 'IO.print' .. args_text,
        title = 'CE: replace IO(print(...)) with IO.print(...)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_node, is_cats_io_type, function(is_ce)
              if is_ce then
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

  -- IO.apply(print(x)) ~> IO.print(x)
  print_apply = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_io (#eq? @_io "IO")
    field: (identifier) @_apply (#eq? @_apply "apply")
  )
  arguments: (arguments
    (call_expression
      function: (identifier) @_print (#eq? @_print "print")
      arguments: (arguments) @_args
    ) @_inner
  )
) @_finish
]]),
    handler = function(bufnr, matches)
      local io_node = matches[1][1]
      local args_node = matches[4][1]
      local finish = matches[5][1]

      local args_text = utils.get_node_text(bufnr, args_node)
      local start_row, start_col, _, _ = io_node:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        diagnostic_severity = 'INFO',
        replacement = 'IO.print' .. args_text,
        title = 'CE: replace IO.apply(print(...)) with IO.print(...)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, io_node, is_cats_io_type, function(is_ce)
              if is_ce then
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
