-- Flat Favorites source для neo-tree
-- Каждый добавленный элемент отображается как отдельный корень на верхнем уровне

local renderer = require("neo-tree.ui.renderer")
local file_items = require("neo-tree.sources.common.file-items")
local utils = require("neo-tree.utils")
local compat = require("neo-tree.utils._compat")

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
---@param favorites_set table|nil Set избранных путей (для пропуска дубликатов)
local function load_all_recursive(parent_item, parent_path, context, favorites_set)
  local scan = require("plenary.scandir")
  local state = context.state
  local filtered_items = state.filtered_items or {}
  
  -- Определяем какие файлы показывать (как в filesystem)
  local show_hidden = filtered_items.visible or false
  local log = require("neo-tree.log")
  
  local success, entries = pcall(scan.scan_dir, parent_path, {
    hidden = show_hidden,  -- Показывать dotfiles если visible=true
    -- НЕ используем respect_gitignore т.к. mark_ignored работает лучше (учитывает родительские .gitignore)
    depth = 1,
    add_dirs = true,
  })
  
  if not success then
    parent_item.loaded = true
    return
  end
  
  parent_item.children = {}
  
  -- Простая собственная реализация gitignore фильтрации
  local utils = require("neo-tree.utils")
  local temp_items = {}
  for _, entry in ipairs(entries) do
    local item = { 
      path = entry, 
      type = vim.fn.isdirectory(entry) == 1 and "directory" or "file" 
    }
    
    -- Проверяем gitignore используя plenary
    local _, name = utils.split_path(entry)
    if name then
      -- Ищем .gitignore вверх по дереву от parent_path
      local gitignore_files = vim.fs.find(".gitignore", { 
        upward = true, 
        limit = math.huge, 
        path = parent_path, 
        type = "file" 
      })
      
      -- Проверяем является ли файл gitignored
      for _, gitignore_path in ipairs(gitignore_files) do
        local gitignore_dir = vim.fn.fnamemodify(gitignore_path, ":h")
        -- Проверяем что entry находится под этой gitignore директорией
        if vim.startswith(entry, gitignore_dir) then
          -- Читаем .gitignore и проверяем паттерны
          local gitignore_content = vim.fn.readfile(gitignore_path)
          for _, pattern in ipairs(gitignore_content) do
            -- Пропускаем комментарии и пустые строки
            pattern = vim.trim(pattern)
            if pattern ~= "" and not vim.startswith(pattern, "#") then
              -- Убираем leading/trailing слэши
              local clean_pattern = pattern:gsub("^/", ""):gsub("/$", "")
              
              -- Проверяем соответствие паттерну
              local matches = false
              if clean_pattern:find("[*?%[]") then
                -- Glob паттерн - преобразуем в regex
                local regex_pattern = vim.fn.glob2regpat(clean_pattern)
                matches = vim.fn.match(name, regex_pattern) ~= -1
              else
                -- Точное совпадение
                matches = (name == clean_pattern)
              end
              
              if matches then
                item.filtered_by = item.filtered_by or {}
                item.filtered_by.ignored = true
                item.filtered_by.ignore_file = gitignore_path
                break
              end
            end
          end
          if item.filtered_by and item.filtered_by.ignored then
            break
          end
        end
      end
    end
    
    table.insert(temp_items, item)
  end
  
  -- Дополнительно помечаем dotfiles (как в common/file-items.lua:263)
  -- Помечаем ВСЕГДА, чтобы когда visible=true они отображались серым
  for _, item in ipairs(temp_items) do
    local _, name = utils.split_path(item.path)
    if name and string.sub(name, 1, 1) == "." then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.dotfiles = true
    end
  end
  
  -- Создаем lookup для filtered_by по пути
  local filtered_by_lookup = {}
  for _, item in ipairs(temp_items) do
    filtered_by_lookup[item.path] = item.filtered_by
  end
  
  -- Фильтруем entries по результатам mark_ignored и dotfiles
  local filtered_entries = {}
  for i, item in ipairs(temp_items) do
    local should_include = true
    
    if not show_hidden and item.filtered_by then
      -- Скрываем gitignored если hide_gitignored
      if item.filtered_by.ignored and filtered_items.hide_gitignored then
        should_include = false
      end
      -- Скрываем dotfiles если hide_dotfiles
      if item.filtered_by.dotfiles and filtered_items.hide_dotfiles then
        should_include = false
      end
    end
    
    if should_include then
      table.insert(filtered_entries, entries[i])
    end
  end
  entries = filtered_entries
  
  -- Setup file watcher for this directory (call on_directory_loaded like filesystem does)
  if context then
    on_directory_loaded(context, parent_path)
  end
  
  for _, entry in ipairs(entries) do
    -- Пропускаем если этот путь уже добавлен в избранное явно
    if favorites_set and favorites_set[entry] then
      goto continue
    end
    
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
        filtered_by = filtered_by_lookup[entry],  -- Добавляем статус (gitignored, dotfile, etc)
      }
      
      if is_dir then
        child.children = {}
        -- Рекурсивно загружаем содержимое (передаем favorites_set)
        load_all_recursive(child, entry, context, favorites_set)
      else
        child.ext = name:match("%.([^%.]+)$")
      end
      
      table.insert(parent_item.children, child)
    end
    
    ::continue::
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
  
  -- Инициализируем filtered_items (как в filesystem.setup)
  config.filtered_items = config.filtered_items or {}
  local defaults = require("neo-tree.defaults").filesystem.filtered_items
  config.filtered_items = vim.tbl_deep_extend("force", vim.deepcopy(defaults), config.filtered_items)
  
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
    -- Создаем set из избранных путей для быстрой проверки
    local favorites_set = {}
    for fav_path, _ in pairs(favorites) do
      favorites_set[fav_path] = true
    end
    
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
    
    -- Находим дубликаты по имени на верхнем уровне
    local name_counts = {}
    for _, item_data in ipairs(paths) do
      local name = vim.fn.fnamemodify(item_data.path, ":t")
      name_counts[name] = (name_counts[name] or 0) + 1
    end
    
    -- Создаем элементы вручную БЕЗ file_items чтобы избежать автоматической иерархии
    for _, item_data in ipairs(paths) do
      local fav_path = item_data.path
      local fav_info = favorites[fav_path]
      local name = vim.fn.fnamemodify(fav_path, ":t")
      
      -- Если есть дубликаты по имени, добавляем путь в скобках
      if name_counts[name] > 1 then
        -- Получаем относительный путь от cwd
        local relative_path = vim.fn.fnamemodify(fav_path, ":~:h")
        -- Убираем начальный ./ если есть
        relative_path = relative_path:gsub("^%./", "")
        name = name .. " (" .. relative_path .. ")"
      end
      
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
          load_all_recursive(item, fav_path, context, favorites_set)
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

