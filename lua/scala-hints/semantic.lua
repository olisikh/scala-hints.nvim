local M = {}

-- per-buffer state
local state = {}

local function buf_state(bufnr)
  local s = state[bufnr]
  if not s then
    s = {
      tick = 0,
      cache = {}, -- key -> { tick, value }
      inflight = {}, -- key -> { callbacks = {...}, started_at_tick }
      queue = {}, -- array of jobs
      inflight_n = 0,
    }
    state[bufnr] = s
  end
  return s
end

local function make_key(method, start_row, start_col, end_row, end_col)
  return table.concat({ method, start_row, start_col, end_row, end_col }, ':')
end

-- Tune these:
local MAX_INFLIGHT = 4
local TIMEOUT_MS = 400

local function pump(bufnr)
  local s = buf_state(bufnr)

  while s.inflight_n < MAX_INFLIGHT and #s.queue > 0 do
    local job = table.remove(s.queue, 1)
    s.inflight_n = s.inflight_n + 1

    local key = job.key
    s.inflight[key] = { callbacks = job.callbacks, tick = job.tick, done = false }

    local done = function(value)
      local infl = s.inflight[key]
      if not infl or infl.done then
        return
      end
      infl.done = true

      s.inflight[key] = nil
      s.inflight_n = s.inflight_n - 1

      -- cache only if still same tick
      if vim.api.nvim_buf_is_valid(bufnr) then
        local cur_tick = vim.api.nvim_buf_get_changedtick(bufnr)
        if cur_tick == job.tick then
          s.cache[key] = { tick = job.tick, value = value }
        end
      end

      for _, cb in ipairs(job.callbacks) do
        pcall(cb, value)
      end

      pump(bufnr)
    end

    -- Guard: first responder (timeout or LSP) wins; the other is ignored
    local resolved = false
    vim.defer_fn(function()
      if resolved then
        return
      end
      resolved = true
      done(false)
    end, TIMEOUT_MS)

    vim.lsp.buf_request(bufnr, job.method, job.params, function(err, result)
      if resolved then
        return
      end
      resolved = true

      if err ~= nil then
        done(false)
        return
      end

      done(job.eval(result))
    end)
  end
end

--- Request a hover-derived boolean predicate check, with callback
---@param bufnr integer buffer number
---@param node TSNode|nil node to hover on
---@param predicate fun(value: string): boolean predicate to match against hover contents
---@param cb fun(result: boolean) callback with the predicate result
function M.hover_predicate(bufnr, node, predicate, cb)
  if not node then
    cb(false)
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    cb(false)
    return
  end

  local s = buf_state(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)

  local sr, sc, er, ec = node:range()
  local key = make_key('textDocument/hover', sr, sc, er, ec)

  -- cache hit (same tick)
  local cached = s.cache[key]
  if cached and cached.tick == tick then
    cb(cached.value)
    return
  end

  -- inflight dedupe
  local infl = s.inflight[key]
  if infl and infl.tick == tick then
    table.insert(infl.callbacks, cb)
    return
  end

  local params = vim.lsp.util.make_given_range_params({ sr, sc }, { er, ec }, bufnr)

  local job = {
    key = key,
    tick = tick,
    method = 'textDocument/hover',
    params = params,
    callbacks = { cb },
    eval = function(result)
      return result ~= nil
        and result.contents ~= nil
        and result.contents.value ~= nil
        and predicate(result.contents.value)
    end,
  }

  table.insert(s.queue, job)
  pump(bufnr)
end

--- Clear cached state for a buffer
---@param bufnr integer buffer number
function M.reset(bufnr)
  state[bufnr] = nil
end

return M
