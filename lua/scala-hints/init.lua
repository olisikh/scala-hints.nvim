local vim = _G.vim
local constants = require('scala-hints.constants')
local diagnostics = require('scala-hints.diagnostics')
local actions = require('scala-hints.actions')
local client = require('scala-hints.client')
local logger = require('scala-hints.logger').new('init')

local M = {}

local diag_ns
local lifecycle_autocmds_configured = false
local lifecycle_group

local function register_apply_command()
  vim.lsp.commands['scala-hints.apply'] = function(command)
    local args = command.arguments or {}
    local replacement = args[1]
    local bufnr = args[2]
    local range = args[3]

    if type(replacement) ~= 'string' or type(bufnr) ~= 'number' or type(range) ~= 'table' then
      return
    end

    local start_range = range.start
    local end_range = range['end']

    if
      type(start_range) ~= 'table'
      or type(end_range) ~= 'table'
      or type(start_range.line) ~= 'number'
      or type(start_range.character) ~= 'number'
      or type(end_range.line) ~= 'number'
      or type(end_range.character) ~= 'number'
    then
      return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    vim.api.nvim_buf_set_text(
      bufnr,
      start_range.line,
      start_range.character,
      end_range.line,
      end_range.character,
      { replacement }
    )
  end
end

local code_action_configured = false
local function setup_code_actions()
  if code_action_configured then
    return
  end

  logger.info('Registering scala-hints code actions')

  code_action_configured = true
  register_apply_command()

  vim.lsp.buf.code_action = function(_)
    local bufnr = vim.api.nvim_get_current_buf()
    logger.info('vim.lsp.buf.code_action called for buffer ' .. bufnr)

    if not vim.api.nvim_buf_is_valid(bufnr) then
      logger.info('Buffer is not valid')
      return
    end

    local params = vim.lsp.util.make_range_params()
    if not params.range then
      logger.info('No range available')
      return
    end

    params.context = {
      diagnostics = vim.diagnostic.get(bufnr),
    }

    local start_line = params.range.start.line
    local end_line = params.range['end'].line

    local items = {}
    local pending_requests = 0

    local function show_code_actions()
      if #items > 0 then
        vim.ui.select(items, {
          prompt = 'Code Actions:',
          format_item = function(item)
            return '[' .. item.source .. '] ' .. item.title
          end,
        }, function(selected)
          if selected then
            if selected.is_scala_hints then
              logger.info('Applying scala-hints action: ' .. selected.title)
              vim.api.nvim_buf_set_text(
                bufnr,
                selected.range.start.line,
                selected.range.start.character,
                selected.range['end'].line,
                selected.range['end'].character,
                { selected.replacement }
              )
            elseif selected.is_lsp then
              logger.info('Executing ' .. selected.source .. ' action: ' .. selected.title)
              logger.info('Action details: command=' .. vim.inspect(selected.command) .. ', edit=' .. vim.inspect(selected.edit))

              if selected.edit then
                logger.info('Applying workspace edit')
                vim.lsp.util.apply_workspace_edit(selected.edit, selected.client.offset_encoding or 'utf-16')
              elseif selected.command then
                logger.info('Executing command: ' .. vim.inspect(selected.command))
                vim.lsp.buf.execute_command(selected.command)
              end
            end
          end
        end)
      else
        vim.notify('No code actions available', vim.log.levels.INFO)
      end
    end

    actions.resolve_actions(bufnr, start_line, end_line, function(scala_actions)
      logger.info('Resolved ' .. (scala_actions and #scala_actions or 0) .. ' scala-hints code actions')

      if scala_actions then
        for _, action in ipairs(scala_actions) do
          table.insert(items, {
            title = action.title,
            range = action.range,
            replacement = action.replacement,
            source = 'scala-hints',
            is_scala_hints = true,
          })
        end
      end

      local clients = vim.lsp.get_clients({ bufnr = bufnr })
      logger.info('Found ' .. #clients .. ' LSP clients')

      for _, lsp_client in ipairs(clients) do
        if lsp_client.supports_method('textDocument/codeAction') then
          pending_requests = pending_requests + 1
          logger.info('Requesting code actions from ' .. lsp_client.name)

          lsp_client.request('textDocument/codeAction', params, function(err, lsp_actions)
            if err then
              logger.info('Error from ' .. lsp_client.name .. ': ' .. vim.inspect(err))
            elseif lsp_actions and vim.tbl_islist(lsp_actions) then
              logger.info(lsp_client.name .. ' returned ' .. #lsp_actions .. ' code actions')
              for _, action in ipairs(lsp_actions) do
                if type(action) == 'table' and action.title then
                  logger.info('Action from ' .. lsp_client.name .. ': ' .. vim.inspect(action))
                  table.insert(items, {
                    title = action.title,
                    command = action.command,
                    edit = action.edit,
                    client = lsp_client,
                    source = lsp_client.name,
                    is_lsp = true,
                  })
                end
              end
            end

            pending_requests = pending_requests - 1
            if pending_requests == 0 then
              show_code_actions()
            end
          end)
        end
      end

      if pending_requests == 0 then
        show_code_actions()
      end
    end)
  end
end

local function setup_lifecycle_autocmds()
  if lifecycle_autocmds_configured then
    return
  end

  lifecycle_autocmds_configured = true
  lifecycle_group = vim.api.nvim_create_augroup('ScalaHintsLspLifecycle', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = lifecycle_group,
    callback = function(args)
      local client_id = args.data and args.data.client_id
      if not client_id then
        return
      end

      local lsp_client = vim.lsp.get_client_by_id(client_id)
      if not lsp_client or lsp_client.name ~= 'metals' then
        return
      end

      local bufnr = args.buf
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
      if filetype ~= constants.lang then
        return
      end

      logger.info('Metals attached to buffer ' .. bufnr .. ', starting scala-hints virtual client')
      client.start_virtual_client(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufUnload' }, {
    group = lifecycle_group,
    callback = function(args)
      local bufnr = args.buf
      if not bufnr then
        return
      end

      if client.get_client_id(bufnr) then
        logger.info('Buffer ' .. bufnr .. ' unloaded, stopping scala-hints virtual client')
      end

      client.stop_virtual_client(bufnr)
    end,
  })
end

local function ensure_diag_ns()
  if diag_ns then
    return diag_ns
  end

  diag_ns = vim.api.nvim_create_namespace(constants.diagnostic_namespace)
  M.diag_ns = diag_ns

  setup_code_actions()

  local diag_group = vim.api.nvim_create_augroup('ScalaHintsDiagnostics', { clear = true })

  logger.info('Registering auto commands to produce diagnostics and code actions')

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufUnload' }, {
    group = diag_group,
    pattern = '*.scala',
    callback = function(args)
      local bufnr = args.buf
      if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      logger.info('Resetting diagnostics')

      vim.diagnostic.reset(diag_ns, bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufEnter' }, {
    group = diag_group,
    pattern = '*.scala',
    callback = function(args)
      logger.info('BufWritePost BufEnter stuff')

      local bufnr = args.buf
      if bufnr == nil or not vim.api.nvim_buf_is_loaded(bufnr) then
        return
      end

      local clients = vim.lsp.get_clients({ bufnr = bufnr })
      local metals_ready = false

      for _, lsp_client in ipairs(clients) do
        if lsp_client.name == 'metals' and lsp_client.initialized then
          metals_ready = true
          break
        end
      end

      if not metals_ready then
        return
      end

      logger.info('Collecting fresh diagnostics')

      vim.diagnostic.reset(diag_ns, bufnr)

      diagnostics.collect_diagnostics(bufnr, function(results)
        local diagnostics_count = results and #results or 0
        logger.info('Collected ' .. diagnostics_count .. ' diagnostics')

        if not vim.api.nvim_buf_is_valid(bufnr) or not results then
          return
        end

        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.diagnostic.set(diag_ns, bufnr, results)
          end
        end)
      end)
    end,
  })

  return diag_ns
end

--- Function to instantiate necessary namespace and autocommands
---@param _opts table|nil options (reserved for future use)
---@return table plugin object
M.setup = function(_opts)
  logger.info('Module initializing')
  ensure_diag_ns()
  setup_lifecycle_autocmds()
  logger.info('Handler registered: ' .. (vim.lsp.handlers['textDocument/codeAction'] and 'yes' or 'NO'))
  return M
end

-- Auto-initialize on first LspAttach to a Scala file
-- This ensures the handler is registered after Metals is ready
local auto_setup_done = false
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('ScalaHintsAutoSetup', { clear = true }),
  callback = function(event)
    if auto_setup_done then
      return
    end

    local bufnr = event.buf
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local buf_filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
    if buf_filetype ~= constants.lang then
      return
    end

    local attached_client_id = event.data and event.data.client_id
    local attached_client = attached_client_id and vim.lsp.get_client_by_id(attached_client_id)
    if not attached_client or attached_client.name ~= 'metals' then
      return
    end

    logger.info('First Metals attach to Scala buffer detected, auto-initializing plugin')
    auto_setup_done = true
    M.setup()
    client.start_virtual_client(bufnr)
  end,
})

return M
