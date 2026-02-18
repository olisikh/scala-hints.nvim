local constants = require('scala-hints.constants')
local client_mod = require('scala-hints.client')

local M = {}

local MAX_ITERATIONS = 50

--- Apply all scala-hints diagnostics in the buffer iteratively.
--- @param bufnr number|nil Buffer number (defaults to current buffer)
--- @param opts table|nil Optional settings
--- @param opts.notify boolean Whether to notify user on completion (default: true)
--- @return table summary { applied: number, remaining: number }
function M.apply_all(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local should_notify = opts.notify ~= false

  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local applied_total = 0
  local iteration = 0
  local remaining = 0

  while iteration < MAX_ITERATIONS do
    iteration = iteration + 1

    local all_diagnostics = vim.diagnostic.get(bufnr)

    local scala_hints_diagnostics = {}
    for _, diag in ipairs(all_diagnostics) do
      if diag.source == constants.plugin_name then
        table.insert(scala_hints_diagnostics, diag)
      end
    end

    if #scala_hints_diagnostics == 0 then
      remaining = 0
      break
    end

    table.sort(scala_hints_diagnostics, function(a, b)
      if a.lnum ~= b.lnum then
        return a.lnum < b.lnum
      end
      return (a.col or 0) < (b.col or 0)
    end)

    local diag = scala_hints_diagnostics[1]
    local applied = M._apply_diagnostic_fix(bufnr, diag)

    if applied then
      applied_total = applied_total + 1
    else
      remaining = #scala_hints_diagnostics
      break
    end

    remaining = #scala_hints_diagnostics - 1
  end

  if should_notify then
    if applied_total > 0 then
      vim.notify(
        string.format('scala-hints: Applied %d fix%s, %d remaining', applied_total, applied_total == 1 and '' or 'es', remaining),
        vim.log.levels.INFO
      )
    else
      vim.notify('scala-hints: No fixes to apply', vim.log.levels.INFO)
    end
  end

  return {
    applied = applied_total,
    remaining = remaining,
  }
end

--- Apply a single diagnostic's fix via LSP code action.
--- @param bufnr number Buffer number
--- @param diag table Diagnostic from vim.diagnostic.get
--- @return boolean success Whether the fix was applied
function M._apply_diagnostic_fix(bufnr, diag)
  local client_id = client_mod.get_client_id()
  if not client_id then
    return false
  end

  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    return false
  end

  local uri = vim.uri_from_bufnr(bufnr)
  local params = {
    textDocument = { uri = uri },
    range = {
      start = { line = diag.lnum, character = diag.col },
      ['end'] = { line = diag.end_lnum or diag.lnum, character = diag.end_col or diag.col },
    },
    context = {
      diagnostics = { diag },
      only = { 'quickfix' },
    },
  }

  local applied = false
  local results = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', params, 5000)

  if results then
    for client_id_str, response in pairs(results) do
      local resp_client_id = tonumber(client_id_str)
      if resp_client_id == client_id and response.result and #response.result > 0 then
        local action = response.result[1]
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, 'UTF-16')
          applied = true
          break
        elseif action.command then
          vim.lsp.buf.execute_command(action.command)
          applied = true
          break
        end
      end
    end
  end

  return applied
end

return M
