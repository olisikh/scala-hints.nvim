local ts = vim.treesitter
local async = require('plenary.async')

local M = {}

---Run a function or timeout
---@param func function to execute
---@param timeout integer duration in ms to trigger a timeout if function call takes too much time to finish
---@return boolean status of the call, true if succeeded
---@return string|any result or error message
M.run_or_timeout = function(func, timeout)
  local function timeout_func()
    async.util.sleep(timeout)
    return false, string.format('timed out after %d ms', timeout)
  end

  return async.util.race({
    function()
      return pcall(func)
    end,
    timeout_func,
  })
end

-- TODO: implement metals progress messages parsing, expecting for when the indexing is over to then kick off
-- diagnostics collection
--
---Makes sure metals is ready
---@param bufnr integer buffer number
---@return vim.lsp.Client metals client
M.ensure_metals = function(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'metals' })

  if #clients == 0 then
    async.util.sleep(1000)
    return M.ensure_metals(bufnr)
  else
    local metals = clients[1]

    if not metals or not metals.initialized then
      async.util.sleep(1000)
      return M.ensure_metals(bufnr)
    else
      return metals
    end
  end
end

M.deep_merge = function(tbl, ext)
  return vim.tbl_deep_extend('error', tbl, ext)
end

---Get the text of the TSNode
---@param bufnr integer buffer number
---@param node TSNode to get text of
---@return string content of the node
M.get_node_text = function(bufnr, node)
  return ts.get_node_text(node, bufnr)
end

---Find the deepest node in a tree by type
---@param node TSNode node to traverse children in
---@param type string type of the symbol to search
---@return TSNode|nil node by type or nil if not found
function M.find_deepest_node_by_type(node, type)
  local deepest_node = nil
  local deepest_depth = -1

  local function dfs(current_node, depth)
    -- Check if the current node is a field_expression and deeper than previous ones
    if current_node:type() == type and depth > deepest_depth then
      deepest_node = current_node
      deepest_depth = depth
    end

    -- Recursively iterate over the children of the current node
    for child in current_node:iter_children() do
      dfs(child, depth + 1)
    end
  end

  -- Start depth-first search from the root node
  dfs(node, 0)

  return deepest_node
end

---Verifies if the node has ZIO type
---@param bufnr number buffer number
---@param node TSNode|nil node to hover on
M.hover_node_and_match = function(bufnr, node, predicate)
  if node == nil then
    return false
  end

  local p_start_row, p_start_col, p_end_row, p_end_col = node:range()
  local start_pos = { p_start_row, p_start_col }
  local end_pos = { p_end_row, p_end_col }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos, bufnr)

  local tx, rx = async.control.channel.oneshot()

  vim.lsp.buf_request(bufnr, 'textDocument/hover', params, function(err, result, _, _)
    if err ~= nil then
      vim.notify(string.format('Request textDocument/hover to Metals LSP server has failed: %s', err))
      return false
    end

    local is_zio = result ~= nil
      and result.contents ~= nil
      and result.contents.value ~= nil
      and predicate(result.contents.value)

    -- vim.print(result)
    -- M.print_ts_node(bufnr, node)

    tx(is_zio)
  end)

  return rx()
end

---Find a parent of the TSNode by type
---@param node TSNode to look for a parent from
---@param type string type of the node to look for
---@return TSNode? node found or nil
function M.find_parent_by_type(node, type)
  local curr_node = node
  while curr_node do
    if curr_node:type() == type then
      return curr_node
    else
      curr_node = curr_node:parent()
    end
  end
  return nil
end

---Prints information about and content of TSNode
---@param bufnr buffer number
---@param node TSNode to print into stdout
function M.print_ts_node(bufnr, node)
  print('Type:', node:type())
  print('Start:', node:start())
  print('End:', node:end_())

  vim.print(ts.get_node_text(node, bufnr))
end

---Flattens an array
---@param arr table to flatten
---@return table arr but flattened
function M.flatten_array(arr)
  local function is_array(t)
    local i = 0
    for _ in pairs(t) do
      i = i + 1
      if t[i] == nil then
        return false
      end
    end
    return true
  end

  local result = {}
  for _, item in ipairs(arr) do
    if is_array(item) then
      local flattenedSubArray = M.flatten_array(item)
      for _, subitem in ipairs(flattenedSubArray) do
        table.insert(result, subitem)
      end
    else
      table.insert(result, item)
    end
  end
  return result
end

return M
