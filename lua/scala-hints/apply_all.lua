local constants = require('scala-hints.constants')
local client_mod = require('scala-hints.client')

local M = {}

--- Apply all scala-hints diagnostics in the buffer.
--- Collects all code actions first, then applies them in reverse order
--- (bottom to top) to avoid position shifts.
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

  local client_id = client_mod.get_client_id()
  if not client_id then
    if should_notify then
      vim.notify('scala-hints: Client not running', vim.log.levels.WARN)
    end
    return { applied = 0, remaining = 0 }
  end

  -- Get all scala-hints diagnostics
  local all_diagnostics = vim.diagnostic.get(bufnr)
  local scala_hints_diagnostics = {}
  for _, diag in ipairs(all_diagnostics) do
    if diag.source == constants.plugin_name then
      table.insert(scala_hints_diagnostics, diag)
    end
  end

  if #scala_hints_diagnostics == 0 then
    if should_notify then
      vim.notify('scala-hints: No fixes to apply', vim.log.levels.INFO)
    end
    return { applied = 0, remaining = 0 }
  end

  -- Sort by line (ascending) for consistent ordering
  table.sort(scala_hints_diagnostics, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return (a.col or 0) < (b.col or 0)
  end)

  -- Collect all code actions
  local edits = {}
  local uri = vim.uri_from_bufnr(bufnr)

  for _, diag in ipairs(scala_hints_diagnostics) do
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

    local results = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', params, 5000)

    if results then
      for client_id_str, response in pairs(results) do
        local resp_client_id = tonumber(client_id_str)
        if resp_client_id == client_id and response.result and #response.result > 0 then
          local action = response.result[1]
          if action.edit and action.edit.changes then
            -- Extract the text edit for this file
            local file_edits = action.edit.changes[uri]
            if file_edits then
              for _, text_edit in ipairs(file_edits) do
                table.insert(edits, {
                  range = text_edit.range,
                  newText = text_edit.newText,
                  lnum = diag.lnum,
                  col = diag.col,
                })
              end
            end
          end
          break
        end
      end
    end
  end

  if #edits == 0 then
    if should_notify then
      vim.notify('scala-hints: No fixes to apply', vim.log.levels.INFO)
    end
    return { applied = 0, remaining = #scala_hints_diagnostics }
  end

  -- Sort edits by position (descending - bottom to top)
  -- This ensures earlier edits don't shift positions of later edits
  table.sort(edits, function(a, b)
    if a.range.start.line ~= b.range.start.line then
      return a.range.start.line > b.range.start.line
    end
    return a.range.start.character > b.range.start.character
  end)

  -- Apply all edits
  local applied = 0
  for _, edit in ipairs(edits) do
    local start_row = edit.range.start.line
    local start_col = edit.range.start.character
    local end_row = edit.range['end'].line
    local end_col = edit.range['end'].character
    local text = vim.split(edit.newText, '\n', { plain = true })

    -- Get current line for column bounds check
    local lines = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)
    local max_col = lines[1] and #lines[1] or 0
    end_col = math.min(end_col, max_col)

    vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, text)
    applied = applied + 1
  end

  -- Clear scala-hints diagnostics after applying fixes
  vim.diagnostic.reset(vim.api.nvim_create_namespace('scala-hints'), bufnr)

  if should_notify then
    vim.notify(
      string.format('scala-hints: Applied %d fix%s', applied, applied == 1 and '' or 'es'),
      vim.log.levels.INFO
    )
  end

  return { applied = applied, remaining = 0 }
end

return M
