local log_dir = '/tmp/scala-hints/log'
local dir_initialized = false

local LEVELS = {
  info = { name = 'INFO', value = vim.log.levels.INFO },
  warn = { name = 'WARN', value = vim.log.levels.WARN },
  error = { name = 'ERROR', value = vim.log.levels.ERROR },
}

local logger = {}

local function ensure_log_dir()
  if dir_initialized then
    return true
  end

  local stat = vim.loop.fs_stat(log_dir)
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

local function write_line(name, level_name, message)
  local path = log_path()
  local bufnr = vim.api.nvim_get_current_buf()
  local timestamp = os.date('%Y-%m-%d %H:%M:%S')
  local formatted = string.format('%s [%s] (%s) %s - %s\n', timestamp, level_name, bufnr, name, message)
  local fd = vim.loop.fs_open(path, 'a', 420)
  if not fd then
    return
  end

  vim.loop.fs_write(fd, formatted, -1)
  vim.loop.fs_close(fd)
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
  local logger_name = name or 'scala-hints'

  local function log(level_info)
    return function(message)
      local text = flatten_message(message)
      write_line(logger_name, level_info.name, text)
    end
  end

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
