-- Flat Favorites source для neo-tree
-- Каждый добавленный элемент отображается как отдельный корень на верхнем уровне

local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")
local utils = require("neo-tree.utils")

-- Берем window defaults из filesystem для fuzzy_finder
local filesystem_defaults = require("neo-tree.defaults").filesystem

local M = {
  name = "flat_favorites",
  display_name = "📦 Flat Favorites",
  
  -- Берем window config из filesystem (включая fuzzy_finder mappings)
  window = vim.deepcopy(filesystem_defaults.window),
}

local manager = require("neotree-favorites.manager")

local wrap = function(func)
  return utils.wrap(func, M.name)
end

--- Stop all file watchers (like in filesystem source)
---@param state table
local function stop_watchers(state)
  if state.use_libuv_file_watcher and state.tree then
    local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
    local log = require("neo-tree.log")
    
    -- Unwatch all previously watched folders
    local loaded_folders = renderer.select_nodes(state.tree, function(node)
      return node.type == "directory" and node.loaded
    end)
    
    for _, folder in ipairs(loaded_folders) do
      log.trace("Unwatching folder", folder.path)
      fs_watch.unwatch_folder(folder:get_id())
    end
  end
end

--- Setup watcher for loaded directory (like on_directory_loaded in filesystem)
---@param context table
---@param dir_path string
local function on_directory_loaded(context, dir_path)
  local state = context.state
  if state.use_libuv_file_watcher then
    local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
    local events = require("neo-tree.events")
    local log = require("neo-tree.log")
    
    local fs_watch_callback = vim.schedule_wrap(function(err, fname)
      if err then
        log.error("file_event_callback: ", err)
        return
      end
      -- Generate FS_EVENT like filesystem source does
      events.fire_event(events.FS_EVENT, { afile = dir_path })
    end)
    
    log.trace("Adding fs watcher for", dir_path)
    fs_watch.watch_folder(dir_path, fs_watch_callback)
  end
end

--- Load all directory contents recursively
---@param parent_item table
---@param parent_path string
---@param context table
local function load_all_recursive(parent_item, parent_path, context)
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
  
  -- Setup file watcher for this directory (call on_directory_loaded like filesystem does)
  if context then
    on_directory_loaded(context, parent_path)
  end
  
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
        extra = {
          search_path = entry,  -- КРИТИЧНО для фильтрации
        },
      }
      
      if is_dir then
        child.children = {}
        -- Рекурсивно загружаем содержимое
        load_all_recursive(child, entry, context)
      else
        child.ext = name:match("%.([^%.]+)$")
      end
      
      table.insert(parent_item.children, child)
    end
  end
  
  -- Сортируем
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
  local events = require("neo-tree.events")
  local mgr = require("neo-tree.sources.manager")
  local log = require("neo-tree.log")
  
  -- Подписываемся на события файловой системы для авто-обновления (как filesystem)
  if config.use_libuv_file_watcher then
    mgr.subscribe(M.name, {
      event = events.FS_EVENT,
      handler = wrap(mgr.refresh),
    })
  else
    -- Отключаем все watchers если file watcher выключен
    require("neo-tree.sources.filesystem.lib.fs_watch").unwatch_all()
    if global_config.enable_refresh_on_write then
      mgr.subscribe(M.name, {
        event = events.VIM_BUFFER_CHANGED,
        handler = function(arg)
          local afile = arg.afile or ""
          if utils.is_real_file(afile) then
            log.trace("refreshing due to vim_buffer_changed event: ", afile)
            mgr.refresh(M.name)
          else
            log.trace("Ignoring vim_buffer_changed event for non-file: ", afile)
          end
        end,
      })
    end
  end
end


--- Navigate - главный метод для отображения дерева
---@param state table
---@param path string|nil
---@param path_to_reveal string|nil
---@param callback function|nil
---@param async boolean|nil
function M.navigate(state, path, path_to_reveal, callback, async)
  if state.loading then
    return
  end
  
  -- Stop all watchers before starting fresh (like filesystem source does)
  stop_watchers(state)
  
  state.loading = true
  state.dirty = false
  state.path = path or vim.fn.getcwd()
  
  -- Создаем контекст для file_items
  local context = file_items.create_context()
  context.state = state
  
  -- Создаем корневую папку
  local root = file_items.create_item(context, state.path, "directory")
  root.name = "📦 Flat Favorites"
  root.loaded = true
  root.extra = root.extra or {}
  root.extra.search_path = root.path
  root.search_pattern = state.search_pattern
  context.folders[root.path] = root
  
  -- Получаем список избранных элементов
  -- Проверяем invalid пути только при открытии flat_favorites (медленно для больших деревьев)
  local favorites = manager.load_favorites(true)
  
  if not vim.tbl_isempty(favorites) then
    -- Собираем пути и сортируем
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
    
    -- Создаем элементы вручную БЕЗ file_items чтобы избежать автоматической иерархии
    for _, item_data in ipairs(paths) do
      local fav_path = item_data.path
      local fav_info = favorites[fav_path]
      local name = vim.fn.fnamemodify(fav_path, ":t")
      
      -- Если путь invalid, добавляем индикатор к имени
      if fav_info and fav_info.invalid then
        name = "⚠️  " .. name
      end
      
      -- Создаем элемент вручную
      local item = {
        id = fav_path,
        name = name,
        parent_path = root.path,  -- Родитель - root, НЕ реальный parent в ФС!
        path = fav_path,
        type = item_data.type,
        loaded = false,
        extra = { 
          search_path = fav_path,  -- Для фильтрации
          is_flat_favorite = true,
          is_invalid = fav_info and fav_info.invalid or false,
        },
      }
      
      if item_data.type == "directory" then
        item.children = {}
        context.folders[fav_path] = item
        -- Загружаем содержимое только для валидных путей
        if not (fav_info and fav_info.invalid) then
          load_all_recursive(item, fav_path, context)
        else
          item.loaded = true -- Помечаем как загруженный чтобы не было попыток загрузить
        end
      end
      
      -- Добавляем напрямую в root
      table.insert(root.children, item)
    end
  end
  
  -- Устанавливаем expanded nodes
  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  
  -- Сортируем детей корня
  if root.children then
    file_items.advanced_sort(root.children, state)
  end
  
  -- Отображаем дерево
  renderer.show_nodes({ root }, state)
  
  state.loading = false
  
  if type(callback) == "function" then
    vim.schedule(callback)
  end
  
  -- Финализация для file watchers
  if state.use_libuv_file_watcher then
    local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")
    fs_watch.updated_watched()
  end
end

return M
