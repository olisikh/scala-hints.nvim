local M = {}
local logger = require('scala-hints.logger').new('semantic')

local settings = {
  type_definition_timeouts_ms = { 400, 1000, 2000 },
  max_inflight = 4,
}

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
      cache = {}, -- key -> { tick, uris }
      inflight = {}, -- key -> { callbacks = {{predicate, cb}, ...}, tick, done }
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

local function collect_location_uris(result)
  if result == nil then
    return nil
  end

  local uris = {}
  local function add_uri(item)
    if type(item) ~= 'table' then
      return
    end
    local uri = item.targetUri or item.uri
    if type(uri) == 'string' and uri ~= '' then
      table.insert(uris, uri)
    end
  end

  if vim.islist(result) then
    for _, item in ipairs(result) do
      add_uri(item)
    end
  else
    add_uri(result)
  end

  if #uris == 0 then
    return nil
  end

  return uris
end

local function pump(bufnr)
  local s = buf_state(bufnr)

  while s.inflight_n < settings.max_inflight and #s.queue > 0 do
    local job = table.remove(s.queue, 1)
    s.inflight_n = s.inflight_n + 1

    local key = job.key
    s.inflight[key] = { callbacks = job.callbacks, tick = job.tick, done = false }

    local done = function(uris, cache_ok, cache_reason)
      local infl = s.inflight[key]
      if not infl or infl.done then
        return
      end
      infl.done = true

      s.inflight[key] = nil
      s.inflight_n = s.inflight_n - 1

      -- cache the raw URIs (not the predicate result) so different predicates
      -- can evaluate them independently on cache hits
      if cache_ok ~= false and uris ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
        local cur_tick = vim.api.nvim_buf_get_changedtick(bufnr)
        if cur_tick == job.tick then
          s.cache[key] = { tick = job.tick, uris = uris }
        end
      else
        local reason = cache_reason
        if cache_ok == false then
          reason = cache_reason or 'uncacheable'
        elseif uris == nil then
          reason = 'no-uris'
        end
        if reason ~= nil then
          logger.debug(
            string.format(
              'type_definition result not cached (%s) for %s:%d:%d:%d:%d',
              reason,
              job.method,
              job.sr,
              job.sc,
              job.er,
              job.ec
            ),
            { bufnr = bufnr }
          )
        end
      end

      -- Each callback receives the raw URIs and applies its own predicate
      for _, entry in ipairs(job.callbacks) do
        local predicate_result = false
        if uris then
          for _, uri in ipairs(uris) do
            if entry.predicate(uri) then
              predicate_result = true
              break
            end
          end
        end
        pcall(entry.cb, predicate_result)
      end

      pump(bufnr)
    end

    local function log_miss(reason)
      logger.debug(
        string.format(
          'type_definition miss (%s) for %s:%d:%d:%d:%d after %d attempt(s)',
          reason,
          job.method,
          job.sr,
          job.sc,
          job.er,
          job.ec,
          #job.timeouts
        ),
        { bufnr = bufnr }
      )
    end

    local function run_attempt(idx)
      -- Guard: first responder (timeout or LSP) wins; the other is ignored
      local resolved = false
      local timeout_ms = job.timeouts[idx]

      logger.debug(
        string.format(
          'type_definition attempt %d/%d for %s:%d:%d:%d:%d (timeout=%dms)',
          idx,
          #job.timeouts,
          job.method,
          job.sr,
          job.sc,
          job.er,
          job.ec,
          timeout_ms
        ),
        { bufnr = bufnr }
      )

      vim.defer_fn(function()
        if resolved then
          return
        end
        resolved = true

        if idx < #job.timeouts then
          run_attempt(idx + 1)
        else
          log_miss('timeout')
          done(nil, false, 'timeout')
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
            done(nil, false, tostring(err))
          end
          return
        end

        local uris = collect_location_uris(result)
        local debug_text = uris and table.concat(uris, '\n') or nil
        logger.info(
          string.format(
            'request result for %s:%d:%d:%d:%d -> uris=%s',
            job.method,
            job.sr,
            job.sc,
            job.er,
            job.ec,
            truncate_text(debug_text, 300) or 'nil'
          ),
          { bufnr = bufnr }
        )
        if not uris then
          done(nil, false, 'no-definition')
        else
          done(uris, true)
        end
      end)
    end

    run_attempt(1)
  end
