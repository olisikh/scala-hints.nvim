--- ZIO Treesitter query definitions and handlers
---
--- Each entry has:
---   query   = parsed Treesitter query (TSQuery)
---   handler = function(bufnr, matches) -> results table
---
--- NOTE: #eq? against ZIO.succeed and ZIO.unit may miss cases where a newline
--- separates `ZIO` from `.unit` (e.g. ZIO\n.unit).

local utils = require('scala-hints.utils')
local semantic = require('scala-hints.semantic')
local ts = vim.treesitter

--- Robust ZIO type detection: checks for ZIO type patterns in definition URI
local function is_zio_type(uri_value)
  if not uri_value or type(uri_value) ~= 'string' then
    return false
  end

  return string.find(uri_value, '/zio/ZIO.scala$') ~= nil
    or string.find(uri_value, '/zio/package%.scala$') ~= nil
    or string.find(uri_value, '/zio/stream/ZStream.scala$') ~= nil
end

--- Robust ZLayer type detection: checks for ZLayer type patterns in definition URI
local function is_zlayer_type(uri_value)
  if not uri_value or type(uri_value) ~= 'string' then
    return false
  end

  return string.find(uri_value, '/zio/ZLayer%.scala$') ~= nil or string.find(uri_value, '/zio/package%.scala') ~= nil
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

local function is_zio_unit_text(text)
  return vim.trim(text) == 'ZIO.unit'
end

