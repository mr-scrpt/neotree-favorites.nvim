# neotree-favorites.nvim

> 🤖 This plugin was fully generated and refined by AI (Cascade/Claude)

A smart favorites system for [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) with per-project storage and auto-cleanup.

## ✨ Features

- **Compact Storage**: Stores only explicitly added items (roots), not nested files
- **Per-Project Storage**: Each project (git root or cwd) has separate favorites
- **Auto-Cleanup**: Automatically detects and marks deleted/moved paths
- **Visual Indicators**: Shows 📦 for favorites and ⚠️ for invalid paths
- **Size Control**: Warns when favorites file exceeds 15MB
- **Optimized Performance**: Cached rendering to prevent lag

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nvim-neo-tree/neo-tree.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
    "mr-scrpt/neotree-favorites.nvim", -- Add this
  },
  opts = {
    sources = {
      "filesystem",
      "buffers",
      "git_status",
      "flat_favorites", -- Add this
    },
    
    source_selector = {
      winbar = true,
      sources = {
        { source = "filesystem", display_name = "  Files " },
        { source = "flat_favorites", display_name = " 📦 Favorites " },
        { source = "buffers", display_name = "  Buffers " },
        { source = "git_status", display_name = "  Git " },
      },
    },
    
    filesystem = {
      components = {
        flat_favorite_indicator = function(config, node, state)
          return require("neotree-favorites.component")(config, node, state)
        end,
      },
      window = {
        mappings = {
          ["s"] = "toggle_flat_favorite",
          ["I"] = "show_favorites_info",
          ["w"] = "clear_all_flat_favorites",
        },
      },
      renderers = {
        directory = {
          { "indent" },
          { "icon" },
          { "current_filter" },
          { "name" },
          { "flat_favorite_indicator" },
        },
        file = {
          { "indent" },
          { "icon" },
          { "name", use_git_status_colors = true },
          { "flat_favorite_indicator" },
          { "git_status" },
        },
      },
    },
    
    flat_favorites = {
      bind_to_cwd = false,
      follow_current_file = { enabled = false },
      window = {
        mappings = {
          ["s"] = "toggle_flat_favorite",
          ["I"] = "show_favorites_info",
          ["w"] = "clear_all_flat_favorites",
        },
      },
    },
    
    commands = {
      toggle_flat_favorite = function(state)
        require("neotree-favorites.commands").toggle_flat_favorite(state)
      end,
      show_favorites_info = function()
        require("neotree-favorites.info").show_project_info()
      end,
      clear_all_flat_favorites = function(state)
        require("neotree-favorites.commands").clear_all_flat_favorites(state)
      end,
    },
  },
  keys = {
    {
      "<leader>E",
      function()
        require("neo-tree.command").execute({
          source = "flat_favorites",
          toggle = true,
          position = "float",
        })
      end,
      desc = "📦 Flat Favorites",
    },
  },
}
```

## 🎮 Usage

### Keymaps

**Opening:**
- `<leader>E` - Open Favorites
- `<leader>e` - Open file explorer

**Toggle (add/remove):**
- `s` - Toggle favorite (works everywhere)

**Clear all:**
- `w` - Clear all favorites for current project (with confirmation)

**Info:**
- `I` (Shift+i) - Show project info (inside Neo-tree)

**Switching tabs:**
- `<` - Previous tab
- `>` - Next tab
- Click on tab names in winbar to switch

**Other useful commands:**
- `?` - Show help with all available keymaps
- `<esc>` - Close Neo-tree window

### Indicators

In the file explorer (`<leader>e`):
- 📦 - In favorites (exists)
- ⚠️ - In favorites but deleted/moved (press `s` to remove)

## 💾 Storage

**Directory:** `~/.local/share/nvim/neotree-favorites/`

**Files:**
- `home_user_project1.json` - favorites for `/home/user/project1`
- `home_user_project2.json` - favorites for `/home/user/project2`

**Example file content:**
```json
{
  "/home/user/project/src": {
    "type": "directory",
    "added_at": 1730295600,
    "invalid": false
  },
  "/home/user/project/config": {
    "type": "directory",
    "added_at": 1730295700,
    "invalid": false
  }
}
```

## 🔧 How It Works

**Data Storage:**
1. Determines project root (git root or cwd)
2. Creates file `~/.local/share/nvim/neotree-favorites/{project_name}.json`
3. Stores ONLY paths of explicitly added items in JSON
4. Nested content NOT stored - loaded dynamically

**Tree Building:**
1. Reads JSON with roots for current project
2. Auto-cleanup - marks non-existent paths as invalid
3. Recursively loads contents of each root from filesystem
4. Displays in neo-tree with each root at top level

**Auto-Cleanup:**
- Checks path existence on every load
- Non-existent paths automatically marked as invalid
- Notification about number of invalid items

## 📊 Benefits

- ✅ Compact - only roots, not thousands of files
- ✅ Isolated - each project separate
- ✅ Size control - warning when >15 MB
- ✅ Visual indication - ⚠️ for deleted/moved
- ✅ Fast - cache for each project

## 📝 License

MIT

## 🙏 Credits

Built as a custom source for [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim).

## 🤖 About

This plugin was entirely created using AI assistance (Cascade/Claude-3.5-Sonnet). The implementation, documentation, and testing were all AI-generated based on requirements and iterative refinement.
