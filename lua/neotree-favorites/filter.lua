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
  log.trace("Filtering tree with pattern:", state.search_pattern)
  
  -- Копируем оригинальное дерево и фильтруем копию (НЕ пересоздаем!)
  state.tree = vim.deepcopy(state.orig_tree)
  state.tree:get_nodes()[1].search_pattern = state.search_pattern
  
  local max_score, max_id = fzy.get_score_min(), nil
  local folders_to_expand = {}  -- Папки с совпадениями которые нужно раскрыть
  
  local function filter_tree(node_id)
    local node = state.tree:get_node(node_id)
    local path = node.extra.search_path or node.path
    
    local should_keep = fzy.has_match(state.search_pattern, path)
    if should_keep then
      local score = fzy.score(state.search_pattern, path)
      node.extra.fzy_score = score
      if score > max_score then
        max_score = score
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
  
  if state.search_pattern and #state.search_pattern > 0 then
    for _, root in ipairs(state.tree:get_nodes()) do
      filter_tree(root:get_id())
    end
  end
  
  -- Раскрываем папки с совпадениями через default_expanded_nodes (как в fs_scan.lua:653)
  if #folders_to_expand > 0 then
    state.default_expanded_nodes = folders_to_expand
    log.trace("Expanding", #folders_to_expand, "folders with matches")
  end
  
  -- Применяем раскрытие папок ДО redraw
  if #folders_to_expand > 0 and state.tree then
    renderer.set_expanded_nodes(state.tree, folders_to_expand)
  end
  
  -- Используем renderer.redraw вместо manager.redraw для сохранения expanded
  renderer.redraw(state)
  
  if max_id then
    renderer.focus_node(state, max_id, do_not_focus_window)
  end
end

M.show_filter = function(state, search_as_you_type, keep_filter_on_submit)
  local winid = vim.api.nvim_get_current_win()
  local height = vim.api.nvim_win_get_height(winid)
  local scroll_padding = 3
  
  local popup_msg = search_as_you_type and "Filter:" or "Search:"
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
  
  -- КРИТИЧНО: Сохраняем оригинальное дерево ОДИН раз (как common.filters:124)
  state.orig_tree = vim.deepcopy(state.tree)
  
  -- Сохраняем открытые папки перед поиском
  local has_pre_search_folders = utils.truthy(state.open_folders_before_search)
  if not has_pre_search_folders then
    log.trace("Recording pre-search folders")
    state.open_folders_before_search = renderer.get_expanded_nodes(state.tree)
  end
  
  local waiting_for_default_value = utils.truthy(state.search_pattern)
  local input = Input(popup_options, {
    prompt = " ",
    default_value = state.search_pattern,
    on_submit = function(value)
      if value == "" then
        -- Сброс фильтра
        local flat_favorites = require("neotree-favorites")
        flat_favorites.reset_search(state)
      else
        if search_as_you_type and not keep_filter_on_submit then
          -- Enter с search_as_you_type - вызываем НАШ reset_search
          local flat_favorites = require("neotree-favorites")
          flat_favorites.reset_search(state, true, true)
          return
        end
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
        log.trace("Clearing search in on_change")
        -- НЕ вызываем reset_search - просто сбрасываем pattern и восстанавливаем дерево
        state.search_pattern = nil
        if state.orig_tree then
          state.tree = vim.deepcopy(state.orig_tree)
          manager.redraw(state.name)
        end
      else
        log.trace("Setting search to:", value)
        state.search_pattern = value
        
        -- Debounce фильтрацию
        local delay = #value > 3 and 100 or (#value > 2 and 200 or (#value > 1 and 400 or 500))
        utils.debounce(state.name .. "_filter", function()
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
      vim.cmd("stopinsert")
      input:unmount()
      if utils.truthy(_state.search_pattern) then
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
