local constants = require('scala-hints.constants')
local client = require('scala-hints.client')
local logger = require('scala-hints.logger').new('init')

local M = {}

--- Function to instantiate the plugin
---@param _opts table|nil options (reserved for future use)
---@return table plugin object
M.setup = function(_opts)
  logger.info('Module initializing')

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
      if vim.bo[bufnr].filetype ~= constants.lang then
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

  logger.info('Plugin initialized')
  return M
end

return M
