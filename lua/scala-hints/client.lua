local api = vim.api
local lsp = vim.lsp
local constants = require('scala-hints.constants')
local diagnostics_mod = require('scala-hints.diagnostics')
local actions_mod = require('scala-hints.actions')
local logger = require('scala-hints.logger').new('client')

local M = {}

-- Single client instance (one in-process server for all scala buffers)
local client_id = nil
local active_dispatchers = nil
local active_dispatcher_generation = 0
local client_lifecycle_generation = 0

local function is_valid_bufnr(bufnr)
  return type(bufnr) == 'number' and api.nvim_buf_is_valid(bufnr)
end

-- Server capabilities advertised during the initialize handshake.
-- Neovim uses these to decide which requests to route to our client.
local server_capabilities = {
  codeActionProvider = true,
  textDocumentSync = {
    openClose = true,
    change = 1, -- Full sync
    save = true,
  },
}

--- Check whether Metals is attached, initialized, and done indexing for a given buffer.
--- nvim-metals sets vim.g.metals_status with progress info while Metals is
--- importing the build or indexing. When empty/nil, Metals is idle.
local function metals_ready(bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr })
  for _, c in ipairs(clients) do
    if c.name == 'metals' and c.initialized then
      local status = vim.g.metals_status
      if type(status) == 'string' and status ~= '' then
        return false
      end
      return true
    end
  end
  return false
end

-- Per-buffer readiness state. The most recent caller owns the completion
-- callback, which lets workspace indexing supersede stale queued work.
local pending_readiness = {}

-- Forward declaration (defined below schedule_diagnostics)
local refresh_diagnostics

local function complete(opts, ok)
  if opts and opts.on_complete then
    opts.on_complete(ok)
  end
end

local function cancel_pending_readiness()
  for _, state in pairs(pending_readiness) do
    complete(state.opts, false)
  end
  pending_readiness = {}
end

local function next_client_lifecycle()
  client_lifecycle_generation = client_lifecycle_generation + 1
  return client_lifecycle_generation
end

local function invalidate_dispatcher_state()
  active_dispatchers = nil
  active_dispatcher_generation = active_dispatcher_generation + 1
  cancel_pending_readiness()
end

local function clear_client_state(lifecycle_generation)
  if lifecycle_generation ~= client_lifecycle_generation then
    return false
  end

  client_id = nil
  invalidate_dispatcher_state()
  return true
end

--- Collect diagnostics once Metals is ready, polling if necessary.
---@param bufnr integer
---@param dispatchers vim.lsp.rpc.Dispatchers
---@param opts table?
---@param dispatcher_generation integer
local function schedule_diagnostics(bufnr, dispatchers, opts, dispatcher_generation)
  if not is_valid_bufnr(bufnr) then
    complete(opts, false)
    return
  end

  if not metals_ready(bufnr) then
    local state = pending_readiness[bufnr]
    if state then
      state.opts = opts
      state.dispatchers = dispatchers
      state.dispatcher_generation = dispatcher_generation
      return
    end

    state = {
      opts = opts,
      dispatchers = dispatchers,
      dispatcher_generation = dispatcher_generation,
    }
    pending_readiness[bufnr] = state
    logger.info('Metals not ready for buffer ' .. bufnr .. ', polling for readiness')

    local attempts = 0
    local max_attempts = 15 -- 15 × 2 s = 30 s max wait
    local interval_ms = 2000

    local function poll()
      if pending_readiness[bufnr] ~= state then
        return
      end

      attempts = attempts + 1
      if not is_valid_bufnr(bufnr) or attempts > max_attempts then
        pending_readiness[bufnr] = nil
        if attempts > max_attempts then
          logger.warn('Metals readiness timeout for buffer ' .. bufnr .. ' after ' .. max_attempts .. ' attempts')
        end
        complete(state.opts, false)
        return
      end

      if metals_ready(bufnr) then
        pending_readiness[bufnr] = nil
        logger.info('Metals ready for buffer ' .. bufnr .. ' (attempt ' .. attempts .. '), collecting diagnostics')
        refresh_diagnostics(bufnr, state.dispatchers, state.opts, state.dispatcher_generation)
      else
        logger.debug('Metals still indexing for buffer ' .. bufnr .. ' (attempt ' .. attempts .. '/' .. max_attempts .. ')')
        vim.defer_fn(poll, interval_ms)
      end
    end

    vim.defer_fn(poll, interval_ms)
    return
  end

  refresh_diagnostics(bufnr, dispatchers, opts, dispatcher_generation)
end

