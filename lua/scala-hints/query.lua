local utils = require('scala-hints.utils')
local semantic = require('scala-hints.semantic')
local ts = vim.treesitter

local zio_predicate = function(value)
  return string.find(value, 'ZIO') ~= nil -- TODO: match part of markdown?
end

local function parse_query(query)
  return ts.query.parse('scala', query)
end

-- TODO: all #eq? against ZIO.succeed and ZIO.unit need to be broken down as it can be ZIO\n.unit ...
-- or alternatively can match against regex with \n and \s symbols in-between
local queries = {

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

      -- return as pending, do not block here
      return {
        ready = {},
        pending = {
          function(publish)
            semantic.hover_predicate(bufnr, target, zio_predicate, function(is_zio)
              if is_zio then
                publish(item)
              end
            end)
          end,
        },
      }
    end,
  },

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
          diagnostic = {
            row = start_row,
            start_col = start_col,
            end_col = end_col,
          },
          action = {
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
          },
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
            diagnostic = {
              row = start_row,
              start_col = start_col,
              end_col = end_col,
            },
            action = {
              start_row = start_row,
              start_col = start_col,
              end_row = end_row,
              end_col = end_col,
            },
            replacement = 'unit',
            title = 'ZIO: replace .map(_ => ()) with .unit',
          },
        }
      else
        return {}
      end
    end,
  },

  -- *> ZIO.unit        ~> .unit
  -- TODO: if ZIO.succeed(()) is on the next line, treesitter renders it as a sibling to the function definition
  -- example: def func = effect *>
  --   ZIO.succeed(())
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

      -- local is_zio = utils.hover_node_and_match(bufnr, finish, zio_predicate)

      -- if is_zio then
      return {
        {
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = '.unit',
          title = 'ZIO: replace *> ' .. replaced .. ' with .unit',
        },
      }
      -- end
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

      -- local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      -- if is_zio then
      return {
        {
          diagnostic = {
            row = start_row,
            start_col = start_col,
            end_col = end_col,
          },
          action = {
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'unit',
          title = 'ZIO: replace .as(()) with .unit',
        },
      }
      -- end
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

      -- local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate)

      -- if is_zio then
      return {
        {
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = '.as(' .. value_text .. ')',
          title = 'ZIO: replace *> ZIO.succeed(' .. value_text .. ') with .as(' .. value_text .. ')',
        },
      }
      -- end
    end,
  },

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
            diagnostic = {
              row = dstart_row,
              start_col = dstart_col,
              end_col = end_col,
            },
            action = {
              start_row = dstart_row,
              start_col = dstart_col,
              end_row = end_row,
              end_col = end_col,
            },
            replacement = 'as(' .. value_text .. ')',
            title = 'ZIO: replace .map(_ => ' .. value_text .. ') with .as(' .. value_text .. ')',
          },
        }
      else
        return {}
      end
    end,
  },

  -- x.catchAll(_ => ()) ~> .ignore
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
            diagnostic = {
              row = dstart_row,
              start_col = dstart_col,
              end_col = end_col,
            },
            action = {
              start_row = dstart_row,
              start_col = dstart_col,
              end_row = end_row,
              end_col = end_col,
            },
            replacement = 'ignore',
            title = 'ZIO: replace .catchAll(_ => ' .. value_text .. ') with .ignore',
          },
        }
      else
        return {}
      end
    end,
  },

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

      local replacement = nil
      if foreach_text == 'collectAll' then
        replacement = 'foreach'
      else
        replacement = 'foreachPar'
      end

      return {
        {
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = dstart_row,
            start_col = dstart_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'ZIO.' .. replacement .. '(' .. collection_text .. ')' .. value_text,
          title = 'ZIO: replace ZIO.' .. foreach_text .. ' with ZIO.' .. replacement,
        },
      }
    end,
  },

  -- x.foldCause(_ => (), _ => ()) ~> .ignore
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

      -- local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate, tx)

      -- if is_zio then
      return {
        {
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = dstart_row,
            start_col = dstart_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'ignore',
          title = 'ZIO: replace .foldCause(_ => (), _ => ()) with .ignore',
        },
      }
      -- end
    end,
  },

  -- x.mapError(_ => "hello") ~> x.orElseFail("hello")
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
            diagnostic = {
              row = dstart_row,
              start_col = dstart_col,
              end_col = end_col,
            },
            action = {
              start_row = dstart_row,
              start_col = dstart_col,
              end_row = end_row,
              end_col = end_col,
            },
            replacement = 'orElseFail(' .. value_text .. ')',
            title = 'ZIO: replace .mapError(_ => ' .. value_text .. ') with .orElseFail(' .. value_text .. ')',
          },
        }
      else
        return {}
      end
    end,
  },

  -- x.orElse(ZIO.fail("hello")) ~> x.orElseFail("hello")
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
            diagnostic = {
              row = dstart_row,
              start_col = dstart_col,
              end_col = end_col,
            },
            action = {
              start_row = dstart_row,
              start_col = dstart_col,
              end_row = end_row,
              end_col = end_col,
            },
            replacement = 'orElseFail(' .. value_text .. ')',
            title = 'ZIO: replace .orElse(ZIO.fail(' .. value_text .. ')) with .orElseFail(' .. value_text .. ')',
          },
        }
      else
        return {}
      end
    end,
  },

  -- x.flatMapError(_ => ZIO.succeed("hello")) ~> x.orElseFail("hello")
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

      -- local is_zio = utils.hover_node_and_match(bufnr, target, zio_predicate, tx)

      -- if is_zio then
      return {
        {
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = dstart_row,
            start_col = dstart_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'orElseFail(' .. value_text .. ')',
          title = 'ZIO: replace .flatMapError(_ => ZIO.succeed('
            .. value_text
            .. ')) with .orElseFail('
            .. value_text
            .. ')',
        },
      }
      -- end
    end,
  },

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
            diagnostic = {
              row = start_row,
              start_col = start_col,
              end_col = end_col,
            },
            action = {
              start_row = start_row,
              start_col = start_col,
              end_row = end_row,
              end_col = end_col,
            },
            replacement = replacement,
            title = 'ZIO: replace ZIO[' .. r_value .. ', ' .. e_value .. ', ' .. a_value .. '] with ' .. replacement,
          })
        end
      end

      return results
    end,
  },

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
            diagnostic = {
              row = start_row,
              start_col = start_col,
              end_col = end_col,
            },
            action = {
              start_row = start_row,
              start_col = start_col,
              end_row = end_row,
              end_col = end_col,
            },
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
  -- TODO: support cats syntax none
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
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = dstart_row,
            start_col = dstart_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'ZIO.none',
          title = 'ZIO: replace ZIO.succeed(' .. value_text .. ') with ZIO.none',
        },
      }
    end,
  },

  -- ZIO.succeed(Some(x)) ~> ZIO.some(x)
  -- ZIO.succeed(Option(x)) ~> ZIO.some(x)
  -- TODO: support cats syntax x.some
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
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = dstart_row,
            start_col = dstart_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'ZIO.some(' .. value_text .. ')',
          title = 'ZIO: replace ZIO.succeed(' .. expr_text .. ') with ZIO.some(' .. value_text .. ')',
        },
      }
    end,
  },

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

      local either = matches[4][1]
      local cats_either = matches[7][1]

      local value = matches[5][1]
      local cats_value = matches[6][1]

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
          diagnostic = {
            row = dstart_row,
            start_col = dstart_col,
            end_col = end_col,
          },
          action = {
            start_row = dstart_row,
            start_col = dstart_col,
            end_row = end_row,
            end_col = end_col,
          },
          replacement = 'ZIO.' .. smartc_text .. '(' .. value_text .. ')',
          title = 'ZIO: replace ZIO.succeed(' .. expr_text .. ') with ZIO.' .. smartc_text .. '(' .. value_text .. ')',
        },
      }
    end,
  },

  -- x.map(_ => ExitCode.success) ~> x.exitCode
  exit_code = {},
  -- x.as(ExitCode.success) ~> x.exitCode
  exit_code2 = {},
  -- x.fold(_ => ExitCode.failure, _ => ExitCode.success)
  exit_code3 = {},

  -- ZIO.fail(new Exception("hello")).orDie ~> ZIO.die(new Exception("hello"))
  -- TODO: how to verify the type of expression within fail call, can this be done with "textDocument/hover"
  -- yes, probably with this https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#typeHierarchy_supertypes
  zio_die = {},
}

