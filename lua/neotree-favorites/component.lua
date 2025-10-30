-- Custom component for displaying flat favorites indicator in neo-tree
local manager = require("neotree-favorites.manager")
local highlights = require("neo-tree.ui.highlights")

-- Favorites cache for current rendering session
local favorites_cache = nil
local cache_time = 0

return function(config, node, state)
  local text = ""
  local highlight = config.highlight or highlights.DIM_TEXT

  -- Cache favorites for 100ms to avoid loading for each node
  local now = vim.loop.now()
  if not favorites_cache or (now - cache_time) > 100 then
    favorites_cache = manager.get_all_favorites()
    cache_time = now
  end

  -- Check if path is in flat favorites
  if node.path and favorites_cache[node.path] then
    local fav_info = favorites_cache[node.path]
    
    -- Show invalid only in flat_favorites view, not in filesystem
    if state.name == "flat_favorites" and fav_info.invalid then
      text = "⚠️ "
      highlight = "NeoTreeGitDeleted"
    else
      text = "📦"
      highlight = "NeoTreeGitModified"
    end
  else
    text = "  " -- Two spaces for alignment
  end

  return {
    text = text,
    highlight = highlight,
  }
end