--- Collect diagnostics and push them back to Neovim via the dispatcher.
---@param bufnr integer
---@param dispatchers vim.lsp.rpc.Dispatchers
---@param opts table?
---@param dispatcher_generation integer
refresh_diagnostics = function(bufnr, dispatchers, opts, dispatcher_generation)
  if not is_valid_bufnr(bufnr) then
    complete(opts, false)
    return
  end

  logger.info('Collecting diagnostics for buffer ' .. bufnr)

  diagnostics_mod.collect_diagnostics(bufnr, function(results)
    if not results or not is_valid_bufnr(bufnr) or (opts and opts.is_current and not opts.is_current()) then
      complete(opts, false)
      return
    end

    -- Convert diagnostics to LSP format
    local lsp_diagnostics = {}
    for _, diag in ipairs(results) do
      table.insert(lsp_diagnostics, {
        range = {
          start = { line = diag.lnum or 0, character = diag.col or 0 },
          ['end'] = { line = diag.end_lnum or diag.lnum or 0, character = diag.end_col or diag.col or 0 },
        },
        message = diag.message or '',
        severity = diag.severity or vim.diagnostic.severity.HINT,
        source = diag.source or constants.name,
      })
    end

    -- Push diagnostics through the dispatcher notification channel.
    -- Neovim will handle them via its built-in publishDiagnostics handler.
    vim.schedule(function()
      local published = false
      if is_valid_bufnr(bufnr)
        and dispatcher_generation == active_dispatcher_generation
        and dispatchers == active_dispatchers
        and (not opts or not opts.is_current or opts.is_current())
      then
        dispatchers.notification('textDocument/publishDiagnostics', {
          uri = vim.uri_from_bufnr(bufnr),
          diagnostics = lsp_diagnostics,
        })
        published = true
      end
      complete(opts, published)
    end)
  end)
end

--- Refresh one buffer outside the LSP didOpen/didSave path.
---@param bufnr integer
---@param opts table?
---@return boolean
function M.refresh_diagnostics(bufnr, opts)
  opts = opts or {}
  if not active_dispatchers then
    complete(opts, false)
    return false
  end

  if opts.wait_for_metals == false then
    refresh_diagnostics(bufnr, active_dispatchers, opts, active_dispatcher_generation)
  else
    schedule_diagnostics(bufnr, active_dispatchers, opts, active_dispatcher_generation)
  end
  return true
end

