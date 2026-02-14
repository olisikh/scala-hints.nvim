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

local zio_predicate = function(value)
  return string.find(value, 'ZIO') ~= nil
end

local function parse_query(query)
  return ts.query.parse('scala', query)
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
            semantic.hover_predicate(bufnr, target, zio_predicate, function(is_zio)
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
  fail_exception_or_die = {
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
      local start = matches[3][1]
      local exception = matches[4][1]
      local finish = matches[5][1]

      local start_row, start_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local exception_text = utils.get_node_text(bufnr, exception)

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = 'ZIO.die(' .. exception_text .. ')',
          title = 'ZIO: replace ZIO.fail(' .. exception_text .. ').orDie with ZIO.die(' .. exception_text .. ')',
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
    (lambda_expression parameters: (wildcard) (unit))
  ) @_3
)
]]),
    handler = function(bufnr, matches)
      local target = matches[2][1]
      local finish = matches[3][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        return {
          {
            diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
            action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
            replacement = 'unit',
            title = 'ZIO: replace .map(_ => ()) with .unit',
          },
        }
      else
        return {}
      end
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
      local start = matches[1][1]
      local finish = matches[5][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, end_row, end_col = finish:range()

      local replaced = utils.get_node_text(bufnr, finish)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = '.unit',
          title = 'ZIO: replace *> ' .. replaced .. ' with .unit',
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
      local target = matches[2][1]
      local finish = matches[3][1]

      local start_row, start_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        {
          diagnostic = { row = start_row, start_col = start_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = 'unit',
          title = 'ZIO: replace .as(()) with .unit',
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
      local start = matches[1][1]
      local target = matches[5][1]
      local value = matches[6][1]
      local finish = matches[7][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          replacement = '.as(' .. value_text .. ')',
          title = 'ZIO: replace *> ZIO.succeed(' .. value_text .. ') with .as(' .. value_text .. ')',
        },
      }
    end,
  },

  -- x.tap(_ => v) ~> x <* v / x.zipLeft(v)
  zip_left_value = {
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
      local start = matches[1][1]
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        local value_text = utils.get_node_text(bufnr, value)

        local base_diagnostic = {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        }

        return {
          utils.deep_merge(base_diagnostic, {
            replacement = ' <* ' .. value_text,
            title = 'ZIO: replace .tap(_ => ' .. value_text .. ') with <* ' .. value_text,
          }),
          utils.deep_merge(base_diagnostic, {
            replacement = '.zipLeft(' .. value_text .. ')',
            title = 'ZIO: replace .tap(_ => ' .. value_text .. ') with .zipLeft(' .. value_text .. ')',
          }),
        }
      else
        return {}
      end
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
      local start = matches[1][1]
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      local _, _, start_row, start_col = start:range()
      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        local value_text = utils.get_node_text(bufnr, value)

        local base_diagnostic = {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
        }

        return {
          utils.deep_merge(base_diagnostic, {
            replacement = ' *> ' .. value_text,
            title = 'ZIO: replace .flatMap(_ => ' .. value_text .. ') with *> ' .. value_text,
          }),
          utils.deep_merge(base_diagnostic, {
            replacement = '.zipRight(' .. value_text .. ')',
            title = 'ZIO: replace .flatMap(_ => ' .. value_text .. ') with .zipRight(' .. value_text .. ')',
          }),
        }
      else
        return {}
      end
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
      parameters: (wildcard) (_) @_3 (#not-eq? @_3 "()")
    )
  ) @_4
)
]]),
    handler = function(bufnr, matches)
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        return {
          {
            diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
            action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
            replacement = 'as(' .. value_text .. ')',
            title = 'ZIO: replace .map(_ => ' .. value_text .. ') with .as(' .. value_text .. ')',
          },
        }
      else
        return {}
      end
    end,
  },

  -- x.catchAll(_ => ZIO.unit) ~> x.ignore
  catch_all_unit = {
    query = parse_query([[
(call_expression 
  function: (field_expression
    value: (_)
    field: (_) @_1 (#eq? @_1 "catchAll")
  )
  arguments: (arguments
    (lambda_expression 
      parameters: (wildcard)
      (field_expression
        value: (identifier) @_2 (#eq? @_2 "ZIO")
        field: (identifier) @_3 (#eq? @_3 "unit")
      ) @_4
     )
  ) @_5
)
]]),
    handler = function(bufnr, matches)
      local target = matches[1][1]
      local value = matches[4][1]
      local finish = matches[5][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        return {
          {
            diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
            action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
            replacement = 'ignore',
            title = 'ZIO: replace .catchAll(_ => ' .. value_text .. ') with .ignore',
          },
        }
      else
        return {}
      end
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

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'ZIO.' .. replacement .. '(' .. collection_text .. ')' .. value_text,
          title = 'ZIO: replace ZIO.' .. foreach_text .. ' with ZIO.' .. replacement,
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
      local target = matches[2][1]
      local finish = matches[3][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'ignore',
          title = 'ZIO: replace .foldCause(_ => (), _ => ()) with .ignore',
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
    (lambda_expression parameters: (wildcard) (_) @_3)
  )
) @_4
]]),
    handler = function(bufnr, matches)
      local target = matches[2][1]
      local value = matches[3][1]
      local finish = matches[4][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)
      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        return {
          {
            diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
            action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
            replacement = 'orElseFail(' .. value_text .. ')',
            title = 'ZIO: replace .mapError(_ => ' .. value_text .. ') with .orElseFail(' .. value_text .. ')',
          },
        }
      else
        return {}
      end
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
      local target = matches[2][1]
      local value = matches[6][1]
      local finish = matches[7][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)
      local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      if is_zio then
        return {
          {
            diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
            action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
            replacement = 'orElseFail(' .. value_text .. ')',
            title = 'ZIO: replace .orElse(ZIO.fail(' .. value_text .. ')) with .orElseFail(' .. value_text .. ')',
          },
        }
      else
        return {}
      end
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
      local target = matches[2][1]
      local value = matches[4][1]
      local finish = matches[5][1]

      local dstart_row, dstart_col, _, _ = target:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'orElseFail(' .. value_text .. ')',
          title = 'ZIO: replace .flatMapError(_ => ZIO.succeed('
            .. value_text
            .. ')) with .orElseFail('
            .. value_text
            .. ')',
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

      return results
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

      return results
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
      ((identifier) @_4 (#eq? @_4 "None"))
      ((generic_function
        function: (field_expression
          value: (identifier) @_5 (#eq? @_5 "Option")
          field: (identifier) @_6 (#eq? @_6 "empty")
        ) @_7
        type_arguments: (type_arguments (type_identifier) @_8)
      ))
    ] @_9
  ) @_10
)
]]),
    handler = function(bufnr, matches)
      local start = matches[3][1]
      local value = matches[9][1]
      local finish = matches[10][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local value_text = utils.get_node_text(bufnr, value)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'ZIO.none',
          title = 'ZIO: replace ZIO.succeed(' .. value_text .. ') with ZIO.none',
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
    (call_expression
      function: (identifier) @_4 (#any-of? @_4 "Some" "Option")
      arguments: (arguments (_) @_5)
    ) @_6
  ) @_7
)
]]),
    handler = function(bufnr, matches)
      local start = matches[3][1]
      local value = matches[5][1]
      local expr = matches[6][1]
      local finish = matches[7][1]

      local dstart_row, dstart_col, _, _ = start:range()
      local _, _, end_row, end_col = finish:range()

      local expr_text = utils.get_node_text(bufnr, expr)
      local value_text = utils.get_node_text(bufnr, value)

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'ZIO.some(' .. value_text .. ')',
          title = 'ZIO: replace ZIO.succeed(' .. expr_text .. ') with ZIO.some(' .. value_text .. ')',
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

      return {
        {
          diagnostic = { row = dstart_row, start_col = dstart_col, end_col = end_col },
          action = { start_row = dstart_row, start_col = dstart_col, end_row = end_row, end_col = end_col },
          replacement = 'ZIO.' .. smartc_text .. '(' .. value_text .. ')',
          title = 'ZIO: replace ZIO.succeed(' .. expr_text .. ') with ZIO.' .. smartc_text .. '(' .. value_text .. ')',
        },
      }
    end,
  },
}
