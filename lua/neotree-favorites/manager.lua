-- Менеджер для flat favorites
-- Хранит ТОЛЬКО явно добавленные элементы (корни), без вложенных файлов
-- Per-project storage с автоочисткой

local M = {}

-- Получить project root (git root или cwd)
local function get_project_root()
  -- Пробуем найти git root
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error == 0 and git_root then
    return git_root
  end
  -- Иначе используем cwd
  return vim.fn.getcwd()
end

-- Получить путь к файлу данных для текущего проекта
local function get_data_path()
  local project_root = get_project_root()
  -- Создаем безопасное имя файла из пути проекта
  local safe_name = project_root:gsub("/", "_"):gsub("^_", "")
  return vim.fn.stdpath("data") .. "/neotree-favorites/" .. safe_name .. ".json"
end

-- Кеш для каждого проекта
local favorites_cache = {}

--- Пометить несуществующие пути как invalid
---@param favorites table
---@return table
local function mark_invalid_paths(favorites)
  local invalid_count = 0
  
  for path, data in pairs(favorites) do
    -- Проверяем существует ли путь
    local stat = vim.loop.fs_stat(path)
    if not stat then
      data.invalid = true
      invalid_count = invalid_count + 1
    else
      data.invalid = false
    end
  end
  
  if invalid_count > 0 then
    vim.notify(
      string.format("⚠️  Found %d invalid paths in favorites (deleted/moved). Press 's' to remove.", invalid_count),
      vim.log.levels.WARN
    )
  end
  
  return favorites
end

--- Загрузить flat favorites из файла
---@param check_invalid boolean|nil Проверять ли несуществующие пути (медленно)
---@return table
function M.load_favorites(check_invalid)
  local data_path = get_data_path()
  
  -- Проверяем кеш для текущего проекта
  -- Если check_invalid=true и кеш есть, перепроверяем
  if favorites_cache[data_path] and not check_invalid then
    return favorites_cache[data_path]
  end

  local file = io.open(data_path, "r")
  if not file then
    favorites_cache[data_path] = {}
    return favorites_cache[data_path]
  end

  -- Проверяем размер файла
  local file_size = vim.loop.fs_stat(data_path).size
  local size_mb = file_size / 1024 / 1024
  if size_mb > 15 then
    vim.notify(
      string.format(
        "⚠️  Favorites file is %.1f MB (>15 MB limit)\nConsider cleaning invalid paths",
        size_mb
      ),
      vim.log.levels.WARN
    )
  end

  local content = file:read("*all")
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    -- Помечаем несуществующие пути как invalid только если запрошено
    if check_invalid then
      data = mark_invalid_paths(data)
    end
    favorites_cache[data_path] = data
    return data
  end

  favorites_cache[data_path] = {}
  return favorites_cache[data_path]
end

--- Сохранить flat favorites в файл
---@param favorites table
function M.save_favorites(favorites)
  local data_path = get_data_path()
  
  -- Обновляем кеш
  favorites_cache[data_path] = favorites

  local ok, json = pcall(vim.json.encode, favorites)
  if not ok then
    vim.notify("Failed to encode flat favorites", vim.log.levels.ERROR)
    return
  end

  -- Создаем директорию если не существует
  local dir = vim.fn.stdpath("data") .. "/neotree-favorites"
  vim.fn.mkdir(dir, "p")

  local file = io.open(data_path, "w")
  if not file then
    vim.notify("Failed to save flat favorites", vim.log.levels.ERROR)
    return
  end

  file:write(json)
  file:close()
end

--- Нормализовать путь
---@param path string
---@return string
local function normalize_path(path)
  path = vim.fn.fnamemodify(path, ":p")
  -- Убираем trailing slash если это не корень
  if path:match("^.+/$") then
    path = path:sub(1, -2)
  end
  return path
end

--- Проверить, является ли путь директорией
---@param path string
---@return boolean
local function is_directory(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "directory" or false
end

--- Добавить путь в flat favorites
--- Добавляется ТОЛЬКО сам элемент, без рекурсивного обхода
---@param path string
function M.add_path(path)
  local favorites = M.load_favorites()
  local normalized = normalize_path(path)

  -- Добавляем только сам выбранный элемент
  if is_directory(normalized) then
    favorites[normalized] = {
      type = "directory",
      added_at = os.time(),
    }
    vim.notify("Added to flat favorites: " .. normalized, vim.log.levels.INFO)
  else
    favorites[normalized] = {
      type = "file",
      added_at = os.time(),
    }
    vim.notify("Added to flat favorites: " .. normalized, vim.log.levels.INFO)
  end

  M.save_favorites(favorites)
end

--- Удалить путь из flat favorites
---@param path string
function M.remove_path(path)
  local favorites = M.load_favorites()
  local normalized = normalize_path(path)

  if not favorites[normalized] then
    vim.notify("Path not in flat favorites: " .. normalized, vim.log.levels.WARN)
    return
  end

  favorites[normalized] = nil
  M.save_favorites(favorites)
  vim.notify("Removed from flat favorites: " .. normalized, vim.log.levels.INFO)
end

--- Проверить, находится ли путь в flat favorites
---@param path string
---@return boolean
function M.is_favorite(path)
  local favorites = M.load_favorites()
  local normalized = normalize_path(path)
  return favorites[normalized] ~= nil
end

--- Получить все flat favorites
---@return table
function M.get_all_favorites()
  return M.load_favorites()
end

--- Очистить кеш для текущего проекта
function M.clear_cache()
  local data_path = get_data_path()
  favorites_cache[data_path] = nil
end

--- Очистить весь кеш
function M.clear_all_cache()
  favorites_cache = {}
end

--- Получить информацию о текущем проекте
---@return table
function M.get_project_info()
  local project_root = get_project_root()
  local data_path = get_data_path()
  local favorites = M.load_favorites()
  
  return {
    root = project_root,
    data_file = data_path,
    count = vim.tbl_count(favorites),
    is_git = vim.fn.isdirectory(project_root .. "/.git") == 1,
  }
end

--- Очистить все избранные для текущего проекта
function M.clear_all_favorites()
  local data_path = get_data_path()
  local favorites = M.load_favorites()
  local count = vim.tbl_count(favorites)
  
  if count == 0 then
    vim.notify("No favorites to clear", vim.log.levels.INFO)
    return
  end
  
  -- Подтверждение перед очисткой
  local confirm = vim.fn.confirm(
    string.format("Clear all %d favorites for this project?", count),
    "&Yes\n&No",
    2
  )
  
  if confirm == 1 then
    M.save_favorites({})
    M.clear_cache()
    vim.notify(string.format("Cleared %d favorites", count), vim.log.levels.INFO)
  end
end

return M