end

--- Request a typeDefinition-derived boolean predicate check, with callback.
--- The underlying LSP result (URI list) is cached per position so that multiple
--- callers with different predicates (e.g. is_zio_type, is_ce_type) each get
--- their own predicate evaluated against the same cached URIs.
---@param bufnr integer buffer number
---@param node TSNode|nil node to resolve
---@param predicate fun(value: string): boolean predicate to match against location URI
---@param cb fun(result: boolean) callback with the predicate result
function M.type_definition_predicate(bufnr, node, predicate, cb)
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

  -- Retarget: when the node is the receiver in a field_expression (e.g. `expr.map`),
  -- resolve typeDefinition on the method identifier (`map`) instead of the receiver.
  -- This ensures Metals returns the definition of the method (e.g. ZIO#map in zio/ZIO.scala)
  -- rather than the type of the receiver itself (which could be a non-ZIO/CE type).
  local target = node
  local parent = node:parent()
  if parent and parent:type() == 'field_expression' then
    local field = parent:field('field')[1]
    if field then
      logger.debug(
        string.format('retarget typeDefinition from %s to field %s', node:type(), field:type()),
        { bufnr = bufnr }
      )
      target = field
    end
  end

  local sr, sc, er, ec = target:range()
  local key = make_key('textDocument/typeDefinition', sr, sc, er, ec)

  -- Cache hit: evaluate THIS caller's predicate against the cached URIs
  local cached = s.cache[key]
  if cached and cached.tick == tick then
    local hit = false
    if cached.uris then
      for _, uri in ipairs(cached.uris) do
        if predicate(uri) then
          hit = true
          break
        end
      end
    end
    logger.debug(
      string.format(
        'typeDefinition cache hit for %s:%d:%d:%d:%d -> %s',
        'textDocument/typeDefinition',
        sr,
        sc,
        er,
        ec,
        tostring(hit)
      ),
      { bufnr = bufnr }
    )
    cb(hit)
    return
  end

  -- Inflight join: attach this caller's predicate+cb so it gets its own evaluation
  local infl = s.inflight[key]
  if infl and infl.tick == tick then
    logger.debug(
      string.format('typeDefinition inflight join for %s:%d:%d:%d:%d', 'textDocument/typeDefinition', sr, sc, er, ec),
      { bufnr = bufnr }
    )
    table.insert(infl.callbacks, { predicate = predicate, cb = cb })
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'metals' })
  local metals = clients[1]
  if not metals then
    logger.warn(
      string.format(
        'typeDefinition skipped: no Metals client for %s:%d:%d:%d:%d',
        'textDocument/typeDefinition',
        sr,
        sc,
        er,
        ec
      ),
      { bufnr = bufnr }
    )
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
    method = 'textDocument/typeDefinition',
    params = params,
    request = function(req_cb)
      metals.request('textDocument/typeDefinition', params, req_cb, bufnr)
    end,
    callbacks = { { predicate = predicate, cb = cb } },
    timeouts = settings.type_definition_timeouts_ms,
    sr = sr,
    sc = sc,
    er = er,
    ec = ec,
  }

  table.insert(s.queue, job)
  pump(bufnr)
end

--- Clear cached state for a buffer
---@param bufnr integer buffer number
function M.reset(bufnr)
  state[bufnr] = nil
end

--- Configure semantic behavior.
---@param opts table|nil
---  - type_definition: table
---    - timeouts_ms: number[]
function M.configure(opts)
  if type(opts) ~= 'table' then
    return
  end

  local td = opts.type_definition
  if type(td) ~= 'table' then
    return
  end

  local timeouts = normalize_timeouts(td.timeouts_ms)
  if timeouts then
    settings.type_definition_timeouts_ms = timeouts
  end

  if type(td.max_inflight) == 'number' and td.max_inflight > 0 then
    settings.max_inflight = td.max_inflight
  end
end

return M
