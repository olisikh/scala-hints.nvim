local constants = require('scala-hints.constants')
local client = require('scala-hints.client')
local semantic = require('scala-hints.semantic')
local diagnostics = require('scala-hints.diagnostics')
local actions = require('scala-hints.actions')
local logger = require('scala-hints.logger')
local apply_all = require('scala-hints.apply_all')

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
      if vim.bo[bufnr].filetype ~= "scala" then
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
    end,
  })

  vim.api.nvim_create_user_command('ScalaHintsApplyBuffer', function()
    apply_all.apply_all(0)
  end, {
    desc = 'Apply all scala-hints fixes in current buffer',
  })

  logger.info('Plugin initialized')
  return M
end

return M
