local constants = require('scala-hints.constants')
local log_dir = '/tmp/' .. constants.client_name .. '/log'
local dir_initialized = false

local LEVELS = {
  debug = { name = 'DEBUG', value = vim.log.levels.DEBUG },
  info = { name = 'INFO', value = vim.log.levels.INFO },
  warn = { name = 'WARN', value = vim.log.levels.WARN },
  error = { name = 'ERROR', value = vim.log.levels.ERROR },
}

local settings = {
  enabled = true,
  level = LEVELS.info.name,
}

local logger = {}

function logger.configure(opts)
  local logging = opts and opts.logging or nil
  if not logging then
    return
  end

  if type(logging.enabled) == 'boolean' then
    settings.enabled = logging.enabled
  end

  if type(logging.level) == 'string' then
    local level_key = string.lower(logging.level)
    if LEVELS[level_key] then
      settings.level = LEVELS[level_key].name
    end
  end
end

local function ensure_log_dir()
  if dir_initialized then
    return true
  end

  local stat = vim.uv.fs_stat(log_dir)
  if not stat then
    vim.fn.mkdir(log_dir, 'p')
  end

  dir_initialized = true
  return true
end

local function log_path()
  ensure_log_dir()
  local date = os.date('%Y-%m-%d')
  return string.format('%s/%s.log', log_dir, date)
end

local function write_line(name, level_name, message, opts)
  if not settings.enabled then
    return
  end

  if LEVELS[string.lower(level_name)].value < LEVELS[string.lower(settings.level)].value then
    return
  end

  local path = log_path()
  local bufnr = opts and opts.bufnr or vim.api.nvim_get_current_buf()
  local file = opts and opts.file or vim.api.nvim_buf_get_name(bufnr)
  if file == nil or file == '' then
    file = 'unknown'
  end
  local timestamp = os.date('%Y-%m-%d %H:%M:%S')
  local formatted =
    string.format('%s [%s] (bufnr=%s file=%s) %s - %s\n', timestamp, level_name, bufnr, file, name, message)
  local fd = vim.uv.fs_open(path, 'a', 420)
  if not fd then
    return
  end

  vim.uv.fs_write(fd, formatted, -1)
  vim.uv.fs_close(fd)
end

local function flatten_message(message)
  if message == nil then
    return ''
  end

  if type(message) == 'table' then
    return vim.inspect(message)
  end

  return tostring(message)
end

local function make_logger(name)
  local meta = {}
  local logger_name = name or constants.plugin_name

  local function log(level_info)
    return function(message, opts)
      local text = flatten_message(message)
      write_line(logger_name, level_info.name, text, opts)
    end
  end

  meta.debug = log(LEVELS.debug)
  meta.info = log(LEVELS.info)
  meta.warn = log(LEVELS.warn)
  meta.error = log(LEVELS.error)
  meta.name = logger_name
  return meta
end

function logger.new(name)
  return make_logger(name)
end

return logger