return {

  -- ZIO.succeed(()) ~> ZIO.unit
  succeed_unit = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
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
        title = 'ZIO: replace ZIO.succeed(()) with ZIO.unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZIO.fail(ex).orDie ~> ZIO.die(ex)
  zio_die = {
    query = parse_query([[
(   
  (call_expression
    function: (field_expression
      value: (identifier) @_1 (#eq? @_1 "ZIO")
      field: (identifier) @_2 (#eq? @_2 "fail")
    ) @_3
    arguments: (arguments (_) @_4)
  )
  (identifier) @_5 (#eq? @_5 "orDie")
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local exception = matches[4][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local exception_text = utils.get_node_text(bufnr, exception)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.die(' .. exception_text .. ')',
        title = 'ZIO: replace ZIO.fail(' .. exception_text .. ').orDie with ZIO.die(' .. exception_text .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- x.map(_ => ()) ~> x.unit
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
        replacement = 'unit',
        title = 'ZIO: replace .map(_ => ()) with .unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- *> ZIO.unit ~> .unit
  zip_right_unit = {
    query = parse_query([[
(infix_expression
  left: (_) @_1
  operator: (operator_identifier) @_2 (#eq? @_2 "*>")
  right: (field_expression
    value: (identifier) @_3 (#eq? @_3 "ZIO")
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

      local replaced = utils.get_node_text(bufnr, finish)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.unit',
        title = 'ZIO: replace *> ' .. replaced .. ' with .unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- x.as(()) ~> x.unit
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
        replacement = 'unit',
        title = 'ZIO: replace .as(()) with .unit',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- *> ZIO.succeed(value) ~> .as(value)
  zip_right_value = {
    query = parse_query([[
(infix_expression
  left: (_) @_1
  operator: (operator_identifier) @_2 (#eq? @_2 "*>")
  right: (call_expression
    function: (field_expression
      value: (identifier) @_3 (#eq? @_3 "ZIO")
      field: (identifier) @_4 (#eq? @_4 "succeed")
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
        title = 'ZIO: replace *> ZIO.succeed(' .. value_text .. ') with .as(' .. value_text .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- x.zipRight(v) ~> x *> v
  zip_right_operator = {
    diagnostic_severity = 'HINT',
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "zipRight")
  )
  arguments: (arguments (_) @_3) @_4
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
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = ' *> ' .. value_text,
                title = 'ZIO: replace .zipRight(' .. value_text .. ') with *> ' .. value_text,
              })
            end)
          end,
        },
      }
    end,
  },

  -- x.tap(_ => v) ~> x <* v / x.zipLeft(v)
  zip_left_value = {
    diagnostic_severity = 'HINT',
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "tap")
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
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              local base_diagnostic = {
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
              }

              -- Call done() separately for each result option
              done(utils.deep_merge(base_diagnostic, {
                replacement = ' <* ' .. value_text,
                title = 'ZIO: replace .tap(_ => ' .. value_text .. ') with <* ' .. value_text,
              }))
              done(utils.deep_merge(base_diagnostic, {
                replacement = '.zipLeft(' .. value_text .. ')',
                title = 'ZIO: replace .tap(_ => ' .. value_text .. ') with .zipLeft(' .. value_text .. ')',
              }))
            end)
          end,
        },
      }
    end,
  },

  -- x.flatMap(_ => v) ~> x *> v / x.zipRight(v)
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
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              local base_diagnostic = {
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
              }

              -- Call done() separately for each result option
              done(utils.deep_merge(base_diagnostic, {
                replacement = ' *> ' .. value_text,
                title = 'ZIO: replace .flatMap(_ => ' .. value_text .. ') with *> ' .. value_text,
              }))
              done(utils.deep_merge(base_diagnostic, {
                replacement = '.zipRight(' .. value_text .. ')',
                title = 'ZIO: replace .flatMap(_ => ' .. value_text .. ') with .zipRight(' .. value_text .. ')',
              }))
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
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = 'as(' .. value_text .. ')',
                title = 'ZIO: replace .map(_ => ' .. value_text .. ') with .as(' .. value_text .. ')',
              })
            end)
          end,
        },
      }
    end,
  },

  -- x.catchAll(_ => ZIO.unit) ~> x.ignore
  catch_all_unit = {
    query = parse_query([[
(call_expression 
  function: (field_expression
    value: (_) @_1
    field: (_) @_2 (#eq? @_2 "catchAll")
  )
  arguments: (arguments
    (lambda_expression 
      parameters: (wildcard)
      (field_expression
        value: (identifier) @_3 (#eq? @_3 "ZIO")
        field: (identifier) @_4 (#eq? @_4 "unit")
      ) @_5
     )
  ) @_6
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local value = matches[5][1]
      local finish = matches[6][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = 'ignore',
                title = 'ZIO: replace .catchAll(_ => ' .. value_text .. ') with .ignore',
              })
            end)
          end,
        },
      }
    end,
  },

  -- ZIO.collectAll(coll.map(f)) ~> ZIO.foreach(coll)(f)
  zio_foreach = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#any-of? @_2 "collectAll" "collectAllPar")
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
      local start = matches[1][1]
      local foreach_fun = matches[2][1]
      local collection = matches[4][1]
      local value = matches[6][1]
      local finish = matches[7][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local foreach_text = utils.get_node_text(bufnr, foreach_fun)
      local value_text = utils.get_node_text(bufnr, value)
      local collection_text = utils.get_node_text(bufnr, collection)

      local replacement
      if foreach_text == 'collectAll' then
        replacement = 'foreach'
      else
        replacement = 'foreachPar'
      end

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.' .. replacement .. '(' .. collection_text .. ')' .. value_text,
        title = 'ZIO: replace ZIO.' .. foreach_text .. ' with ZIO.' .. replacement,
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZIO.foreachPar(coll)(f) ~> ZIO.foreachParN(n)(coll)(f)
  foreach_par_n = {
    query = parse_query([[
(call_expression
  function: (call_expression
    function: (field_expression
      value: (identifier) @_1 (#eq? @_1 "ZIO")
      field: (identifier) @_2 (#eq? @_2 "foreachPar")
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
        replacement = 'ZIO.foreachParN(n)(' .. collection_text .. ')(' .. fn_text .. ')',
        title = 'ZIO: replace ZIO.foreachPar with ZIO.foreachParN (specify parallelism)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- x.foldCause(_ => (), _ => ()) ~> x.ignore
  fold_cause_ignore = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "foldCause")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard) (unit)
    )
    (lambda_expression parameters: (wildcard) (unit))
  ) @_3
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local finish = matches[3][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'ignore',
        title = 'ZIO: replace .foldCause(_ => (), _ => ()) with .ignore',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- x.mapError(_ => v) ~> x.orElseFail(v)
  or_else_fail = {
    query = parse_query([[
(call_expression 
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "mapError")
  )
  arguments: (arguments
    (lambda_expression
      parameters: [(wildcard) (identifier)]
      (_) @_3
    )
  )
) @_4
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
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = 'orElseFail(' .. value_text .. ')',
                title = 'ZIO: replace .mapError(_ => ' .. value_text .. ') with .orElseFail(' .. value_text .. ')',
              })
            end)
          end,
        },
      }
    end,
  },

  -- x.orElse(ZIO.fail(v)) ~> x.orElseFail(v)
  or_else_fail2 = {
    query = parse_query([[
(call_expression 
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "orElse")
    )
    arguments: (arguments
      (call_expression
        function: (field_expression
          value: (identifier) @_3 (#eq? @_3 "ZIO")
          field: (identifier) @_4 (#eq? @_4 "fail")
        ) @_5
        arguments: (arguments (_) @_6)
      )
    ) @_7
) 
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local value = matches[6][1]
      local finish = matches[7][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end

              local value_text = utils.get_node_text(bufnr, value)
              done({
                diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
                action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
                replacement = 'orElseFail(' .. value_text .. ')',
                title = 'ZIO: replace .orElse(ZIO.fail(' .. value_text .. ')) with .orElseFail(' .. value_text .. ')',
              })
            end)
          end,
        },
      }
    end,
  },

  -- x.flatMapError(_ => ZIO.succeed(v)) ~> x.orElseFail(v)
  or_else_fail3 = {
    query = parse_query([[
(call_expression
    function: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "flatMapError")
    )
    arguments: (arguments
      (lambda_expression
        parameters: (wildcard)
        (call_expression
          function: (field_expression) @_3
          arguments: (arguments (_) @_4)
        )
      )
    ) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local value = matches[4][1]
      local finish = matches[5][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'orElseFail(' .. value_text .. ')',
        title = 'ZIO: replace .flatMapError(_ => ZIO.succeed('
          .. value_text
          .. ')) with .orElseFail('
          .. value_text
          .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZIO[Any, Nothing, A] ~> UIO[A] (and other type aliases)
  zio_type = {
    query = parse_query([[
(
  generic_type (
    (
     (type_identifier) @_1 (#eq? @_1 "ZIO")
    )
    type_arguments: (
      type_arguments 
      (type_identifier) @_2
      (type_identifier) @_3
      (type_identifier) @_4
    ) @finish
  )
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[1][1]
      local finish = matches[5][1]

      local r_value = utils.get_node_text(bufnr, matches[2][1])
      local e_value = utils.get_node_text(bufnr, matches[3][1])
      local a_value = utils.get_node_text(bufnr, matches[4][1])

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      -- stylua: ignore start
      local lookup = {
        { "Any",   "Nothing",   'UIO['.. a_value .. ']' },
        { "Any",   "Throwable", 'Task[' .. a_value .. ']'  },
        { "Any",   e_value,     'IO[' .. e_value .. ', ' .. a_value .. ']'  },
        { r_value, "Nothing",   'URIO['.. r_value ..', ' .. a_value .. ']' },
        { r_value, "Throwable", 'RIO[' .. r_value ..', ' .. a_value .. ']' }
      }
      -- stylua: ignore end

      local results = {}
      for _, m in ipairs(lookup) do
        if r_value == m[1] and e_value == m[2] then
          local replacement = m[3]
          table.insert(results, {
            diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
            action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
            replacement = replacement,
            title = 'ZIO: replace ZIO[' .. r_value .. ', ' .. e_value .. ', ' .. a_value .. '] with ' .. replacement,
          })
        end
      end

      if #results == 0 then
        return {}
      end

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
                for _, item in ipairs(results) do
                  done(item)
                end
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- ZLayer[Any, Nothing, A] ~> ULayer[A] (and other type aliases)
  zlayer_type = {
    query = parse_query([[
(
  generic_type (
    (
     (type_identifier) @start (#eq? @start "ZLayer")
    )
    type_arguments: (
      type_arguments 
      (type_identifier) @R_id 
      (type_identifier) @E_id 
      (type_identifier) @A_id 
    ) @finish
  )
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[1][1]
      local finish = matches[5][1]

      local r_value = utils.get_node_text(bufnr, matches[2][1])
      local e_value = utils.get_node_text(bufnr, matches[3][1])
      local a_value = utils.get_node_text(bufnr, matches[4][1])

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      -- stylua: ignore start
      local lookup = {
        { "Any",   "Nothing",   'ULayer['.. a_value .. ']' },
        { "Any",   "Throwable", 'TaskLayer[' .. a_value .. ']'  },
        { "Any",   e_value,     'Layer[' .. e_value .. ', ' .. a_value .. ']'  },
        { r_value, "Nothing",   'URLayer['.. r_value ..', ' .. a_value .. ']' },
        { r_value, "Throwable", 'RLayer[' .. r_value ..', ' .. a_value .. ']' }
      }
      -- stylua: ignore end

      local results = {}
      for _, m in ipairs(lookup) do
        if r_value == m[1] and e_value == m[2] then
          local replacement = m[3]
          table.insert(results, {
            diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
            action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
            replacement = replacement,
            title = 'ZIO: replace ZLayer[' .. r_value .. ', ' .. e_value .. ', ' .. a_value .. '] with ' .. replacement,
          })
        end
      end

      if #results == 0 then
        return {}
      end

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zlayer_type, function(is_zlayer)
              if is_zlayer then
                for _, item in ipairs(results) do
                  done(item)
                end
              else
                done(nil)
              end
            end)
          end,
        },
      }
    end,
  },

  -- ZIO.succeed(None) ~> ZIO.none
  -- ZIO.succeed(Option.empty[A]) ~> ZIO.none
  zio_none = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
  ) @_3
  arguments: (arguments
    [
      ((identifier) @_4 (#any-of? @_4 "None" "none"))
      ((generic_function
        function: (field_expression
          value: (identifier) @_5 (#eq? @_5 "Option")
          field: (identifier) @_6 (#eq? @_6 "empty")
        ) @_7
        type_arguments: (type_arguments (type_identifier) @_8)
      ) @_4)
    ]
  ) @_9
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local value = matches[4][1]
      local finish = matches[9][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.none',
        title = 'ZIO: replace ZIO.succeed(' .. value_text .. ') with ZIO.none',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZIO.succeed(Some(x)) ~> ZIO.some(x)
  -- ZIO.succeed(Option(x)) ~> ZIO.some(x)
  zio_some = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
  ) @_3
  arguments: (arguments
    [
      (call_expression
        function: (identifier) @_4 (#any-of? @_4 "Some" "Option")
        arguments: (arguments (_) @_5)
      )
      (field_expression
        value: (_) @_6
        field: (identifier) @_7 (#eq? @_7 "some")
      )
    ] @_8
  ) @_9
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local value = matches[5] and matches[5][1]
      local some_value = matches[6] and matches[6][1]
      local expr = matches[8][1]
      local finish = matches[9][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local expr_text = utils.get_node_text(bufnr, expr)
      local value_text = value ~= nil and utils.get_node_text(bufnr, value) or utils.get_node_text(bufnr, some_value)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.some(' .. value_text .. ')',
        title = 'ZIO: replace ZIO.succeed(' .. expr_text .. ') with ZIO.some(' .. value_text .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZIO.succeed(Left(v)) ~> ZIO.left(v)
  -- ZIO.succeed(Right(v)) ~> ZIO.right(v)
  -- ZIO.succeed(v.asLeft) ~> ZIO.left(v)
  -- ZIO.succeed(v.asRight) ~> ZIO.right(v)
  zio_either = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "succeed")
  ) @_3
  arguments: (arguments 
    [
      (call_expression
          function: (identifier) @_4 (#any-of? @_4 "Left" "Right")
          arguments: (arguments (_) @_5)
      )
      (field_expression
        value: (_) @_6
        field: (identifier) @_7 (#any-of? @_7 "asLeft" "asRight")
      )
    ] @_8
  ) @_9
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]

      local either = matches[4] and matches[4][1]
      local cats_either = matches[7] and matches[7][1]

      local value = matches[5] and matches[5][1]
      local cats_value = matches[6] and matches[6][1]

      local expr = matches[8][1]
      local finish = matches[9][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local smartc_text = nil
      local value_text = nil
      if either ~= nil then
        smartc_text = string.lower(utils.get_node_text(bufnr, either))
        value_text = utils.get_node_text(bufnr, value)
      else
        if utils.get_node_text(bufnr, cats_either) == 'asLeft' then
          smartc_text = 'left'
        else
          smartc_text = 'right'
        end
        value_text = utils.get_node_text(bufnr, cats_value)
      end

      local expr_text = utils.get_node_text(bufnr, expr)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.' .. smartc_text .. '(' .. value_text .. ')',
        title = 'ZIO: replace ZIO.succeed(' .. expr_text .. ') with ZIO.' .. smartc_text .. '(' .. value_text .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZIO.sleep(duration) *> effect ~> effect.delay(duration)
  delay = {
    query = parse_query([[
(infix_expression
  left: (call_expression
    function: (field_expression
      value: (identifier) @_1 (#eq? @_1 "ZIO")
      field: (identifier) @_2 (#eq? @_2 "sleep")
    ) @_3
    arguments: (arguments (_) @_4)
  ) @_5
  operator: (operator_identifier) @_6 (#eq? @_6 "*>")
  right: (_) @_7
) @_8
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local duration = matches[4][1]
      local sleep_expr = matches[5][1]
      local effect = matches[7][1]
      local finish = matches[8][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local duration_text = utils.get_node_text(bufnr, duration)

      local item = {
        diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
        action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
        replacement = '.delay(' .. duration_text .. ')',
        title = 'ZIO: replace ZIO.sleep(' .. duration_text .. ') *> effect with effect.delay(' .. duration_text .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- ZLayer.fromEffect(effect) ~> effect.toLayer (deprecated API)
  to_layer = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZLayer")
    field: (identifier) @_2 (#eq? @_2 "fromEffect")
  ) @_3
  arguments: (arguments (_) @_4) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local effect = matches[4][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local effect_text = utils.get_node_text(bufnr, effect)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = '.toLayer',
        title = 'ZIO: replace ZLayer.fromEffect(' .. effect_text .. ') with ' .. effect_text .. '.toLayer',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zlayer_type, function(is_zlayer)
              if is_zlayer then
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

  -- layer.build.use(effect.provide) ~> effect.provideLayer(layer)
  -- layer.build.use(effect.provideLayer) ~> effect.provideLayer(layer)
  provide_layer = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (field_expression
      value: (_) @_1
      field: (identifier) @_2 (#eq? @_2 "build")
    ) @_3
    field: (identifier) @_4 (#eq? @_4 "use")
  ) @_5
  arguments: (arguments
    (field_expression
      value: (_) @_6
      field: (identifier) @_7 (#any-of? @_7 "provide" "provideLayer")
    ) @_8
  )
) @_9
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local layer = matches[1][1]
      local effect = matches[6][1]
      local start = matches[9][1]

      local start_row, start_col, end_row, end_col = start:range()

      local layer_text = utils.get_node_text(bufnr, layer)
      local effect_text = utils.get_node_text(bufnr, effect)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = effect_text .. '.provideLayer(' .. layer_text .. ')',
        title = 'ZIO: replace layer.build.use(effect.provide) with effect.provideLayer(layer)',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zlayer_type, function(is_zlayer)
              if is_zlayer then
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

  -- ZIO.access(identity) ~> ZIO.service[A]
  -- Note: This is informational - suggests using ZIO.service[A]
  zio_service = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "access")
  ) @_3
  arguments: (arguments
    (identifier) @_4 (#eq? @_4 "identity")
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.service',
        title = 'ZIO: consider using ZIO.service[A] instead of ZIO.access(identity) for cleaner service access',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- effect.map(_ => ExitCode.success) ~> effect.exitCode
  exit_code_map = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "map")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard)
      (field_expression
        value: (identifier) @_3 (#eq? @_3 "ExitCode")
        field: (identifier) @_4 (#eq? @_4 "success")
      )
    )
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'exitCode',
        title = 'ZIO: replace .map(_ => ExitCode.success) with .exitCode',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- effect.as(ExitCode.success) ~> effect.exitCode
  exit_code_as = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "as")
  )
  arguments: (arguments
    (field_expression
      value: (identifier) @_3 (#eq? @_3 "ExitCode")
      field: (identifier) @_4 (#eq? @_4 "success")
    )
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'exitCode',
        title = 'ZIO: replace .as(ExitCode.success) with .exitCode',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- effect.fold(_ => ExitCode.failure, _ => ExitCode.success) ~> effect.exitCode
  exit_code_fold = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "fold")
  )
  arguments: (arguments
    (lambda_expression
      parameters: (wildcard)
      (field_expression
        value: (identifier) @_3 (#eq? @_3 "ExitCode")
        field: (identifier) @_4 (#eq? @_4 "failure")
      )
    )
    (lambda_expression
      parameters: (wildcard)
      (field_expression
        value: (identifier) @_5 (#eq? @_5 "ExitCode")
        field: (identifier) @_6 (#eq? @_6 "success")
      )
    )
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local target = matches[2][1]
      local finish = matches[7][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'exitCode',
        title = 'ZIO: replace .fold(_ => ExitCode.failure, _ => ExitCode.success) with .exitCode',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- effect.map(v => { sideEffect(v); v }) ~> effect.tap(v => sideEffect(v))
  -- Detects block-style lambdas where the last expression returns the parameter unchanged.
  tap = {
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
      local replacement = 'tap(' .. param_text .. ' => ' .. body_text .. ')'

      -- First body expression must be a ZIO effect for .tap to be valid
      local first_body_expr = body_block:named_child(0)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = replacement,
        title = 'ZIO: replace .map returning its parameter with .tap',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end
              semantic.type_definition_predicate(bufnr, first_body_expr, is_zio_type, function(body_is_zio)
                if body_is_zio then
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

  -- effect.mapError(e => { logError(e); e }) ~> effect.tapError(e => logError(e))
  -- Detects block-style lambdas where the last expression returns the parameter unchanged.
  tap_error = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (_) @_1
    field: (identifier) @_2 (#eq? @_2 "mapError")
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
    field: (identifier) @_2 (#eq? @_2 "mapError")
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
      local replacement = 'tapError(' .. param_text .. ' => ' .. body_text .. ')'

      -- First body expression must be a ZIO effect for .tapError to be valid
      local first_body_expr = body_block:named_child(0)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = replacement,
        title = 'ZIO: replace .mapError returning its parameter with .tapError',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end
              semantic.type_definition_predicate(bufnr, first_body_expr, is_zio_type, function(body_is_zio)
                if body_is_zio then
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

  -- effect.map(v => { sideEffect(v); v }).mapError(e => { logError(e); e }) ~> effect.tapBoth(e => logError(e), v => sideEffect(v))
  tap_both = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (call_expression
      function: (field_expression
        value: (_) @_1
        field: (identifier) @_2 (#any-of? @_2 "map" "mapError")
      ) @_3
      arguments: (arguments
        (lambda_expression
          parameters: (identifier) @_4
          (block (_) (identifier) @_5 .) @_6
        )
      )
    ) @_7
    field: (identifier) @_8 (#any-of? @_8 "map" "mapError")
  ) @_9
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_10
      (block (_) (identifier) @_11 .) @_12
    )
  )
) @_13

(call_expression
  function: (field_expression
    value: (call_expression
      function: (field_expression
        value: (_) @_1
        field: (identifier) @_2 (#any-of? @_2 "map" "mapError")
      ) @_3
      arguments: (arguments
        (lambda_expression
          parameters: (identifier) @_4
          (block (_) (identifier) @_5 .) @_6
        )
      )
    ) @_7
    field: (identifier) @_8 (#any-of? @_8 "map" "mapError")
  ) @_9
  arguments: (block
    (lambda_expression
      parameters: (identifier) @_10
      (indented_block (_) (identifier) @_11 .) @_12
    )
  )
) @_13

(call_expression
  function: (field_expression
    value: (call_expression
      function: (field_expression
        value: (_) @_1
        field: (identifier) @_2 (#any-of? @_2 "map" "mapError")
      ) @_3
      arguments: (arguments
        (lambda_expression
          parameters: (identifier) @_4
          (indented_block (_) (identifier) @_5 .) @_6
        )
      )
    ) @_7
    field: (identifier) @_8 (#any-of? @_8 "map" "mapError")
  ) @_9
  arguments: (arguments
    (lambda_expression
      parameters: (identifier) @_10
      (block (_) (identifier) @_11 .) @_12
    )
  )
) @_13

(call_expression
  function: (field_expression
    value: (call_expression
      function: (field_expression
        value: (_) @_1
        field: (identifier) @_2 (#any-of? @_2 "map" "mapError")
      ) @_3
      arguments: (arguments
        (lambda_expression
          parameters: (identifier) @_4
          (indented_block (_) (identifier) @_5 .) @_6
        )
      )
    ) @_7
    field: (identifier) @_8 (#any-of? @_8 "map" "mapError")
  ) @_9
  arguments: (block
    (lambda_expression
      parameters: (identifier) @_10
      (indented_block (_) (identifier) @_11 .) @_12
    )
  )
) @_13
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local first_method = matches[2][1]
      local first_param = matches[4][1]
      local first_last = matches[5][1]
      local first_body = matches[6][1]

      local second_method = matches[8][1]
      local second_param = matches[10][1]
      local second_last = matches[11][1]
      local second_body = matches[12][1]

      local start = matches[9][1]
      local finish = matches[13][1]

      local first_method_text = utils.get_node_text(bufnr, first_method)
      local second_method_text = utils.get_node_text(bufnr, second_method)

      local is_valid = (first_method_text == 'map' and second_method_text == 'mapError')
        or (first_method_text == 'mapError' and second_method_text == 'map')
      if not is_valid then
        return {}
      end

      local function build_side(param_node, last_node, body_node)
        local param_text = utils.get_node_text(bufnr, param_node)
        local last_text = utils.get_node_text(bufnr, last_node)
        if param_text ~= last_text then
          return nil
        end

        local child_count = body_node:named_child_count()
        if child_count < 2 then
          return nil
        end

        local body_parts = {}
        for i = 0, child_count - 2 do
          local child = body_node:named_child(i)
          table.insert(body_parts, utils.get_node_text(bufnr, child))
        end

        local body_text = table.concat(body_parts, '; ')
        if body_text == '' then
          return nil
        end

        return { param = param_text, body = body_text }
      end

      local first_side = build_side(first_param, first_last, first_body)
      local second_side = build_side(second_param, second_last, second_body)
      if not (first_side and second_side) then
        return {}
      end

      local err_side
      local ok_side
      if first_method_text == 'mapError' then
        err_side = first_side
        ok_side = second_side
      else
        err_side = second_side
        ok_side = first_side
      end

      -- First body expressions must be ZIO effects for .tapBoth to be valid
      local first_body_expr = first_body:named_child(0)
      local second_body_expr = second_body:named_child(0)

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local replacement = 'tapBoth('
        .. err_side.param
        .. ' => '
        .. err_side.body
        .. ', '
        .. ok_side.param
        .. ' => '
        .. ok_side.body
        .. ')'

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = replacement,
        title = 'ZIO: replace map/mapError side-effects with .tapBoth',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if not is_zio then
                done(nil)
                return
              end
              semantic.type_definition_predicate(bufnr, first_body_expr, is_zio_type, function(body1_is_zio)
                if not body1_is_zio then
                  done(nil)
                  return
                end
                semantic.type_definition_predicate(bufnr, second_body_expr, is_zio_type, function(body2_is_zio)
                  if body2_is_zio then
                    done(item)
                  else
                    done(nil)
                  end
                end)
              end)
            end)
          end,
        },
      }
    end,
  },

  -- ZIO.cond(cond, (), err) ~> ZIO.fail(err).unless(cond)
  zio_cond = {
    query = parse_query([[
(call_expression
  function: (field_expression
    value: (identifier) @_1 (#eq? @_1 "ZIO")
    field: (identifier) @_2 (#eq? @_2 "cond")
  ) @_3
  arguments: (arguments
    (_) @_4
    (unit) @_5
    (_) @_6
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local verify_target = matches[1][1]
      local start = matches[3][1]
      local condition = matches[4][1]
      local error_value = matches[6][1]
      local finish = matches[7][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local condition_text = normalize_condition_text(utils.get_node_text(bufnr, condition))
      local error_text = utils.get_node_text(bufnr, error_value)

      local item = {
        diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
        action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        replacement = 'ZIO.fail(' .. error_text .. ').unless(' .. condition_text .. ')',
        title = 'ZIO: replace ZIO.cond('
          .. condition_text
          .. ', (), '
          .. error_text
          .. ') with ZIO.fail('
          .. error_text
          .. ').unless('
          .. condition_text
          .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- if (condition) effect else ZIO.unit ~> effect.when(condition)
  when = {
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

      local consequence_is_unit = is_zio_unit_text(consequence_text)
      local alternative_is_unit = is_zio_unit_text(alternative_text)

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
        replacement = replacement_effect .. '.when(' .. replacement_condition .. ')',
        title = 'ZIO: replace if ('
          .. condition_text
          .. ') effect else ZIO.unit with effect.when('
          .. replacement_condition
          .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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

  -- if (!condition) effect else ZIO.unit ~> effect.unless(condition)
  -- if (condition) ZIO.unit else effect ~> effect.unless(condition)
  unless = {
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

      local consequence_is_unit = is_zio_unit_text(consequence_text)
      local alternative_is_unit = is_zio_unit_text(alternative_text)

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
        replacement = replacement_effect .. '.unless(' .. replacement_condition .. ')',
        title = 'ZIO: replace if ('
          .. condition_text
          .. ') effect else ZIO.unit with effect.unless('
          .. replacement_condition
          .. ')',
      }

      return {
        ready = {},
        pending = {
          function(done)
            semantic.type_definition_predicate(bufnr, verify_target, is_zio_type, function(is_zio)
              if is_zio then
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
