-- Filter для flat_favorites (точная копия filesystem.lib.filter с заменой fs на flat_favorites)

local Input = require("nui.input")
local popups = require("neo-tree.ui.popups")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local common_filter = require("neo-tree.sources.common.filters")

local M = {}

M.show_filter = function(
  state,
  search_as_you_type,
  fuzzy_finder_mode,
  use_fzy,
  keep_filter_on_submit
)
  local winid = vim.api.nvim_get_current_win()
  local height = vim.api.nvim_win_get_height(winid)
  local popup_msg = "Filter:"
  if search_as_you_type then
    if fuzzy_finder_mode == "directory" then
      popup_msg = "Filter Directories:"
    else
      popup_msg = "Filter:"
    end
  end
  
  local width = vim.fn.winwidth(0) - 2
  local row = height - 3
  
  local popup_options = popups.popup_options(popup_msg, width, {
    relative = "win",
    winid = winid,
    position = {
      row = row,
      col = 0,
    },
    size = width,
  })

  local input = Input(popup_options, {
    prompt = " ",
    default_value = state.search_pattern,
    on_submit = function(value)
      if value == "" then
        local flat_favorites = require("neotree-favorites")
        flat_favorites.reset_search(state)
      else
        if search_as_you_type and fuzzy_finder_mode and not keep_filter_on_submit then
          -- КАК В FILESYSTEM - вызываем reset_search с open_current_node=true
          local flat_favorites = require("neotree-favorites")
          flat_favorites.reset_search(state, true, true)
          return
        end
        state.search_pattern = value
        manager.refresh(state.name)
      end
    end,
    on_change = function(value)
      if not search_as_you_type then
        return
      end
      if value == state.search_pattern or value == nil or value == "" then
        return
      end
      
      -- Инпат только фильтрует - обновляем search_pattern и делаем refresh
      state.search_pattern = value
      state.fuzzy_finder_mode = fuzzy_finder_mode
      
      utils.debounce(state.name .. "_filter", function()
        manager.refresh(state.name)
      end, 100, utils.debounce_strategy.CALL_LAST_ONLY)
    end,
  })

  input:mount()
  
  -- Commands для popup (как в filesystem.lib.filter:205-239)
  local cmds = {
    move_cursor_down = function(_state, _scroll_padding)
      renderer.focus_node(_state, nil, true, 1, _scroll_padding)
    end,
    move_cursor_up = function(_state, _scroll_padding)
      renderer.focus_node(_state, nil, true, -1, _scroll_padding)
      vim.cmd("redraw!")
    end,
    close = function(_state, _scroll_padding)
      vim.cmd("stopinsert")
      input:unmount()
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

  common_filter.setup_hooks(input, cmds, state, 3)
  
  if not fuzzy_finder_mode then
    return
  end
  
  common_filter.setup_mappings(input, cmds, state, 3)
end

return M
