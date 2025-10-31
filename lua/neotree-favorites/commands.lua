-- Команды для работы с flat favorites
local manager = require("neotree-favorites.manager")
local filesystem_commands = require("neo-tree.sources.filesystem.commands")
local common_filter = require("neo-tree.sources.common.filters")

-- НАСЛЕДУЕМ ВСЕ команды из filesystem
local M = vim.tbl_extend("force", {}, filesystem_commands)

-- ПЕРЕОПРЕДЕЛЯЕМ toggle_hidden для flat_favorites
M.toggle_hidden = function(state)
  state.filtered_items.visible = not state.filtered_items.visible
  local log = require("neo-tree.log")
  log.info("Toggling hidden files: " .. tostring(state.filtered_items.visible))
  
  -- Обновляем только filtered_items в default config чтобы изменение сохранилось при refresh
  local mgr = require("neo-tree.sources.manager")
  mgr.set_default_config(state.name, {
    filtered_items = vim.deepcopy(state.filtered_items)
  })
  
  -- Refresh
  mgr.refresh("flat_favorites")
end

-- ПЕРЕОПРЕДЕЛЯЕМ fuzzy_finder - используем НАШ filter который вызывает flat_favorites.reset_search
-- "/" - строгий поиск (substring match)
M.fuzzy_finder = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, true, false, config.keep_filter_on_submit or false)
end

-- "#" - fuzzy поиск (fzy алгоритм)
M.fuzzy_sorter = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, true, true, config.keep_filter_on_submit or false)
end

-- "f" - поиск по Enter (не as-you-type)
M.filter_on_submit = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  filter.show_filter(state, false, false, config.keep_filter_on_submit or false)
end

M.fuzzy_finder_directory = function(state)
  local filter = require("neotree-favorites.filter")
  local config = state.config or {}
  -- Пока не поддерживаем directory mode, просто используем обычный fuzzy_finder
  filter.show_filter(state, true, false, config.keep_filter_on_submit or false)
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

--- Удалить все устаревшие пути (deleted/moved) из избранного
---@param state table
function M.remove_invalid_favorites(state)
  local favorites = manager.load_favorites()
  local invalid_paths = {}
  
  -- Находим устаревшие пути
  for path, _ in pairs(favorites) do
    if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
      table.insert(invalid_paths, path)
    end
  end
  
  if #invalid_paths == 0 then
    vim.notify("No invalid paths found in favorites", vim.log.levels.INFO)
    return
  end
  
  -- Удаляем все устаревшие пути
  for _, path in ipairs(invalid_paths) do
    manager.remove_path(path)
  end
  
  vim.notify(string.format("Removed %d invalid path(s) from favorites", #invalid_paths), vim.log.levels.INFO)
  
  -- Обновляем отображение
  if state.name == "flat_favorites" then
    local mgr = require("neo-tree.sources.manager")
    mgr.refresh("flat_favorites")
  end
end

return M
