--- Workspace-wide Scala diagnostics coordinator.
---
--- Once Metals is ready, this module loads Scala files as hidden buffers and
--- runs scala-hints one at a time. Keeping the buffers loaded lets Neovim's
--- normal diagnostic store expose results to workspace UIs such as Trouble.
local api = vim.api
local lsp = vim.lsp
local uv = vim.uv

local client = require('scala-hints.client')
local logger = require('scala-hints.logger').new('workspace')

local M = {}

local coordinators = {}
local ignored_directories = {
  ['.git'] = true,
  ['.bloop'] = true,
  ['.metals'] = true,
  ['.scala-build'] = true,
  ['.idea'] = true,
  ['node_modules'] = true,
  ['target'] = true,
}

local function is_valid_buffer(bufnr)
  return type(bufnr) == 'number' and api.nvim_buf_is_valid(bufnr)
end

local function normalize_path(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

local function is_within_root(path, root)
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

local function root_for_client(metals, bufnr)
  if metals.workspace_folders and metals.workspace_folders[1] then
    local uri = metals.workspace_folders[1].uri
    if uri then
      return normalize_path(vim.uri_to_fname(uri))
    end
  end

  local root_dir = metals.config and metals.config.root_dir
  if type(root_dir) == 'string' and root_dir ~= '' then
    return normalize_path(root_dir)
  end

  local name = api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    return normalize_path(vim.fs.dirname(name))
  end

  return normalize_path(vim.fn.getcwd())
end

local function metals_ready(coordinator)
  local metals = lsp.get_client_by_id(coordinator.metals_client_id)
  if not metals or metals:is_stopped() or not metals.initialized then
    return false
  end

  return type(vim.g.metals_status) ~= 'string' or vim.g.metals_status == ''
end

local function is_scala_file(path)
  return path:sub(-6) == '.scala'
end

local function should_ignore(path)
  for segment in path:gmatch('[^/]+') do
    if ignored_directories[segment] then
      return true
    end
  end
  return false
end

local function discover_files(root, done)
  local directories = { root }
  local files = {}

  local function scan_next()
    local directory = table.remove(directories)
    if not directory then
      done(files)
      return
    end

    local handle = uv.fs_scandir(directory)
    if handle then
      while true do
        local name, file_type = uv.fs_scandir_next(handle)
        if not name then
          break
        end

        local path = directory .. '/' .. name
        if file_type == 'directory' then
          if not ignored_directories[name] then
            table.insert(directories, path)
          end
        elseif file_type == 'file' and is_scala_file(path) and not should_ignore(path) then
          table.insert(files, normalize_path(path))
        end
      end
    end

    -- Yield once per directory so discovery does not monopolize the UI loop.
    vim.schedule(scan_next)
  end

  scan_next()
end

local function load_managed_buffer(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)

  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = 'scala'
  vim.b[bufnr].scala_hints_workspace_managed = true

  return bufnr
end

local function attach_clients(coordinator, bufnr)
  local metals = lsp.get_client_by_id(coordinator.metals_client_id)
  if not metals or metals:is_stopped() then
    return false
  end

  if not lsp.buf_is_attached(bufnr, metals.id) then
    lsp.buf_attach_client(bufnr, metals.id)
  end

  return client.start(bufnr) ~= nil
end

local function enqueue(coordinator, path, priority)
  local entry = coordinator.entries[path]
  if not entry then
    entry = { generation = 0 }
    coordinator.entries[path] = entry
  end

  entry.generation = entry.generation + 1
  if entry.running then
    entry.pending = true
    return
  end

  if entry.queued then
    return
  end

  entry.queued = true
  if priority then
    table.insert(coordinator.queue, 1, path)
  else
    table.insert(coordinator.queue, path)
  end
end

local function drain(coordinator)
  if coordinator.running or coordinator.cancelled or not metals_ready(coordinator) then
    return
  end

  local path = table.remove(coordinator.queue, 1)
  if not path then
    return
  end

  local entry = coordinator.entries[path]
  if not entry then
    vim.schedule(function()
      drain(coordinator)
    end)
    return
  end

  entry.queued = false
  entry.running = true
  local generation = entry.generation
  coordinator.running = path

  local bufnr = load_managed_buffer(path)
  if not attach_clients(coordinator, bufnr) then
    entry.running = false
    coordinator.running = nil
    logger.warn('Unable to attach clients for ' .. path, { bufnr = bufnr })
    vim.schedule(function()
      drain(coordinator)
    end)
    return
  end

  client.refresh_diagnostics(bufnr, {
    wait_for_metals = true,
    is_current = function()
      return not coordinator.cancelled and entry.generation == generation
    end,
    on_complete = function()
      entry.running = false
      coordinator.running = nil

      if entry.pending then
        entry.pending = false
        entry.queued = true
        table.insert(coordinator.queue, 1, path)
      end

      vim.schedule(function()
        drain(coordinator)
      end)
    end,
  })
end

local function start_when_ready(coordinator)
  if coordinator.cancelled then
    return
  end

  if not metals_ready(coordinator) then
    vim.defer_fn(function()
      start_when_ready(coordinator)
    end, 2000)
    return
  end

  if coordinator.discovery_started then
    return
  end
  coordinator.discovery_started = true

  logger.info('Discovering Scala files under ' .. coordinator.root)
  discover_files(coordinator.root, function(files)
    if coordinator.cancelled then
      return
    end

    local queued = 0
    for _, path in ipairs(files) do
      -- Buffers that were already opened normally have their own didOpen
      -- refresh; avoid duplicating that work in the background queue.
      local existing = vim.fn.bufnr(path, false)
      if existing == -1 or vim.b[existing].scala_hints_workspace_managed then
        enqueue(coordinator, path, false)
        queued = queued + 1
      end
    end
    logger.info(string.format('Queued %d Scala files under %s', queued, coordinator.root))
    drain(coordinator)
  end)
end

local function update_metals_client(coordinator, metals_client_id)
  local changed = coordinator.metals_client_id ~= metals_client_id
  coordinator.metals_client_id = metals_client_id
  coordinator.cancelled = false

  if changed then
    -- A new Metals client has a fresh document/indexing lifecycle. Re-run
    -- discovery so every completed file is queued against the new client.
    coordinator.discovery_started = false
  end

  return changed
end

--- Start (or reuse) automatic indexing for the Metals workspace of a buffer.
---@param bufnr integer
---@param metals_client vim.lsp.Client
function M.start(bufnr, metals_client)
  if not metals_client then
    return
  end

  local root = root_for_client(metals_client, bufnr)
  local coordinator = coordinators[root]
  if not coordinator then
    coordinator = {
      root = root,
      metals_client_id = metals_client.id,
      queue = {},
      entries = {},
      cancelled = false,
      discovery_started = false,
    }
    coordinators[root] = coordinator
  else
    update_metals_client(coordinator, metals_client.id)
  end

  start_when_ready(coordinator)
end

--- Queue a priority refresh for an indexed buffer when it is opened or saved.
---@param bufnr integer
function M.refresh_buffer(bufnr)
  if not is_valid_buffer(bufnr) or not vim.b[bufnr].scala_hints_workspace_managed then
    return
  end

  local path = api.nvim_buf_get_name(bufnr)
  if path == '' then
    return
  end
  path = normalize_path(path)

  for _, coordinator in pairs(coordinators) do
    if is_within_root(path, coordinator.root) then
      enqueue(coordinator, path, true)
      drain(coordinator)
      return
    end
  end
end

function M.cancel_all()
  for _, coordinator in pairs(coordinators) do
    coordinator.cancelled = true
    coordinator.queue = {}
    for _, entry in pairs(coordinator.entries) do
      entry.queued = false
      entry.pending = false
    end
  end
  logger.info('Cancelled workspace diagnostics')
end

function M.refresh_all()
  for _, coordinator in pairs(coordinators) do
    coordinator.cancelled = false
    coordinator.discovery_started = false
    start_when_ready(coordinator)
  end
end

function M.forget_buffer(bufnr)
  if not is_valid_buffer(bufnr) then
    return
  end

  local path = api.nvim_buf_get_name(bufnr)
  if path == '' then
    return
  end
  path = normalize_path(path)

  for _, coordinator in pairs(coordinators) do
    coordinator.entries[path] = nil
  end
end

function M.is_managed(bufnr)
  return is_valid_buffer(bufnr) and vim.b[bufnr].scala_hints_workspace_managed == true
end

M._test = {
  discover_files = discover_files,
  should_ignore = should_ignore,
  update_metals_client = update_metals_client,
  is_within_root = is_within_root,
}

return M
