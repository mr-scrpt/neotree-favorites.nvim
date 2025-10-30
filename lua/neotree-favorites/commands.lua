-- Commands for working with flat favorites
local manager = require("neotree-favorites.manager")

local M = {}

--- Add current node to flat favorites
---@param state table
function M.add_to_flat_favorites(state)
  -- Does NOT work in flat_favorites source - only in filesystem
  if state.name == "flat_favorites" then
    vim.notify("Cannot add from flat_favorites view. Use filesystem view (fa)", vim.log.levels.WARN)
    return
  end
  
  local node = state.tree:get_node()
  
  if not node then
    vim.notify("No node selected", vim.log.levels.WARN)
    return
  end

  local path = node:get_id()
  manager.add_path(path)
  
  -- Update indicator display
  local ok, renderer = pcall(require, "neo-tree.ui.renderer")
  if ok then
    pcall(renderer.redraw, state)
  end
end

--- Remove current node from flat favorites
---@param state table
function M.remove_from_flat_favorites(state)
  local node = state.tree:get_node()
  
  if not node then
    vim.notify("No node selected", vim.log.levels.WARN)
    return
  end

  local path = node:get_id()
  
  if not manager.is_favorite(path) then
    vim.notify("Path is not in flat favorites", vim.log.levels.WARN)
    return
  end

  manager.remove_path(path)
  
  -- Update display - if in flat_favorites source, do refresh
  if state.name == "flat_favorites" then
    local mgr = require("neo-tree.sources.manager")
    mgr.refresh("flat_favorites")
  else
    -- Otherwise just redraw indicators
    local ok, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok then
      pcall(renderer.redraw, state)
    end
  end
end

--- Toggle favorite for current node
---@param state table
function M.toggle_flat_favorite(state)
  local node = state.tree:get_node()
  
  if not node then
    vim.notify("No node selected", vim.log.levels.WARN)
    return
  end

  local path = node:get_id()
  
  if manager.is_favorite(path) then
    -- Remove
    manager.remove_path(path)
    
    -- Update display
    if state.name == "flat_favorites" then
      local mgr = require("neo-tree.sources.manager")
      mgr.refresh("flat_favorites")
    else
      local ok, renderer = pcall(require, "neo-tree.ui.renderer")
      if ok then
        pcall(renderer.redraw, state)
      end
    end
  else
    -- Add
    manager.add_path(path)
    
    -- Update indicators
    local ok, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok then
      pcall(renderer.redraw, state)
    end
  end
end

--- Clear all favorites for current project
---@param state table
function M.clear_all_flat_favorites(state)
  manager.clear_all_favorites()
  
  -- Refresh the view if in flat_favorites source
  if state.name == "flat_favorites" then
    local mgr = require("neo-tree.sources.manager")
    mgr.refresh("flat_favorites")
  end
end

return M