--- Create the in-process RPC "server".
--- This is passed as the `cmd` field to vim.lsp.start().
--- Neovim calls it with `dispatchers` and expects a PublicClient back.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
function M.rpc_start(dispatchers)
  active_dispatchers = dispatchers
  active_dispatcher_generation = active_dispatcher_generation + 1
  local message_id = 0
  local stopped = false

  --- Handle an incoming request or notification from Neovim
  ---@param method string LSP method name
  ---@param params table? LSP params
  ---@param callback fun(err: any, result: any)? response callback (nil for notifications)
  ---@param is_notify boolean? true when this is a notification (no response expected)
  local function handle(method, params, callback, is_notify)
    params = params or {}
    message_id = message_id + 1

    local function send(result)
      if callback then
        callback(nil, result)
      end
    end

    -- === Lifecycle methods ===

    if method == 'initialize' then
      logger.info('Handling initialize request')
      send({
        capabilities = server_capabilities,
        serverInfo = {
          name = constants.name,
          version = '0.1.0',
        },
      })
      return true, message_id
    end

    if method == 'initialized' then
      logger.info('Client initialized')
      return true, message_id
    end

    if method == 'shutdown' then
      logger.info('Handling shutdown request')
      stopped = true
      send()
      return true, message_id
    end

    if method == 'exit' then
      logger.info('Handling exit notification')
      if dispatchers.on_exit then
        dispatchers.on_exit(0, 0)
      end
      return true, message_id
    end

    -- === Document sync notifications ===

    if method == 'textDocument/didOpen' or method == 'textDocument/didSave' then
      local uri = params.textDocument and params.textDocument.uri
      if uri then
        local bufnr = vim.uri_to_bufnr(uri)
        logger.info('Received ' .. method .. ' for buffer ' .. bufnr)

        -- Workspace-managed buffers are refreshed by the coordinator so its
        -- single-worker queue can prevent duplicate initial didOpen work.
        if vim.b[bufnr].scala_hints_workspace_managed then
          if method == 'textDocument/didSave' then
            require('scala-hints.workspace').refresh_buffer(bufnr)
          end
        else
          schedule_diagnostics(bufnr, dispatchers, nil, active_dispatcher_generation)
        end
      end
      return true, message_id
    end

    if method == 'textDocument/didChange' then
      -- We don't refresh on every keystroke; diagnostics run on didOpen/didSave.
      return true, message_id
    end

    if method == 'textDocument/didClose' then
      local uri = params.textDocument and params.textDocument.uri
      if uri then
        local bufnr = vim.uri_to_bufnr(uri)
        logger.info('Received didClose for buffer ' .. bufnr)
        -- Clear our diagnostics when the document is closed
        vim.schedule(function()
          if is_valid_bufnr(bufnr) then
            dispatchers.notification('textDocument/publishDiagnostics', {
              uri = uri,
              diagnostics = {},
            })
          end
        end)
      end
      return true, message_id
    end

    -- === Code actions ===

    if method == 'textDocument/codeAction' then
      logger.info('Handling textDocument/codeAction request')

      local context_params = params or {}
      local range = context_params.range
      if not range then
        send({})
        return true, message_id
      end

      local uri = context_params.textDocument and context_params.textDocument.uri
      if not uri then
        send({})
        return true, message_id
      end

      local bufnr = vim.uri_to_bufnr(uri)
      if not is_valid_bufnr(bufnr) then
        send({})
        return true, message_id
      end

      local start_line = range.start.line
      local end_line = range['end'].line

      actions_mod.resolve_actions(bufnr, start_line, end_line, function(action_results)
        local lsp_actions = {}
        if action_results then
          for _, action in ipairs(action_results) do
            table.insert(lsp_actions, {
              title = action.title,
              kind = 'quickfix',
              edit = {
                changes = {
                  [uri] = {
                    {
                      range = action.range,
                      newText = action.replacement,
                    },
                  },
                },
              },
            })
          end
        end

        logger.info('Returning ' .. #lsp_actions .. ' code actions')
        send(lsp_actions)
      end)

      return true, message_id
    end

    -- === Unhandled methods ===

    logger.info('Unhandled method: ' .. method)
    if not is_notify then
      send(nil)
    end

    return true, message_id
  end

  -- === PublicClient interface ===

  ---@param method string LSP method name
  ---@param params table? LSP request params
  ---@param callback fun(err: any, result: any) response callback
  ---@param notify_callback fun(message_id: integer)? called when the request is registered
  local function request(method, params, callback, notify_callback)
    logger.info('RPC request: ' .. method)

    local success, req_id = handle(method, params, vim.schedule_wrap(callback))

    if success and notify_callback then
      local id_to_clear = message_id
      vim.schedule(function()
        notify_callback(id_to_clear)
      end)
    end

    return success, message_id
  end

  ---@param method string LSP method name
  ---@param params table? LSP notification params
  local function notify(method, params)
    logger.info('RPC notification: ' .. method)
    handle(method, params, nil, true)
    return true
  end

  return {
    request = request,
    notify = notify,
    is_closing = function()
      return stopped
    end,
    terminate = function()
      stopped = true
    end,
  }
end

--- Start (or reuse) the in-process LSP client and attach it to the given buffer.
---@param bufnr integer buffer handle
---@return integer? client_id
function M.start(bufnr)
  if not is_valid_bufnr(bufnr) then
    logger.info('Invalid buffer: ' .. tostring(bufnr))
    return nil
  end

  -- Reuse existing client if it's still alive
  if client_id then
    local existing = lsp.get_client_by_id(client_id)
    if existing and not existing:is_stopped() then
      -- Just attach to the new buffer if not already attached
      if not lsp.buf_is_attached(bufnr, client_id) then
        lsp.buf_attach_client(bufnr, client_id)
        logger.info('Attached existing client ' .. client_id .. ' to buffer ' .. bufnr)
      end
      return client_id
    else
      logger.info('Previous client stopped, starting new one')
      client_id = nil
    end
  end

  logger.info('Starting in-process LSP client')

  local lifecycle_generation = next_client_lifecycle()
  -- The old dispatcher belongs to the stopped client. Clear it before
  -- attempting a replacement so a failed start cannot publish through it.
  invalidate_dispatcher_state()
  client_id = lsp.start({
    name = constants.name,
    cmd = M.rpc_start,
    filetypes = { 'scala' },
    root_dir = vim.fn.getcwd(),
    on_attach = function(_, buf)
      logger.info('Client attached to buffer ' .. buf)
    end,
    on_exit = function(code, signal)
      logger.info(('Client exited (code=%s, signal=%s)'):format(code, signal))
      clear_client_state(lifecycle_generation)
    end,
  }, {
    bufnr = bufnr,
  })

  if client_id then
    logger.info('Client started with id ' .. client_id)
  else
    logger.error('Failed to start in-process LSP client')
  end

  return client_id
end

--- Stop the in-process LSP client
function M.stop()
  next_client_lifecycle()
  invalidate_dispatcher_state()
  if not client_id then
    return
  end

  local c = lsp.get_client_by_id(client_id)
  if c then
    logger.info('Stopping client ' .. client_id)
    c:stop()
  end
  client_id = nil
end

--- Get the current client id
---@return integer?
function M.get_client_id()
  return client_id
end

return M
