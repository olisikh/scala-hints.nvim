--- Tests for the libs registry module.
---
--- Verifies that the registry properly loads, namespaces, and caches queries
--- from each registered library.

local libs = require('scala-hints.libs')

describe('libs registry', function()
  before_each(function()
    libs.reload()
  end)

  describe('get_all_queries', function()
    it('returns a non-empty table', function()
      local all = libs.get_all_queries()
      assert.is_truthy(all)
      assert.is_true(vim.tbl_count(all) > 0)
    end)

    it('namespaces ZIO queries as zio/<name>', function()
      local all = libs.get_all_queries()
      -- Every key must start with "zio/"
      for key, _ in pairs(all) do
        assert.is_truthy(
          key:match('^zio/'),
          'Expected key to start with "zio/", got: ' .. key
        )
      end
    end)

    it('contains all 35 known ZIO queries', function()
      local expected = {
        'zio/succeed_unit',
        'zio/zio_die',
        'zio/map_unit',
        'zio/zip_right_unit',
        'zio/as_unit',
        'zio/zip_right_value',
        'zio/zip_right_operator',
        'zio/zip_left_value',
        'zio/flat_map_value',
        'zio/map_value',
        'zio/catch_all_unit',
        'zio/zio_foreach',
        'zio/foreach_par_n',
        'zio/fold_cause_ignore',
        'zio/or_else_fail',
        'zio/or_else_fail2',
        'zio/or_else_fail3',
        'zio/zio_type',
        'zio/zlayer_type',
        'zio/zio_none',
        'zio/zio_some',
        'zio/zio_either',
        'zio/delay',
        'zio/to_layer',
        'zio/provide_layer',
        'zio/zio_service',
        'zio/bimap',
        'zio/exit_code_map',
        'zio/exit_code_as',
        'zio/exit_code_fold',
        'zio/tap',
        'zio/tap_error',
        'zio/tap_both',
        'zio/when',
        'zio/unless',
      }
      local all = libs.get_all_queries()
      for _, name in ipairs(expected) do
        assert.is_truthy(all[name], 'Missing query: ' .. name)
      end
    end)

    it('each query has a query and handler field', function()
      local all = libs.get_all_queries()
      for key, qd in pairs(all) do
        assert.is_truthy(qd.query, key .. ': missing query field')
        assert.is_truthy(qd.handler, key .. ': missing handler field')
        -- qd.query is a parsed TSQuery (userdata/table), not a raw string
        assert.is_truthy(qd.query.iter_matches, key .. ': query should have iter_matches method')
        assert.are.equal('function', type(qd.handler), key .. ': handler should be a function')
      end
    end)

    it('caches results on second call', function()
      local first = libs.get_all_queries()
      local second = libs.get_all_queries()
      assert.are.equal(first, second) -- same table reference
    end)
  end)

  describe('reload', function()
    it('clears the cache so next call returns a new table', function()
      local first = libs.get_all_queries()
      libs.reload()
      local second = libs.get_all_queries()
      assert.are_not.equal(first, second) -- different table reference
    end)

    it('returned queries are still valid after reload', function()
      libs.reload()
      local all = libs.get_all_queries()
      assert.is_true(vim.tbl_count(all) > 0)
      for key, qd in pairs(all) do
        assert.is_truthy(qd.query, key .. ': missing query after reload')
        assert.is_truthy(qd.handler, key .. ': missing handler after reload')
      end
    end)
  end)
end)
