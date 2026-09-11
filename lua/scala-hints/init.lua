local client = require('scala-hints.client')
local semantic = require('scala-hints.semantic')
local diagnostics = require('scala-hints.diagnostics')
local actions = require('scala-hints.actions')
local logger = require('scala-hints.logger')
local apply_all = require('scala-hints.apply_all')
local workspace = require('scala-hints.workspace')

local M = {}

--- Function to instantiate the plugin
---@param opts table|nil options
---@return table plugin object
M.setup = function(opts)
  logger.configure(opts)

  logger = logger.new('init')
  logger.info('Module initializing')

  semantic.configure(opts)
  diagnostics.configure(opts)
  actions.configure(opts)

  -- Listen for Metals attaching to Scala buffers.
  -- When Metals is ready we start (or reuse) our in-process LSP client
  -- and attach it to the same buffer.
  local group = vim.api.nvim_create_augroup('ScalaHints', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(event)
      local bufnr = event.buf
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      -- Only act on Scala buffers
      if vim.bo[bufnr].filetype ~= 'scala' then
        return
      end

      -- Only act when Metals attaches
      local attached_client_id = event.data and event.data.client_id
      local attached_client = attached_client_id and vim.lsp.get_client_by_id(attached_client_id)
      if not attached_client or attached_client.name ~= 'metals' then
        return
      end

      logger.info('Metals attached to buffer ' .. bufnr .. ', starting scala-hints client')
      client.start(bufnr)
      workspace.start(bufnr, attached_client)
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(event)
      workspace.refresh_buffer(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      workspace.forget_buffer(event.buf)
    end,
  })

  vim.api.nvim_create_user_command('ScalaHintsApplyBuffer', function()
    apply_all.run(0)
  end, {
    desc = 'Apply all scala-hints fixes in current buffer',
  })

  vim.api.nvim_create_user_command('ScalaHintsWorkspaceRefresh', function()
    workspace.refresh_all()
  end, {
    desc = 'Re-index workspace Scala diagnostics',
    force = true,
  })

  vim.api.nvim_create_user_command('ScalaHintsWorkspaceCancel', function()
    workspace.cancel_all()
  end, {
    desc = 'Cancel workspace Scala diagnostics indexing',
    force = true,
  })

  logger.info('Plugin initialized')
  return M
end

return M
