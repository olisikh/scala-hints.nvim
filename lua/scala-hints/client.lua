---@diagnostic disable: undefined-global
local vim = vim
local api = vim.api
local lsp = vim.lsp
local constants = require('scala-hints.constants')
local diagnostics = require('scala-hints.diagnostics')
local actions = require('scala-hints.actions')
local logger = require('scala-hints.logger').new('client')

local M = {}

local client_id_by_buf = {}
M.client_id_by_buf = client_id_by_buf

local diag_ns = api.nvim_create_namespace(constants.diagnostic_namespace)

local function is_valid_bufnr(bufnr)
  return type(bufnr) == 'number' and api.nvim_buf_is_valid(bufnr)
end

local function lsp_to_nvim_diagnostic(diagnostic)
  local range = diagnostic.range or {}
  local start_range = range.start or {}
  local end_range = range['end'] or start_range

  return {
    lnum = start_range.line or 0,
    col = start_range.character or 0,
    end_lnum = end_range.line or start_range.line or 0,
    end_col = end_range.character or start_range.character or 0,
    message = diagnostic.message or '',
    severity = diagnostic.severity or vim.diagnostic.severity.HINT,
    source = diagnostic.source or constants.source,
    code = diagnostic.code,
  }
end

local function publish_diagnostics_handler(err, result, ctx)
  if err then
    logger.error('publishDiagnostics error: ' .. vim.inspect(err))
    return
  end

  if not result or not ctx then
    return
  end

  local bufnr = ctx.bufnr or (result.uri and vim.uri_to_bufnr(result.uri))
  if not is_valid_bufnr(bufnr) then
    return
  end

  local lsp_diagnostics = result.diagnostics or {}
  local nvim_diagnostics = {}

  for _, diagnostic in ipairs(lsp_diagnostics) do
    table.insert(nvim_diagnostics, lsp_to_nvim_diagnostic(diagnostic))
  end

  vim.schedule(function()
    if is_valid_bufnr(bufnr) then
      vim.diagnostic.set(diag_ns, bufnr, nvim_diagnostics, ctx.config)
    end
  end)
end

local function code_action_handler(err, params, ctx)
  if err then
    return nil, err
  end

  local bufnr = ctx.bufnr
  if not is_valid_bufnr(bufnr) then
    return nil
  end

  local range = params.range
  local start_line = range.start.line
  local end_line = range['end'].line

  local results = {}
  local done = false

  actions.resolve_actions(bufnr, start_line, end_line, function(action_results)
    if action_results then
      for _, action in ipairs(action_results) do
        table.insert(results, {
          title = action.title,
          kind = 'quickfix',
          edit = {
            changes = {
              [vim.uri_from_bufnr(bufnr)] = {
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
    done = true
  end)

  -- Wait for async completion with timeout
  local attempts = 0
  while not done and attempts < 100 do
    vim.wait(10)
    attempts = attempts + 1
  end

  return results
end

local function nvim_to_lsp_diagnostic(diagnostic)
  if diagnostic.range then
    return diagnostic
  end

  local lnum = diagnostic.lnum or 0
  local col = diagnostic.col or 0
  local end_lnum = diagnostic.end_lnum or lnum
  local end_col = diagnostic.end_col or col

  return {
    range = {
      start = { line = lnum, character = col },
      ['end'] = { line = end_lnum, character = end_col },
    },
    message = diagnostic.message or '',
    severity = diagnostic.severity or vim.diagnostic.severity.HINT,
    source = diagnostic.source or constants.source,
    code = diagnostic.code,
  }
end

function M.publish_diagnostics(bufnr, diagnostics_list)
  if not is_valid_bufnr(bufnr) then
    return
  end

  local client_id = client_id_by_buf[bufnr]
  if not client_id then
    logger.info('No virtual client attached to buffer ' .. bufnr)
    return
  end

  local lsp_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics_list or {}) do
    table.insert(lsp_diagnostics, nvim_to_lsp_diagnostic(diagnostic))
  end

  publish_diagnostics_handler(nil, {
    uri = vim.uri_from_bufnr(bufnr),
    diagnostics = lsp_diagnostics,
  }, {
    client_id = client_id,
    bufnr = bufnr,
  })
end

function M.collect_and_publish(bufnr)
  if not is_valid_bufnr(bufnr) then
    return
  end

  diagnostics.collect_diagnostics(bufnr, function(results)
    if not results then
      return
    end

    if is_valid_bufnr(bufnr) then
      M.publish_diagnostics(bufnr, results)
    end
  end)
end

local function clear_buf(bufnr, client_id)
  if client_id_by_buf[bufnr] == client_id or client_id == nil then
    client_id_by_buf[bufnr] = nil
  end
end

function M.start_virtual_client(bufnr)
  if not is_valid_bufnr(bufnr) then
    logger.info('Invalid buffer provided to start_virtual_client: ' .. tostring(bufnr))
    return
  end

  local existing_client_id = client_id_by_buf[bufnr]
  if existing_client_id then
    local existing_client = lsp.get_client_by_id(existing_client_id)
    if existing_client then
      if lsp.buf_is_attached and not lsp.buf_is_attached(bufnr, existing_client_id) then
        lsp.buf_attach_client(bufnr, existing_client_id)
        logger.info('Re-attached virtual client ' .. existing_client_id .. ' to buffer ' .. bufnr)
      else
        logger.info('Virtual client already attached to buffer ' .. bufnr)
      end
      return existing_client_id
    else
      logger.info('Stale virtual client id for buffer ' .. bufnr .. ', restarting')
      client_id_by_buf[bufnr] = nil
    end
  end

  logger.info('Starting virtual LSP client for buffer ' .. bufnr)

  local client_id = lsp.start_client({
    name = constants.client_name,
    capabilities = constants.capabilities,
    handlers = {
      ['textDocument/publishDiagnostics'] = publish_diagnostics_handler,
      ['textDocument/codeAction'] = code_action_handler,
    },
    on_attach = function(_, buf)
      logger.info('Virtual client attached to buffer ' .. buf)
    end,
    on_exit = function(code, signal, stopped_client_id)
      logger.info(('Virtual client exited (code=%s, signal=%s)'):format(code, signal))
      for buf, id in pairs(client_id_by_buf) do
        if id == stopped_client_id then
          client_id_by_buf[buf] = nil
        end
      end
    end,
  })

  if client_id then
    lsp.buf_attach_client(bufnr, client_id)
    client_id_by_buf[bufnr] = client_id
    logger.info('Virtual client ' .. client_id .. ' attached to buffer ' .. bufnr)
  else
    logger.error('Failed to start virtual client')
  end

  return client_id
end

function M.stop_virtual_client(bufnr)
  if not bufnr then
    return
  end

  local client_id = client_id_by_buf[bufnr]
  if not client_id then
    return
  end

  logger.info('Stopping virtual client ' .. client_id .. ' for buffer ' .. bufnr)
  lsp.stop_client(client_id)
  clear_buf(bufnr, client_id)
end

function M.handle_lsp_attach(args)
  if not args or not args.buf then
    return
  end

  return M.start_virtual_client(args.buf)
end

function M.handle_buf_cleanup(args)
  if not args or not args.buf then
    return
  end

  M.stop_virtual_client(args.buf)
end

function M.get_client_id(bufnr)
  return client_id_by_buf[bufnr]
end

return M
