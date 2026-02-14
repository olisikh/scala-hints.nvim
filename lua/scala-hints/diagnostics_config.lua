local M = {}

local settings = {
  default_severity = vim.diagnostic.severity.HINT,
  overrides = {},
}

local function normalize_severity(value)
  if value == nil then
    return nil
  end

  if type(value) == 'number' then
    return value
  end

  if type(value) ~= 'string' then
    return nil
  end

  local key = string.upper(value)
  if key == 'OFF' or key == 'NONE' then
    return false
  end

  local map = {
    ERROR = vim.diagnostic.severity.ERROR,
    WARN = vim.diagnostic.severity.WARN,
    WARNING = vim.diagnostic.severity.WARN,
    INFO = vim.diagnostic.severity.INFO,
    HINT = vim.diagnostic.severity.HINT,
  }

  return map[key]
end

function M.configure(opts)
  local diagnostics = opts and opts.diagnostics or nil
  if not diagnostics then
    return
  end

  local default_sev = normalize_severity(diagnostics.default_severity)
  if default_sev ~= nil then
    settings.default_severity = default_sev
  end

  if type(diagnostics.overrides) == 'table' then
    settings.overrides = diagnostics.overrides
  end
end

function M.resolve(query_name, query_def)
  local override = settings.overrides and settings.overrides[query_name]
  local override_sev = normalize_severity(override)
  if override_sev ~= nil then
    return override_sev
  end

  local def_sev = query_def and query_def.diagnostic_severity
  local normalized = normalize_severity(def_sev)
  if normalized ~= nil then
    return normalized
  end

  return settings.default_severity
end

return M
