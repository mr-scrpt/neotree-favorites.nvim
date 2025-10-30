-- Команда для показа информации о favorites текущего проекта
local manager = require("neotree-favorites.manager")

local M = {}

--- Показать информацию о favorites текущего проекта
function M.show_project_info()
  local info = manager.get_project_info()
  
  local message = string.format(
    [[Flat Favorites Info:

Project Root: %s
Git Project: %s
Data File: %s
Favorites Count: %d

Storage: Per-project (each project has separate favorites)
Auto-cleanup: Enabled (removes invalid paths on load)]],
    info.root,
    info.is_git and "Yes" or "No",
    info.data_file,
    info.count
  )
  
  vim.notify(message, vim.log.levels.INFO)
end

return M