--- Reset the current search/filter and optionally open the current node (file)
---@param state table
---@param refresh boolean|nil
---@param open_current_node boolean|nil
function M.reset_search(state, refresh, open_current_node)
  -- Cancel any pending external filter
  require("neo-tree.sources.filesystem.lib.filter_external").cancel()

  -- Reset fuzzy state (mirrors filesystem behavior)
  state.fuzzy_finder_mode = nil
  state.use_fzy = nil
  state.fzy_sort_result_scores = nil
  state.sort_function_override = nil
  
  -- КРИТИЧНО: Сбрасываем orig_tree чтобы при следующем поиске создалось новое с актуальным winid/bufnr
  state.orig_tree = nil

  if refresh == nil then
    refresh = true
  end

  if state.open_folders_before_search then
    state.force_open_folders = vim.deepcopy(state.open_folders_before_search, compat.noref())
  else
    state.force_open_folders = nil
  end
  state.search_pattern = nil
  state.open_folders_before_search = nil

  if open_current_node then
    local success, node = pcall(state.tree.get_node, state.tree)
    if success and node then
      local path = node:get_id()
      renderer.position.set(state, path)
      if node.type == "directory" then
        path = utils.remove_trailing_slash(path)
        M.navigate(state, nil, path, function()
          pcall(renderer.focus_node, state, path, false)
        end)
      else
        utils.open_file(state, path)
        if refresh and state.current_position ~= "current" and state.current_position ~= "float" then
          M.navigate(state, nil, path)
        end
      end
    end
  else
    if refresh then
      M.navigate(state)
    end
  end
end

return M