local M = {}

local function normalize_handler_result(res)
  -- old style: array
  if res == nil then
    return { ready = {}, pending = {} }
  end
  if res.ready ~= nil or res.pending ~= nil then
    return {
      ready = res.ready or {},
      pending = res.pending or {},
    }
  end
  -- assume old style list
  return { ready = res, pending = {} }
end
---
--- Executes a query on a given buffer and returns the results.
--- @param opts (table) The options for running the query.
---   - bufnr (number, optional): The buffer number to run the query on. Defaults to the current buffer.
---   - start_line (number, optional): The starting line for the query. Defaults to 0.
---   - end_line (number, optional): The ending line for the query. Defaults to the total number of lines in the buffer.
---   - root (table): The root object for the query.
---   - handler (function): The handler function to process query results.
---   - query_name (string): The name of the query to run.
--- @return function callback
function M.run_query(opts)
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  local start_line = opts.start_line or 0
  local end_line = opts.end_line or vim.api.nvim_buf_line_count(bufnr)

  local root = opts.root
  local callback = opts.callback

  return function(cb)
    --- @type table
    ---   - query (vim.treesitter.Query) - compiled treesitter query
    ---   - handler (function) - function that knows how to collect results of the match
    local query = queries[opts.query_name]
    if query == nil then
      return callback({})
    end

    local ok, query_results = pcall(function()
      return query.query:iter_matches(root, bufnr, start_line, end_line + 1)
    end)

    local results = {}
    local pending = {}

    if ok then
      for _, matches, _ in query_results do
        local ok2, res = pcall(query.handler, bufnr, matches)

        if ok2 then
          local norm = normalize_handler_result(res)

          for _, item in ipairs(norm.ready) do
            table.insert(results, callback(item))
          end

          for _, thunk in ipairs(norm.pending) do
            table.insert(pending, thunk)
          end
        else
          vim.notify('Query ' .. opts.query_name .. ' handler failed: ' .. res)
        end
      end
    else
      vim.notify('Query ' .. opts.query_name .. ' failed ' .. query_results, vim.log.levels.WARN)
    end

    -- publish immediate
    cb(results)

    -- publish async results later
    for _, thunk in ipairs(pending) do
      thunk(function(item)
        -- IMPORTANT: callback(item) likely publishes diagnostics
        -- If callback only *transforms*, then adapt this to publish properly.
        callback(item)
      end)
    end

    return
  end
end

return M
