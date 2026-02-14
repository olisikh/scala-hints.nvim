--- Generic Treesitter query execution engine.
---
--- Runs a parsed Treesitter query against a buffer's AST, invokes the
--- handler for each match, and separates results into ready (synchronous)
--- and pending (async/callback-based) items.

local M = {}

local function normalize_handler_result(res)
  if res == nil then
    return { ready = {}, pending = {} }
  end
  if res.ready ~= nil or res.pending ~= nil then
    return {
      ready = res.ready or {},
      pending = res.pending or {},
    }
  end
  return { ready = res, pending = {} }
end

--- Build a thunk that runs a single query against a buffer's AST.
---
---@param opts table
---  - bufnr       integer     buffer number
---  - root        TSNode      root node of the syntax tree
---  - query_name  string      name used in log/error messages
---  - query_def   table       { query = TSQuery, handler = fn(bufnr, matches) }
---  - start_line  integer?    first line (0-based, default 0)
---  - end_line    integer?    last line  (default buf line count)
---  - callback    function    transforms a single result item
---@return function(cb) thunk that calls cb(results)
function M.run_query(opts)
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local start_line = opts.start_line or 0
  local end_line = opts.end_line or vim.api.nvim_buf_line_count(bufnr)
  local root = opts.root
  local callback = opts.callback
  local query_name = opts.query_name or 'unknown'
  local q = opts.query_def

  return function(cb)
    if q == nil or q.query == nil then
      -- No query to run; preserve existing behavior of silently returning no results.
      return cb({})
    end

    if q.handler == nil then
      vim.notify('Query ' .. query_name .. ' has no handler', vim.log.levels.WARN)
      return cb({})
    end
    local ok_iter, iter_or_err = pcall(function()
      return q.query:iter_matches(root, bufnr, start_line, end_line + 1)
    end)

    if not ok_iter then
      vim.notify('Query ' .. query_name .. ' failed: ' .. tostring(iter_or_err), vim.log.levels.WARN)
      return cb({})
    end

    local results = {}
    local pending = {}

    for _, matches, _ in iter_or_err do
      local ok_handler, res_or_err = pcall(q.handler, bufnr, matches)

      if not ok_handler then
        vim.notify('Query ' .. query_name .. ' handler failed: ' .. tostring(res_or_err), vim.log.levels.WARN)
      else
        local norm = normalize_handler_result(res_or_err)

        for _, item in ipairs(norm.ready) do
          local ok_cb, out = pcall(callback, item)
          if ok_cb then
            table.insert(results, out)
          else
            vim.notify('Query ' .. query_name .. ' callback failed: ' .. tostring(out), vim.log.levels.WARN)
          end
        end

        for _, thunk in ipairs(norm.pending) do
          table.insert(pending, thunk)
        end
      end
    end

    -- If there are no pending items, return ready batch immediately.
    if #pending == 0 then
      return cb(results)
    end

    -- Wait for all pending thunks to resolve before calling cb.
    -- Each pending thunk MUST call its done(item_or_nil) callback exactly once.
    local remaining = #pending
    for _, thunk in ipairs(pending) do
      local ok_thunk, err = pcall(thunk, function(item)
        if item ~= nil then
          local ok_cb, out = pcall(callback, item)
          if ok_cb then
            table.insert(results, out)
          else
            vim.notify('Query ' .. query_name .. ' callback failed (async): ' .. tostring(out), vim.log.levels.WARN)
          end
        end

        remaining = remaining - 1
        if remaining == 0 then
          cb(results)
        end
      end)

      if not ok_thunk then
        vim.notify('Query ' .. query_name .. ' pending thunk failed: ' .. tostring(err), vim.log.levels.WARN)
        remaining = remaining - 1
        if remaining == 0 then
          cb(results)
        end
      end
    end
  end
end

return M
