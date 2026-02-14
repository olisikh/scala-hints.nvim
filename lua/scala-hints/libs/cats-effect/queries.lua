--- Cats-Effect Treesitter query definitions and handlers
---
--- Each entry has:
---   query   = parsed Treesitter query (TSQuery)
---   handler = function(bufnr, matches) -> results table

local utils = require('scala-hints.utils')
local semantic = require('scala-hints.semantic')
local ts = vim.treesitter

--- Basic CE type detection: checks for IO/Resource type patterns in definition URI
local function is_ce_type(uri_value)
  if not uri_value or type(uri_value) ~= 'string' then
    return false
  end
  local lower = uri_value:lower()
  if lower:find('cats/effect') ~= nil or lower:find('cats%-effect') ~= nil then
    return true
  end
  return string.find(uri_value, 'cats%.effect%.IO%[') ~= nil
    or string.find(uri_value, 'cats%.effect%.Resource%[') ~= nil
    or string.find(uri_value, 'cats%.effect%.kernel%.Resource%[') ~= nil
    or string.find(uri_value, 'cats%.effect%.IO') ~= nil
    or string.find(uri_value, 'cats%.effect%.Resource') ~= nil
    or string.find(uri_value, 'object IO') ~= nil
    or string.find(uri_value, 'object Resource') ~= nil
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
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
        title = 'CE: replace if (' .. condition_text .. ') effect else IO.unit with effect.whenA(' .. replacement_condition .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
        title = 'CE: replace if (' .. condition_text .. ') effect else IO.unit with effect.unlessA(' .. replacement_condition .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
      local start = matches[1][1]
      local target = matches[2][1]
      local param = matches[3][1]
      local effect = matches[4][1]
      local param_value = matches[6][1]
      local finish = matches[7][1]

      local param_text = utils.get_node_text(bufnr, param)
      local value_text = utils.get_node_text(bufnr, param_value)
      if param_text ~= value_text then
        return {}
      end

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local effect_text = utils.get_node_text(bufnr, effect)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'flatTap(' .. param_text .. ' => ' .. effect_text .. ')',
        title = 'CE: replace .flatMap returning its parameter with .flatTap',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
  )
)
]]),
    handler = function(bufnr, matches)
      local opt = matches[1][1]
      local io_target = matches[3][1]
      local err = matches[5][1]
      local finish = matches[7][1]

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
            semantic.type_definition_predicate(bufnr, io_target, is_ce_type, function(is_ce)
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
  )
)
]]),
    handler = function(bufnr, matches)
      local either = matches[1][1]
      local io_target = matches[3][1]
      local finish = matches[6][1]

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
            semantic.type_definition_predicate(bufnr, io_target, is_ce_type, function(is_ce)
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
  from_try = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (call_expression
      function: (identifier) @_1 (#eq? @_1 "Try")
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
  )
)
]]),
    handler = function(bufnr, matches)
      local try_call = matches[3][1]
      local io_target = matches[5][1]
      local finish = matches[8][1]

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
            semantic.type_definition_predicate(bufnr, io_target, is_ce_type, function(is_ce)
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
      local target = matches[4][1]
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

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = match_node:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = replacement,
        title = 'CE: replace .attempt.flatMap with .handleError',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
      local target = matches[4][1]
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

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = match_node:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = method .. '(' .. left_fn .. ', ' .. right_fn .. ')',
        title = 'CE: replace .attempt.map with .' .. method,
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, effect, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, effect, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, fa, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, fa, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, full, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, full, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, effect, is_ce_type, function(is_ce)
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
            semantic.type_definition_predicate(bufnr, effect, is_ce_type, function(is_ce)
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
