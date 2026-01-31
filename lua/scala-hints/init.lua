local null_ls = require('null-ls')
local constants = require('scala-hints.constants')

local lang = constants.lang
local source = constants.source

local diagnostics = require('scala-hints.diagnostics')
local actions = require('scala-hints.actions')

local M = {}

M.attach = function(buf)
  null_ls.register({
    name = source,
    method = null_ls.methods.DIAGNOSTICS,
    filetypes = { lang },
    generator = {
      async = true,
      fn = function(context, done)
        -- vim.print(context)

        local bufnr = context.bufnr
        local method = context.lsp_method
        -- local content = context.lsp_params.textDocument.text

        -- vim.print(method)
        -- vim.print(context)

        diagnostics.collect_diagnostics(bufnr, done)
      end,
    },
  })

  null_ls.register({
    name = source,
    method = null_ls.methods.CODE_ACTION,
    filetypes = { lang },
    generator = {
      async = true,
      fn = function(context, done)
        -- vim.print(context)

        local bufnr = context.bufnr
        local range = context.lsp_params.range

        local start_row = range['start'].line
        local start_col = range['start'].character
        local end_row = range['end'].line
        local end_col = range['end'].character

        actions.resolve_actions(bufnr, start_row, end_row, done)
      end,
    },
  })
end

return M
