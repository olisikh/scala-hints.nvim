local api = vim.api
local lsp = vim.lsp
local constants = require('scala-hints.constants')
local diagnostics_mod = require('scala-hints.diagnostics')
local actions_mod = require('scala-hints.actions')
local logger = require('scala-hints.logger').new('client')

local M = {}

-- Single client instance (one in-process server for all scala buffers)
local client_id = nil

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

--- Check whether Metals is attached and initialized for a given buffer
local function metals_ready(bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr })
  for _, c in ipairs(clients) do
    if c.name == 'metals' and c.initialized then
      return true
    end
  end
  return false
end

--- Collect diagnostics and push them back to Neovim via the dispatcher
---@param bufnr integer
---@param dispatchers vim.lsp.rpc.Dispatchers
local function refresh_diagnostics(bufnr, dispatchers)
  if not is_valid_bufnr(bufnr) then
    return
  end

  if not metals_ready(bufnr) then
    logger.info('Metals not ready for buffer ' .. bufnr .. ', skipping diagnostics')
    return
  end

  logger.info('Collecting diagnostics for buffer ' .. bufnr)

  diagnostics_mod.collect_diagnostics(bufnr, function(results)
    if not results or not is_valid_bufnr(bufnr) then
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
        source = diag.source or constants.plugin_name,
      })
    end

    -- Push diagnostics through the dispatcher notification channel.
    -- Neovim will handle them via its built-in publishDiagnostics handler.
    vim.schedule(function()
      if is_valid_bufnr(bufnr) then
        dispatchers.notification('textDocument/publishDiagnostics', {
          uri = vim.uri_from_bufnr(bufnr),
          diagnostics = lsp_diagnostics,
        })
      end
    end)
  end)
end

--- Create the in-process RPC "server".
--- This is passed as the `cmd` field to vim.lsp.start().
--- Neovim calls it with `dispatchers` and expects a PublicClient back.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
function M.rpc_start(dispatchers)
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
          name = constants.client_name,
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
        refresh_diagnostics(bufnr, dispatchers)
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

  client_id = lsp.start({
    name = constants.client_name,
    cmd = M.rpc_start,
    filetypes = { 'scala' },
    root_dir = vim.fn.getcwd(),
    on_attach = function(_, buf)
      logger.info('Client attached to buffer ' .. buf)
    end,
    on_exit = function(code, signal)
      logger.info(('Client exited (code=%s, signal=%s)'):format(code, signal))
      client_id = nil
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
