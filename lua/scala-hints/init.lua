local vim = vim
local constants = require('scala-hints.constants')
local diagnostics = require('scala-hints.diagnostics')
local actions = require('scala-hints.actions')
local logger = require('scala-hints.logger').new('init')
local async = require('plenary.async')

local M = {}

local diag_ns

local function to_code_action_entry(action, bufnr)
  if not (action and action.title and bufnr) then
    return nil
  end

  return {
    title = action.title,
    kind = 'refactor',
    command = {
      title = action.title,
      command = 'scala-hints.apply',
      arguments = {
        action.replacement,
        bufnr,
        action.range,
      },
    },
  }
end

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
local function configure_code_action_handler()
  if code_action_configured then
    return
  end

  logger.info('Registering code actions apply command (whatever that is)')

  code_action_configured = true
  register_apply_command()

  local original_handler = vim.lsp.handlers['textDocument/codeAction']
  logger.info('Original handler before override: ' .. (original_handler and 'exists' or 'nil'))
  
  vim.lsp.handlers['textDocument/codeAction'] = function(err, result, ctx, config)
    logger.info('HANDLER INVOKED: textDocument/codeAction')
    logger.info('Resolving code actions')

    local merged = {}
    local seen_titles = {}

    if vim.tbl_islist(result) then
      for _, entry in ipairs(result) do
        table.insert(merged, entry)
        if type(entry) == 'table' and entry.title then
          seen_titles[entry.title] = true
        end
      end
    end

    local function append_scala_actions(actions_list)
      local resolved_count = actions_list and #actions_list or 0
      logger.info('Resolved ' .. resolved_count .. ' code actions')

      if actions_list and vim.tbl_islist(actions_list) then
        for _, action in ipairs(actions_list) do
          if action and action.title and not seen_titles[action.title] then
            local entry = to_code_action_entry(action, ctx and ctx.bufnr)
            if entry then
              table.insert(merged, entry)
              seen_titles[action.title] = true
            end
          end
        end
      end

      if original_handler then
        original_handler(err, merged, ctx, config)
      end
    end

    if not (ctx and ctx.bufnr and ctx.params and ctx.params.range) then
      append_scala_actions(nil)
      return
    end

    local bufnr = ctx.bufnr
    if not vim.api.nvim_buf_is_valid(bufnr) then
      append_scala_actions(nil)
      return
    end

    local request_range = ctx.params.range

    actions.resolve_actions(bufnr, request_range.start.line, request_range['end'].line, append_scala_actions)
  end
end

local function ensure_diag_ns()
  if diag_ns then
    return diag_ns
  end

  diag_ns = vim.api.nvim_create_namespace(constants.diagnostic_namespace)
  M.diag_ns = diag_ns

  configure_code_action_handler()

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

      for _, client in ipairs(clients) do
        if client.name == 'metals' and client.initialized then
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
---@param opts table|nil options (reserved for future use)
---@return table plugin object
M.setup = function(_opts)
  logger.info('Module initializing')
  ensure_diag_ns()
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

    local buf_filetype = vim.api.nvim_buf_get_option(event.buf, 'filetype')
    if buf_filetype == 'scala' then
      logger.info('First Scala LSP attach detected, auto-initializing plugin')
      auto_setup_done = true
      M.setup()
    end
  end,
})

return M
