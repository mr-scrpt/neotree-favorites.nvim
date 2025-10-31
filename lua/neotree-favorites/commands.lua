-- Команды для работы с flat favorites
local manager = require("neotree-favorites.manager")
local filesystem_commands = require("neo-tree.sources.filesystem.commands")
local common_filter = require("neo-tree.sources.common.filters")

-- НАСЛЕДУЕМ ВСЕ команды из filesystem
local M = vim.tbl_extend("force", {}, filesystem_commands)

-- ПЕРЕОПРЕДЕЛЯЕМ fuzzy_finder - используем НАШ filter который вызывает flat_favorites.reset_search
M.fuzzy_finder = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, true, config.keep_filter_on_submit or false)
end

M.fuzzy_sorter = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, true, config.keep_filter_on_submit or false)
end

M.filter_on_submit = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, false, config.keep_filter_on_submit or false)
end

M.fuzzy_finder_directory = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, true, config.keep_filter_on_submit or false)
end

M.clear_filter = function(state)
  state.search_pattern = nil
  state.fuzzy_finder_mode = nil
  local mgr = require("neo-tree.sources.manager")
  mgr.refresh(state.name)
end

--- Добавить текущий узел в flat favorites
---@param state table
function M.add_to_flat_favorites(state)
  -- НЕ работает в источнике flat_favorites - только в filesystem
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
  
  -- Обновляем отображение индикаторов
  local ok, renderer = pcall(require, "neo-tree.ui.renderer")
  if ok then
    pcall(renderer.redraw, state)
  end
end

--- Удалить текущий узел из flat favorites
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
  
  -- Обновляем отображение - если в источнике flat_favorites, делаем refresh
  if state.name == "flat_favorites" then
    local mgr = require("neo-tree.sources.manager")
    mgr.refresh("flat_favorites")
  else
    -- Иначе просто перерисовываем индикаторы
    local ok, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok then
      pcall(renderer.redraw, state)
    end
  end
end

--- Переключить избранное для текущего узла
---@param state table
function M.toggle_flat_favorite(state)
  local node = state.tree:get_node()
  
  if not node then
    vim.notify("No node selected", vim.log.levels.WARN)
    return
  end

  local path = node:get_id()
  
  if manager.is_favorite(path) then
    -- Удаляем
    manager.remove_path(path)
    
    -- Обновляем отображение
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
    -- Добавляем
    manager.add_path(path)
    
    -- Обновляем индикаторы
    local ok, renderer = pcall(require, "neo-tree.ui.renderer")
    if ok then
      pcall(renderer.redraw, state)
    end
  end
end

--- Очистить все избранные для текущего проекта
---@param state table
function M.clear_all_flat_favorites(state)
  manager.clear_all_favorites()
  
  -- Обновляем отображение - если в источнике flat_favorites, делаем refresh
  if state.name == "flat_favorites" then
    local mgr = require("neo-tree.sources.manager")
    mgr.refresh("flat_favorites")
  end
end

return M
