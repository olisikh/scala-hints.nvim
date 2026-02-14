local M = {}
local logger = require('scala-hints.logger').new('semantic')

local settings = {
  hover_timeouts_ms = { 400, 1000, 2000 },
  log_misses = true,
}

local function hover_contents_to_text(contents)
  if contents == nil then
    return nil
  end

  if type(contents) == 'string' then
    return contents
  end

  if type(contents) ~= 'table' then
    return tostring(contents)
  end

  if contents.value ~= nil then
    return tostring(contents.value)
  end

  if contents.language ~= nil and contents.value ~= nil then
    return tostring(contents.value)
  end

  local parts = {}
  for _, item in ipairs(contents) do
    if type(item) == 'string' then
      table.insert(parts, item)
    elseif type(item) == 'table' and item.value ~= nil then
      table.insert(parts, tostring(item.value))
    end
  end

  if #parts == 0 then
    return nil
  end

  return table.concat(parts, '\n')
end

local function truncate_text(text, max_len)
  if text == nil then
    return nil
  end
  if #text <= max_len then
    return text
  end
  return string.sub(text, 1, max_len) .. '...'
end

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

    local done = function(value, cache_ok, cache_reason)
      local infl = s.inflight[key]
      if not infl or infl.done then
        return
      end
      infl.done = true

      s.inflight[key] = nil
      s.inflight_n = s.inflight_n - 1

      -- cache only if still same tick and value is cacheable + true
      if cache_ok ~= false and value == true and vim.api.nvim_buf_is_valid(bufnr) then
        local cur_tick = vim.api.nvim_buf_get_changedtick(bufnr)
        if cur_tick == job.tick then
          s.cache[key] = { tick = job.tick, value = value }
        end
      else
        local reason = cache_reason
        if cache_ok == false then
          reason = cache_reason or 'uncacheable'
        elseif value ~= true then
          reason = 'false'
        end
        if reason ~= nil then
          logger.warn(string.format(
            'hover result not cached (%s) for %s:%d:%d:%d:%d',
            reason,
            job.method,
            job.sr,
            job.sc,
            job.er,
            job.ec
          ), { bufnr = bufnr })
        end
      end

      -- no retry hook: hover misses are logged only

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
      ), { bufnr = bufnr })
    end

    local function run_attempt(idx)
      -- Guard: first responder (timeout or LSP) wins; the other is ignored
      local resolved = false
      local timeout_ms = job.timeouts[idx]

      logger.info(string.format(
        'hover attempt %d/%d for %s:%d:%d:%d:%d (timeout=%dms)',
        idx,
        #job.timeouts,
        job.method,
        job.sr,
        job.sc,
        job.er,
        job.ec,
        timeout_ms
      ), { bufnr = bufnr })

      vim.defer_fn(function()
        if resolved then
          return
        end
        resolved = true

        if idx < #job.timeouts then
          run_attempt(idx + 1)
        else
          log_miss('timeout')
          done(false, false, 'timeout')
        end
      end, timeout_ms)

      job.request(function(err, result)
        if resolved then
          return
        end
        resolved = true

        if err ~= nil then
          if idx < #job.timeouts then
            run_attempt(idx + 1)
          else
            log_miss(tostring(err))
            done(false, false, tostring(err))
          end
          return
        end

        local eval_ok = job.eval(result)
        local text = result ~= nil and hover_contents_to_text(result.contents) or nil
        logger.info(string.format(
          'hover result for %s:%d:%d:%d:%d -> %s (text=%s)',
          job.method,
          job.sr,
          job.sc,
          job.er,
          job.ec,
          tostring(eval_ok),
          truncate_text(text, 300) or 'nil'
        ), { bufnr = bufnr })
        if text == nil then
          done(false, false, 'no-hover')
        else
          done(eval_ok, true)
        end
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
    logger.info(string.format(
      'hover cache hit for %s:%d:%d:%d:%d -> %s',
      'textDocument/hover',
      sr,
      sc,
      er,
      ec,
      tostring(cached.value)
    ), { bufnr = bufnr })
    cb(cached.value)
    return
  end

  -- inflight dedupe
  local infl = s.inflight[key]
  if infl and infl.tick == tick then
    logger.info(string.format(
      'hover inflight join for %s:%d:%d:%d:%d',
      'textDocument/hover',
      sr,
      sc,
      er,
      ec
    ), { bufnr = bufnr })
    table.insert(infl.callbacks, cb)
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'metals' })
  local metals = clients[1]
  if not metals then
    logger.warn(string.format(
      'hover skipped: no Metals client for %s:%d:%d:%d:%d',
      'textDocument/hover',
      sr,
      sc,
      er,
      ec
    ), { bufnr = bufnr })
    cb(false)
    return
  end

  local encoding = metals.offset_encoding or 'utf-16'
  local params = vim.lsp.util.make_position_params(0, encoding)
  params.textDocument = { uri = vim.uri_from_bufnr(bufnr) }
  params.position = { line = sr, character = sc }

  local job = {
    key = key,
    tick = tick,
    method = 'textDocument/hover',
    params = params,
    request = function(cb)
      metals.request('textDocument/hover', params, cb, bufnr)
    end,
    callbacks = { cb },
    timeouts = HOVER_TIMEOUTS_MS,
    sr = sr,
    sc = sc,
    er = er,
    ec = ec,
    eval = function(result)
      local text = result ~= nil and hover_contents_to_text(result.contents) or nil
      return text ~= nil and predicate(text)
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
