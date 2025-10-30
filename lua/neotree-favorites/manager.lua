-- Manager for flat favorites
-- Stores ONLY explicitly added items (roots), without nested files
-- Per-project storage with auto-cleanup

local M = {}

-- Get project root (git root or cwd)
local function get_project_root()
  -- Try to find git root
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error == 0 and git_root then
    return git_root
  end
  -- Otherwise use cwd
  return vim.fn.getcwd()
end

-- Get data file path for current project
local function get_data_path()
  local project_root = get_project_root()
  -- Create safe filename from project path
  local safe_name = project_root:gsub("/", "_"):gsub("^_", "")
  return vim.fn.stdpath("data") .. "/neotree-favorites/" .. safe_name .. ".json"
end

-- Cache for each project
local favorites_cache = {}

--- Mark non-existent paths as invalid
---@param favorites table
---@return table
local function mark_invalid_paths(favorites)
  local invalid_count = 0
  
  for path, data in pairs(favorites) do
    -- Check if path exists
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

--- Load flat favorites from file
---@param check_invalid boolean|nil Whether to check non-existent paths (slow)
---@return table
function M.load_favorites(check_invalid)
  local data_path = get_data_path()
  
  -- Check cache for current project
  -- If check_invalid=true and cache exists, recheck
  if favorites_cache[data_path] and not check_invalid then
    return favorites_cache[data_path]
  end

  local file = io.open(data_path, "r")
  if not file then
    favorites_cache[data_path] = {}
    return favorites_cache[data_path]
  end

  -- Check file size
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
      -- Mark non-existent paths as invalid only if requested
    if check_invalid then
      data = mark_invalid_paths(data)
    end
    favorites_cache[data_path] = data
    return data
  end

  favorites_cache[data_path] = {}
  return favorites_cache[data_path]
end

--- Save flat favorites to file
---@param favorites table
function M.save_favorites(favorites)
  local data_path = get_data_path()
  
  -- Update cache
  favorites_cache[data_path] = favorites

  local ok, json = pcall(vim.json.encode, favorites)
  if not ok then
    vim.notify("Failed to encode flat favorites", vim.log.levels.ERROR)
    return
  end

  -- Create directory if it doesn't exist
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

--- Normalize path
---@param path string
---@return string
local function normalize_path(path)
  path = vim.fn.fnamemodify(path, ":p")
  -- Remove trailing slash if not root
  if path:match("^.+/$") then
    path = path:sub(1, -2)
  end
  return path
end

--- Check if path is a directory
---@param path string
---@return boolean
local function is_directory(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "directory" or false
end

--- Add path to flat favorites
--- Adds ONLY the item itself, without recursive traversal
---@param path string
function M.add_path(path)
  local favorites = M.load_favorites()
  local normalized = normalize_path(path)

  -- Add only the selected item itself
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

--- Remove path from flat favorites
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

--- Check if path is in flat favorites
---@param path string
---@return boolean
function M.is_favorite(path)
  local favorites = M.load_favorites()
  local normalized = normalize_path(path)
  return favorites[normalized] ~= nil
end

--- Get all flat favorites
---@return table
function M.get_all_favorites()
  return M.load_favorites()
end

--- Clear cache for current project
function M.clear_cache()
  local data_path = get_data_path()
  favorites_cache[data_path] = nil
end

--- Clear all cache
function M.clear_all_cache()
  favorites_cache = {}
end

--- Get information about current project
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

return M
