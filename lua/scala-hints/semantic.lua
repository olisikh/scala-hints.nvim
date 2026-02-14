local M = {}
local logger = require('scala-hints.logger').new('semantic')

local settings = {
  hover_timeouts_ms = { 400, 1000, 2000 },
  log_misses = true,
}

local function normalize_timeouts(value)
  if type(value) ~= 'table' then
    return nil
  end

  local out = {}
  for _, item in ipairs(value) do
    if type(item) == 'number' and item > 0 then
      table.insert(out, item)
    end
  end

  if #out == 0 then
    return nil
  end

  return out
end

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
local HOVER_TIMEOUTS_MS = settings.hover_timeouts_ms

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

    local function log_miss(reason)
      if not settings.log_misses then
        return
      end

      logger.warn(string.format(
        'hover miss (%s) for %s:%d:%d:%d:%d after %d attempt(s)',
        reason,
        job.method,
        job.sr,
        job.sc,
        job.er,
        job.ec,
        #job.timeouts
      ))
    end

    local function run_attempt(idx)
      -- Guard: first responder (timeout or LSP) wins; the other is ignored
      local resolved = false
      local timeout_ms = job.timeouts[idx]

      vim.defer_fn(function()
        if resolved then
          return
        end
        resolved = true

        if idx < #job.timeouts then
          run_attempt(idx + 1)
        else
          log_miss('timeout')
          done(false)
        end
      end, timeout_ms)

      vim.lsp.buf_request(bufnr, job.method, job.params, function(err, result)
        if resolved then
          return
        end
        resolved = true

        if err ~= nil then
          if idx < #job.timeouts then
            run_attempt(idx + 1)
          else
            log_miss(tostring(err))
            done(false)
          end
          return
        end

        done(job.eval(result))
      end)
    end

    run_attempt(1)
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

  local params = vim.lsp.util.make_given_range_params({ sr, sc }, { er, ec }, bufnr, 'utf-16')

  local job = {
    key = key,
    tick = tick,
    method = 'textDocument/hover',
    params = params,
    callbacks = { cb },
    timeouts = HOVER_TIMEOUTS_MS,
    sr = sr,
    sc = sc,
    er = er,
    ec = ec,
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

--- Configure semantic hover behavior.
---@param opts table|nil
---  - hover: table
---    - timeouts_ms: number[]
---    - log_misses: boolean
function M.configure(opts)
  if type(opts) ~= 'table' then
    return
  end

  local hover = opts.hover
  if type(hover) ~= 'table' then
    return
  end

  local timeouts = normalize_timeouts(hover.timeouts_ms)
  if timeouts then
    settings.hover_timeouts_ms = timeouts
    HOVER_TIMEOUTS_MS = settings.hover_timeouts_ms
  end

  if type(hover.log_misses) == 'boolean' then
    settings.log_misses = hover.log_misses
  end
end

return M
