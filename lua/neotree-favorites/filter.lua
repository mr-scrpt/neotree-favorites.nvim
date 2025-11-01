-- Кастомный filter для flat_favorites
-- Использует подход common.filters (orig_tree + фильтрация), но вызывает flat_favorites.reset_search

local Input = require("nui.input")
local popups = require("neo-tree.ui.popups")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local compat = require("neo-tree.utils._compat")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local fzy = require("neo-tree.sources.common.filters.filter_fzy")
local common_filter = require("neo-tree.sources.common.filters")

local M = {}

---Show filtered tree (из common.filters:57-94)
local function show_filtered_tree(state, do_not_focus_window)
  -- Проверяем что window все еще валидное
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    vim.notify("[FLAT_FAV] ⚠️  Window is not valid, aborting filter", vim.log.levels.WARN)
    return
  end
  
  -- По умолчанию используем substring search если use_fzy не установлен
  local use_fzy = state.use_fzy
  if use_fzy == nil then
    use_fzy = false
  end
  
  -- DEBUG: Подсчитываем узлы ДО фильтрации
  local function count_all_nodes(node_id, tree)
    local node = tree:get_node(node_id)
    if not node then return 0 end
    local count = 1
    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        count = count + count_all_nodes(child_id, tree)
      end
    end
    return count
  end
  
  local nodes_before = 0
  for _, root in ipairs(state.orig_tree:get_nodes()) do
    nodes_before = nodes_before + count_all_nodes(root:get_id(), state.orig_tree)
  end
  
  vim.notify(
    string.format("🔍 [FLAT_FAV] Searching: '%s' | Mode: %s | Nodes before: %d", 
      state.search_pattern or "", 
      use_fzy and "fuzzy" or "substring",
      nodes_before
    ),
    vim.log.levels.INFO
  )
  
  -- Копируем оригинальное дерево и фильтруем копию (НЕ пересоздаем!)
  state.tree = vim.deepcopy(state.orig_tree)
  state.tree:get_nodes()[1].search_pattern = state.search_pattern
  
  -- КРИТИЧНО: Обновляем winid и bufnr в дереве чтобы избежать "Invalid window" при повторных поисках
  if state.tree then
    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
      state.tree.winid = state.winid
    end
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
      state.tree.bufnr = state.bufnr
    end
  end
  
  local max_score, max_id = fzy.get_score_min(), nil
  local folders_to_expand = {}  -- Папки с совпадениями которые нужно раскрыть
  
  -- Получаем "базовый" путь (корень избранного) для относительных путей
  local base_path = state.path  -- Обычно это cwd проекта
  
  local function filter_tree(node_id)
    local node = state.tree:get_node(node_id)
    local full_path = node.extra.search_path or node.path
    
    local should_keep
    if use_fzy then
      -- Fuzzy search (как в "#" fuzzy_sorter) - ищем по ОТНОСИТЕЛЬНОМУ пути
      -- Убираем общий префикс чтобы не находить случайные совпадения в /home/username/
      local search_path = full_path
      
      -- Находим избранные папки из корня дерева
      local favorite_folders = {}
      if state.orig_tree then
        local root_nodes = state.orig_tree:get_nodes()
        if root_nodes and #root_nodes > 0 then
          -- Первый узел - это корень "📦 Flat Favorites"
          local flat_root = root_nodes[1]
          if flat_root and flat_root:has_children() then
            -- Дети root'а - это избранные папки (composition, react, etc)
            for _, child_id in ipairs(flat_root:get_child_ids()) do
              local child = state.orig_tree:get_node(child_id)
              if child and child.type == "directory" then
                table.insert(favorite_folders, child.name .. "/")
              end
            end
          end
        end
      end
      
      -- Пытаемся обрезать от избранной папки
      -- ВАЖНО: Ищем ПОСЛЕДНЕЕ вхождение (справа налево) чтобы избежать дублирования
      local best_pos = nil
      local best_pattern = nil
      for _, pattern in ipairs(favorite_folders) do
        -- Ищем все вхождения pattern и берем последнее
        local pos = 1
        while true do
          local found_pos = search_path:find(pattern, pos, true)
          if not found_pos then break end
          best_pos = found_pos
          best_pattern = pattern
          pos = found_pos + 1
        end
      end
      
      -- Если нашли избранную папку, обрезаем от неё
      if best_pos then
        search_path = search_path:sub(best_pos)
      end
      
      should_keep = fzy.has_match(state.search_pattern, search_path)
      if should_keep then
        local score = fzy.score(state.search_pattern, search_path)
        node.extra.fzy_score = score
        node.extra.fzy_search_path = search_path  -- Сохраняем для отладки
        if score > max_score then
          max_score = score
          max_id = node_id
        end
      end
    else
      -- Substring search (как в "/" fuzzy_finder) - ищем ТОЛЬКО по имени файла
      local filename = node.name  -- Используем имя файла вместо полного пути!
      local lower_filename = filename:lower()
      local lower_pattern = state.search_pattern:lower()
      should_keep = lower_filename:find(lower_pattern, 1, true) ~= nil
      -- Запоминаем первый найденный файл для фокуса
      if should_keep and not max_id and node.type == "file" then
        max_id = node_id
      end
    end
    
    local has_matching_children = false
    if node:has_children() then
      for _, child_id in ipairs(node:get_child_ids()) do
        local child_kept = filter_tree(child_id)
        if child_kept then
          has_matching_children = true
        end
        should_keep = child_kept or should_keep
      end
    end
    
    -- Если папка содержит совпадения, добавляем в список для раскрытия
    if node.type == "directory" and (should_keep or has_matching_children) then
      table.insert(folders_to_expand, node_id)
    end
    
    if not should_keep then
      state.tree:remove_node(node_id)
    end
    return should_keep
  end
  
  local matched_count = 0
  local file_matches = {}
  local tree_structure = {}
  local fuzzy_examples = {}  -- Примеры для fuzzy поиска
  
  if state.search_pattern and #state.search_pattern > 0 then
    for _, root in ipairs(state.tree:get_nodes()) do
      filter_tree(root:get_id())
    end
    
    -- КРИТИЧНО: Дедуплицируем узлы после фильтрации
    -- NuiTree.remove_node иногда оставляет дубликаты папок
    local duplicates_removed = 0
    local function dedupe_tree_nodes(parent_id)
      local parent = state.tree:get_node(parent_id)
      if not parent or not parent:has_children() then
        return
      end
      
      local seen_paths = {}  -- Дедуплицируем по ПУТИ, не по ID!
      local children_to_remove = {}
      
      for _, child_id in ipairs(parent:get_child_ids()) do
        local child = state.tree:get_node(child_id)
        if child then
          local path_key = child.path or child.id
          if seen_paths[path_key] then
            -- Это дубликат по пути!
            table.insert(children_to_remove, child_id)
            duplicates_removed = duplicates_removed + 1
          else
            seen_paths[path_key] = true
            -- Рекурсивно дедуплицируем детей
            dedupe_tree_nodes(child_id)
          end
        end
      end
      
      -- Удаляем дубликаты
      for _, dup_id in ipairs(children_to_remove) do
        state.tree:remove_node(dup_id)
      end
    end
    
    for _, root in ipairs(state.tree:get_nodes()) do
      dedupe_tree_nodes(root:get_id())
    end
    
    if duplicates_removed > 0 then
      vim.notify(
        string.format("🔧 [FLAT_FAV] Removed %d duplicate nodes", duplicates_removed),
        vim.log.levels.WARN
      )
    end
    
    -- Подсчитываем оставшиеся узлы и строим структуру дерева
    local function build_tree_structure(node_id, level)
      local node = state.tree:get_node(node_id)
      if not node then return 0 end
      
      local indent = string.rep("  ", level)
      local icon = node.type == "directory" and "📁" or "📄"
      local line = string.format("%s%s %s", indent, icon, node.name)
      table.insert(tree_structure, line)
      
      local count = 1
      
      -- Собираем файлы для отдельного списка
      if node.type == "file" then
        table.insert(file_matches, node.path)
        
        -- Для fuzzy поиска собираем примеры путей
        if use_fzy and #fuzzy_examples < 5 and node.extra and node.extra.fzy_search_path then
          table.insert(fuzzy_examples, string.format(
            "Original: %s\nSearched: %s\nScore: %.2f",
            node.path,
            node.extra.fzy_search_path,
            node.extra.fzy_score or 0
          ))
        end
      end
      
      if node:has_children() then
        for _, child_id in ipairs(node:get_child_ids()) do
          count = count + build_tree_structure(child_id, level + 1)
        end
      end
      return count
    end
    
    for _, root in ipairs(state.tree:get_nodes()) do
      matched_count = matched_count + build_tree_structure(root:get_id(), 0)
    end
    
    -- DEBUG: Детальное логирование результатов
    local result_msg = string.format(
      "✅ [FLAT_FAV] Results: %d nodes matched | %d folders to expand",
      matched_count,
      #folders_to_expand
    )
    vim.notify(result_msg, vim.log.levels.INFO)
    
    -- Показываем все найденные файлы (не папки)
    if #file_matches > 0 then
      local files_msg = string.format("📄 Found %d files:\n%s", #file_matches, table.concat(file_matches, "\n"))
      vim.notify(files_msg, vim.log.levels.INFO)
    end
    
    -- Для fuzzy поиска показываем примеры обработки путей
    if use_fzy and #fuzzy_examples > 0 then
      local fuzzy_msg = "🔍 Fuzzy search examples:\n" .. table.concat(fuzzy_examples, "\n---\n")
      vim.notify(fuzzy_msg, vim.log.levels.INFO)
    end
    
    -- Показываем структуру дерева (ограничиваем до 50 строк)
    if #tree_structure > 0 then
      local max_lines = 50
      local tree_msg_lines = {}
      for i = 1, math.min(#tree_structure, max_lines) do
        table.insert(tree_msg_lines, tree_structure[i])
      end
      if #tree_structure > max_lines then
        table.insert(tree_msg_lines, string.format("... и еще %d узлов", #tree_structure - max_lines))
      end
      local tree_msg = "🌳 Tree structure:\n" .. table.concat(tree_msg_lines, "\n")
      vim.notify(tree_msg, vim.log.levels.INFO)
    end
    
    -- Если слишком много узлов, предупреждаем
    if matched_count > 1000 then
      vim.notify(
        string.format("⚠️  [FLAT_FAV] Too many matches (%d nodes)! Consider more specific search.", matched_count),
        vim.log.levels.WARN
      )
    end
  end
  
  -- Раскрываем папки с совпадениями через default_expanded_nodes (как в fs_scan.lua:653)
  if #folders_to_expand > 0 then
    state.default_expanded_nodes = folders_to_expand
  end
  
  -- Применяем раскрытие папок ДО redraw
  if #folders_to_expand > 0 and state.tree then
    renderer.set_expanded_nodes(state.tree, folders_to_expand)
  end
  
  -- Проверяем что window все еще валидное перед redraw
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    log.warn("[FLAT_FAV FILTER] Window became invalid before redraw, aborting")
    return
  end
  
  -- Используем renderer.redraw вместо manager.redraw для сохранения expanded
  renderer.redraw(state)
  
  if max_id then
    -- Проверяем что window все еще валидное перед focus
    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
      renderer.focus_node(state, max_id, do_not_focus_window)
    end
  end
end

M.show_filter = function(state, search_as_you_type, use_fzy, keep_filter_on_submit)
  
  -- DEBUG: Логируем открытие поиска
  local mode_name = use_fzy and "fuzzy (#)" or "substring (/)"
  vim.notify(
    string.format("🔎 [FLAT_FAV] Opening search | Mode: %s | Live: %s", 
      mode_name,
      search_as_you_type and "yes" or "no"
    ),
    vim.log.levels.INFO
  )
  
  local winid = vim.api.nvim_get_current_win()
  local height = vim.api.nvim_win_get_height(winid)
  local scroll_padding = 3
  
  -- Устанавливаем режим поиска и сохраняем оригинальное значение
  state.use_fzy = use_fzy
  state._filter_use_fzy = use_fzy  -- Сохраняем в state для восстановления после reset
  
  -- Меняем заголовок в зависимости от режима
  local popup_msg
  if search_as_you_type then
    popup_msg = use_fzy and "Fuzzy Filter:" or "Filter:"
  else
    popup_msg = use_fzy and "Fuzzy Search:" or "Search:"
  end
  
  local width = vim.fn.winwidth(0) - 2
  local row = height - 3
  
  if state.current_position == "float" then
    scroll_padding = 0
    width = vim.fn.winwidth(winid)
    row = height - 2
    vim.api.nvim_win_set_height(winid, row)
  end
  
  local popup_options = popups.popup_options(popup_msg, width, {
    relative = "win",
    winid = winid,
    position = { row = row, col = 0 },
    size = width,
  })
  
  -- КРИТИЧНО: Сохраняем оригинальное дерево ТОЛЬКО ОДИН РАЗ (как common.filters:124)
  if not state.orig_tree then
    state.orig_tree = vim.deepcopy(state.tree)
    -- Обновляем winid/bufnr в оригинальном дереве
    if state.orig_tree then
      if state.winid and vim.api.nvim_win_is_valid(state.winid) then
        state.orig_tree.winid = state.winid
      end
      if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
        state.orig_tree.bufnr = state.bufnr
      end
    end
  end
  
  -- Сохраняем открытые папки перед поиском
  local has_pre_search_folders = utils.truthy(state.open_folders_before_search)
  if not has_pre_search_folders then
    state.open_folders_before_search = renderer.get_expanded_nodes(state.tree)
  end
  
  local waiting_for_default_value = utils.truthy(state.search_pattern)
  local input = Input(popup_options, {
    prompt = " ",
    default_value = state.search_pattern,
    on_submit = function(value)
      if value == "" then
        vim.notify("↩️  [FLAT_FAV] Submit with empty value - resetting search", vim.log.levels.INFO)
        -- Сброс фильтра
        local flat_favorites = require("neotree-favorites")
        flat_favorites.reset_search(state)
      else
        if search_as_you_type and not keep_filter_on_submit then
          vim.notify(
            string.format("↩️  [FLAT_FAV] Enter pressed - opening file and resetting search (pattern: '%s')", value),
            vim.log.levels.INFO
          )
          -- Enter с search_as_you_type - вызываем НАШ reset_search
          local flat_favorites = require("neotree-favorites")
          flat_favorites.reset_search(state, true, true)
          return
        end
        vim.notify(
          string.format("↩️  [FLAT_FAV] Submit search: '%s'", value),
          vim.log.levels.INFO
        )
        state.search_pattern = value
        show_filtered_tree(state, false)
      end
    end,
    on_change = function(value)
      if not search_as_you_type then
        return
      end
      
      -- Обработка default value
      if waiting_for_default_value then
        if #value < #(state.search_pattern or "") then
          return
        end
        waiting_for_default_value = false
      end
      
      if value == state.search_pattern or value == nil then
        return
      end
      
      if value == "" then
        if state.search_pattern == nil then
          return
        end
        
        vim.notify("🗑️  [FLAT_FAV] Search cleared - resetting to original tree", vim.log.levels.INFO)
        
        -- Сохраняем open_folders_before_search как в filesystem (filter.lua:159-164)
        local original_open_folders = nil
        if type(state.open_folders_before_search) == "table" then
          original_open_folders = vim.deepcopy(state.open_folders_before_search, compat.noref())
        end
        
        -- КРИТИЧНО: Оборачиваем в vim.schedule чтобы избежать E565
        vim.schedule(function()
          -- Вызываем reset_search как в filesystem
          local flat_favorites = require("neotree-favorites")
          flat_favorites.reset_search(state)
          
          -- Восстанавливаем сохраненные значения
          state.open_folders_before_search = original_open_folders
          state.use_fzy = state._filter_use_fzy  -- Восстанавливаем режим поиска
        end)
      else
        -- DEBUG: Логируем что печатает пользователь
        vim.notify(
          string.format("⌨️  [FLAT_FAV] Typing: '%s' (length: %d)", value, #value),
          vim.log.levels.INFO
        )
        
        state.search_pattern = value
        
        -- Debounce фильтрацию
        local delay = #value > 3 and 100 or (#value > 2 and 200 or (#value > 1 and 400 or 500))
        utils.debounce(state.name .. "_filter", function()
          -- Проверяем что pattern все еще установлен (не был очищен)
          if not state.search_pattern or state.search_pattern == "" then
            vim.notify("🗑️  [FLAT_FAV] Pattern was cleared, skipping filter", vim.log.levels.INFO)
            return
          end
          show_filtered_tree(state, true)
        end, delay, utils.debounce_strategy.CALL_LAST_ONLY)
      end
    end,
  })
  
  input:mount()
  
  local restore_height = vim.schedule_wrap(function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_height(winid, height)
    end
  end)
  
  -- Commands для popup
  local cmds = {
    move_cursor_down = function(_state, _scroll_padding)
      renderer.focus_node(_state, nil, true, 1, _scroll_padding)
    end,
    move_cursor_up = function(_state, _scroll_padding)
      renderer.focus_node(_state, nil, true, -1, _scroll_padding)
      vim.cmd("redraw!")
    end,
    close = function(_state)
      vim.notify("❌ [FLAT_FAV] Search popup closed (Esc)", vim.log.levels.INFO)
      vim.cmd("stopinsert")
      input:unmount()
      if utils.truthy(_state.search_pattern) then
        vim.notify(
          string.format("🔄 [FLAT_FAV] Resetting search after close (pattern was: '%s')", _state.search_pattern),
          vim.log.levels.INFO
        )
        local flat_favorites = require("neotree-favorites")
        flat_favorites.reset_search(_state, true)
      end
      restore_height()
    end,
    close_keep_filter = function(_state, _scroll_padding)
      log.info("Persisting the search filter")
      keep_filter_on_submit = true
      cmds.close(_state, _scroll_padding)
    end,
    close_clear_filter = function(_state, _scroll_padding)
      log.info("Clearing the search filter")
      keep_filter_on_submit = false
      cmds.close(_state, _scroll_padding)
    end,
  }
  
  common_filter.setup_hooks(input, cmds, state, scroll_padding)
  common_filter.setup_mappings(input, cmds, state, scroll_padding)
end

return M
