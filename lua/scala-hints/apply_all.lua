local constants = require('scala-hints.constants')
local client_mod = require('scala-hints.client')

local M = {}

--- Check if two ranges overlap
local function ranges_overlap(r1, r2)
  -- r1 is entirely before r2
  if r1.end_line < r2.start_line then
    return false
  end
  -- r1 is entirely after r2
  if r1.start_line > r2.end_line then
    return false
  end
  -- Same line - check columns
  if r1.start_line == r2.end_line and r1.end_col < r2.start_col then
    return false
  end
  if r1.end_line == r2.start_line and r1.start_col > r2.end_col then
    return false
  end
  return true
end

--- Apply all scala-hints diagnostics in the buffer.
--- Collects all code actions first, then applies non-overlapping edits
--- in reverse order (bottom to top).
--- @param bufnr number|nil Buffer number (defaults to current buffer)
--- @param opts table|nil Optional settings
--- @param opts.notify boolean Whether to notify user on completion (default: true)
--- @return table summary { applied: number, remaining: number }
function M.run(bufnr, opts)
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

  table.sort(scala_hints_diagnostics, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return (a.col or 0) < (b.col or 0)
  end)

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
            local file_edits = action.edit.changes[uri]
            if file_edits then
              for _, text_edit in ipairs(file_edits) do
                table.insert(edits, {
                  range = text_edit.range,
                  newText = text_edit.newText,
                  start_line = text_edit.range.start.line,
                  start_col = text_edit.range.start.character,
                  end_line = text_edit.range['end'].line,
                  end_col = text_edit.range['end'].character,
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

  table.sort(edits, function(a, b)
    if a.start_line ~= b.start_line then
      return a.start_line > b.start_line
    end
    return a.start_col > b.start_col
  end)

  -- Track modified ranges and skip overlapping edits
  local applied_edits = {}
  local skipped = 0

  for _, edit in ipairs(edits) do
    local overlaps = false
    for _, applied in ipairs(applied_edits) do
      if ranges_overlap(
        { start_line = edit.start_line, start_col = edit.start_col, end_line = edit.end_line, end_col = edit.end_col },
        { start_line = applied.start_line, start_col = applied.start_col, end_line = applied.end_line, end_col = applied.end_col }
      ) then
        overlaps = true
        break
      end
    end

    if not overlaps then
      local start_row = edit.start_line
      local start_col = edit.start_col
      local end_row = edit.end_line
      local end_col = edit.end_col
      local text = vim.split(edit.newText, '\n', { plain = true })

      local lines = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)
      local max_col = lines[1] and #lines[1] or 0
      end_col = math.min(end_col, max_col)

      vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, text)
      table.insert(applied_edits, edit)
    else
      skipped = skipped + 1
    end
  end

  vim.diagnostic.reset(vim.api.nvim_create_namespace('scala-hints'), bufnr)

  local applied = #applied_edits
  if should_notify then
    if skipped > 0 then
      vim.notify(
        string.format('scala-hints: Applied %d fix%s, %d skipped (overlapping)', applied, applied == 1 and '' or 'es', skipped),
        vim.log.levels.INFO
      )
    else
      vim.notify(
        string.format('scala-hints: Applied %d fix%s', applied, applied == 1 and '' or 'es'),
        vim.log.levels.INFO
      )
    end
  end

  return { applied = applied, remaining = skipped }
end

return M
