-- Flat Favorites source for neo-tree
-- Each added item is displayed as a separate root at the top level

local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")
local utils = require("neo-tree.utils")

local M = {
  name = "neotree-favorites",
  display_name = "📦 Flat Favorites",
}

local manager = require("neotree-favorites.manager")

--- Load all directory contents recursively
---@param parent_item table
---@param parent_path string
local function load_all_recursive(parent_item, parent_path)
  local scan = require("plenary.scandir")
  
  local success, entries = pcall(scan.scan_dir, parent_path, {
    hidden = false,
    depth = 1,
    add_dirs = true,
  })
  
  if not success then
    parent_item.loaded = true
    return
  end
  
  parent_item.children = {}
  
  for _, entry in ipairs(entries) do
    local stat = vim.loop.fs_stat(entry)
    if stat then
      local name = vim.fn.fnamemodify(entry, ":t")
      local is_dir = stat.type == "directory"
      
      local child = {
        id = entry,
        name = name,
        parent_path = parent_path,
        path = entry,
        type = is_dir and "directory" or "file",
        loaded = false,
      }
      
      if is_dir then
        child.children = {}
        -- Recursively load contents
        load_all_recursive(child, entry)
      else
        child.ext = name:match("%.([^%.]+)$")
      end
      
      table.insert(parent_item.children, child)
    end
  end
  
  -- Sort children
  table.sort(parent_item.children, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    end
    return a.type == "directory"
  end)
  
  parent_item.loaded = true
end

--- Setup source
---@param config table
---@param global_config table
function M.setup(config, global_config)
  -- No setup required
end


--- Navigate - main method for displaying the tree
---@param state table
---@param path string|nil
---@param path_to_reveal string|nil
---@param callback function|nil
---@param async boolean|nil
function M.navigate(state, path, path_to_reveal, callback, async)
  if state.loading then
    return
  end
  
  state.loading = true
  state.dirty = false
  state.path = path or vim.fn.getcwd()
  
  -- Create context for file_items
  local context = file_items.create_context()
  context.state = state
  
  -- Create root folder
  local root = file_items.create_item(context, state.path, "directory")
  root.name = "📦 Flat Favorites"
  root.loaded = true
  root.search_pattern = state.search_pattern
  context.folders[root.path] = root
  
  -- Get list of favorite items
  -- Check invalid paths only when opening flat_favorites (slow for large trees)
  local favorites = manager.load_favorites(true)
  
  if not vim.tbl_isempty(favorites) then
    -- Collect paths and sort
    local paths = {}
    for fav_path, data in pairs(favorites) do
      table.insert(paths, { path = fav_path, type = data.type })
    end
    
    table.sort(paths, function(a, b)
      if a.type == b.type then
        return a.path < b.path
      end
      return a.type == "directory"
    end)
    
    -- Create items manually WITHOUT file_items to avoid automatic hierarchy
    for _, item_data in ipairs(paths) do
      local fav_path = item_data.path
      local fav_info = favorites[fav_path]
      local name = vim.fn.fnamemodify(fav_path, ":t")
      
      -- If path is invalid, add indicator to name
      if fav_info and fav_info.invalid then
        name = "⚠️  " .. name
      end
      
      -- Create item manually
      local item = {
        id = fav_path,
        name = name,
        parent_path = root.path,  -- Parent is root, NOT the real parent in filesystem!
        path = fav_path,
        type = item_data.type,
        loaded = false,
        extra = { 
          is_flat_favorite = true,
          is_invalid = fav_info and fav_info.invalid or false,
        },
      }
      
      if item_data.type == "directory" then
        item.children = {}
        context.folders[fav_path] = item
        -- Load contents only for valid paths
        if not (fav_info and fav_info.invalid) then
          load_all_recursive(item, fav_path)
        else
          item.loaded = true -- Mark as loaded to prevent loading attempts
        end
      end
      
      -- Add directly to root
      table.insert(root.children, item)
    end
  end
  
  -- Set expanded nodes
  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  
  -- Sort root children
  if root.children then
    file_items.advanced_sort(root.children, state)
  end
  
  -- Display tree
  renderer.show_nodes({ root }, state)
  
  state.loading = false
  
  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

return M
