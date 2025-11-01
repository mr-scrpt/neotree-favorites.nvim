# neotree-favorites.nvim

> 🤖 This plugin was fully generated and refined by AI (Cascade/Claude)

A powerful favorites system for [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) with fuzzy search, gitignore filtering, and per-project storage.

## ✨ Features

### Core Features
- **Compact Storage**: Stores only explicitly added items (roots), not nested files
- **Per-Project Storage**: Each project (git root or cwd) has separate favorites
- **Auto-Cleanup**: Automatically detects and removes deleted/moved paths
- **Visual Indicators**: Shows 📦 for favorites and ⚠️ for invalid paths

### Search & Filtering
- **Built-in Fuzzy Finder**: Fast fuzzy search with `/` (substring) and `#` (fzy algorithm)
- **Gitignore Support**: Automatically hides gitignored files (`node_modules`, build artifacts, etc.)
- **Hidden Files Toggle**: Press `H` to show/hide dotfiles and gitignored items
- **Visual Filtering**: Gitignored/dotfiles displayed in gray when visible

### Performance
- **Size Control**: Warns when favorites file exceeds 15MB
- **Optimized Rendering**: Cached rendering to prevent lag
- **Smart File Watching**: Auto-refresh on file changes

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
    
    -- Filesystem source configuration
    filesystem = {
      components = {
        flat_favorite_indicator = function(config, node, state)
          return require("neotree-favorites.component")(config, node, state)
        end,
      },
      window = {
        mappings = {
          ["s"] = "toggle_flat_favorite",  -- Toggle favorite for current file
          ["I"] = "show_favorites_info",   -- Show favorites info
        },
      },
      renderers = {
        directory = {
          { "indent" },
          { "icon" },
          { "current_filter" },
          { "name" },
          { "flat_favorite_indicator" },  -- Shows 📦 indicator
        },
        file = {
          { "indent" },
          { "icon" },
          { "name", use_git_status_colors = true },
          { "flat_favorite_indicator" },  -- Shows 📦 indicator
          { "git_status" },
        },
      },
    },
    
    -- Flat favorites source configuration
    flat_favorites = {
      bind_to_cwd = false,
      follow_current_file = { enabled = false },
      window = {
        mappings = {
          -- Search mappings
          ["/"] = "fuzzy_finder",              -- Fuzzy search (substring)
          ["#"] = "fuzzy_sorter",              -- Fuzzy search (fzy algorithm)
          ["D"] = "fuzzy_finder_directory",    -- Directory-only search
          ["f"] = "filter_on_submit",          -- Filter with custom pattern
          ["<c-x>"] = "clear_filter",          -- Clear current filter
          
          -- Favorites management
          ["s"] = "remove_invalid_favorites",  -- Remove deleted/moved paths
          ["S"] = "toggle_flat_favorite",      -- Toggle favorite for current node
          ["X"] = "clear_all_flat_favorites",  -- Clear all favorites (with confirmation)
          ["I"] = "show_favorites_info",       -- Show favorites info
          ["H"] = "toggle_hidden",             -- Toggle gitignored/hidden files
        },
      },
      renderers = {
        directory = {
          { "indent" },
          { "icon", use_filtered_colors = true },
          { "current_filter" },
          { "name", use_filtered_colors = true },
          { "filtered_by" },  -- Shows (gitignored), (dotfile), etc.
        },
        file = {
          { "indent" },
          { "icon", use_filtered_colors = true },
          { "name", use_git_status_colors = true, use_filtered_colors = true },
          { "filtered_by" },  -- Shows (gitignored), (dotfile), etc.
          { "git_status" },
        },
      },
    },
    
    -- Global commands
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
      remove_invalid_favorites = function(state)
        require("neotree-favorites.commands").remove_invalid_favorites(state)
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

### Opening Favorites

- `<leader>E` - Open Favorites view (float)
- `<leader>e` - Open file explorer (for adding favorites)

### In Favorites View (`<leader>E`)

#### Search & Filter
- `/` - **Fuzzy finder** (substring match) - Type to search, `Enter` to open
- `#` - **Fuzzy sorter** (fzy algorithm) - Advanced fuzzy matching
- `D` - **Directory search** - Search only directories
- `f` - **Filter on submit** - Custom filter pattern
- `<c-x>` - **Clear filter** - Reset search/filter
- `H` - **Toggle hidden** - Show/hide gitignored and dotfiles

#### Favorites Management
- `S` (Shift+s) - **Toggle favorite** - Add/remove current file/folder
- `s` - **Remove invalid** - Clean up deleted/moved paths
- `X` (Shift+x) - **Clear all** - Remove ALL favorites (with confirmation)
- `I` (Shift+i) - **Show info** - Display favorites statistics

#### Navigation
- `<CR>` (Enter) - Open file/expand folder
- `<` - Previous tab (source)
- `>` - Next tab (source)
- `?` - Show help with all keymaps
- `<esc>` - Close Neo-tree

### In File Explorer (`<leader>e`)

- `s` - **Toggle favorite** - Add/remove current file/folder to favorites
- `I` (Shift+i) - **Show info** - Display favorites statistics

### Visual Indicators

**In file explorer:**
- 📦 - File/folder is in favorites
- ⚠️ - In favorites but deleted/moved

**In favorites view (when `H` pressed):**
- Gray text + `(ignored by .gitignore)` - Gitignored file/folder
- Gray text + `(dotfile)` - Hidden file (starts with `.`)
- Gray text + `(hidden)` - System hidden file

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

### Data Storage
1. Determines project root (git root or cwd)
2. Creates file `~/.local/share/nvim/neotree-favorites/{project_name}.json`
3. Stores ONLY paths of explicitly added items in JSON
4. Nested content NOT stored - loaded dynamically from filesystem

### Tree Building
1. Reads JSON with roots for current project
2. Auto-cleanup - marks non-existent paths as invalid
3. Recursively loads contents of each root from filesystem
4. **Applies gitignore filtering** - hides `node_modules`, build artifacts, etc.
5. **Applies dotfile filtering** - hides files starting with `.`
6. Displays in neo-tree with each root at top level

### Gitignore Filtering
- Searches for `.gitignore` files upward from each directory
- Parses gitignore patterns (supports glob patterns like `*.log`, `build/*`)
- Marks files as `filtered_by.ignored` if they match any pattern
- **Default behavior**: Gitignored files are hidden
- **Press `H`**: Show gitignored files in gray with `(ignored by .gitignore)` label

### Fuzzy Search
- **`/`**: Substring search - matches files containing the search term
- **`#`**: Fzy algorithm - advanced fuzzy matching with scoring
- **`D`**: Directory-only search
- Real-time filtering as you type
- `Enter` to open file, `Esc` to cancel
- Search preserves tree structure (shows parent folders)

### Auto-Cleanup
- Checks path existence on every load
- Non-existent paths automatically marked as invalid
- `s` command to remove all invalid paths at once
- Notification about number of invalid/removed items

## 💡 Examples

### Common Workflow

1. **Add important directories to favorites:**
   ```
   <leader>e          # Open file explorer
   Navigate to src/
   s                  # Add to favorites
   Navigate to config/
   s                  # Add to favorites
   ```

2. **Quick access to favorites:**
   ```
   <leader>E          # Open favorites view
   ```

3. **Search within favorites:**
   ```
   <leader>E          # Open favorites
   /                  # Start fuzzy search
   component          # Type to search
   <Enter>            # Open selected file
   ```

4. **Show hidden files temporarily:**
   ```
   <leader>E          # Open favorites
   H                  # Toggle hidden files
   # Now you can see .env, .gitignore, node_modules/, etc. in gray
   H                  # Hide them again
   ```

5. **Clean up deleted paths:**
   ```
   <leader>E          # Open favorites
   s                  # Remove all invalid paths
   ```

### Use Cases

- **Quick access** to frequently used project directories (`src/`, `config/`, `docs/`)
- **Search** across your favorite files without noise from `node_modules/`
- **Toggle visibility** of gitignored files when you need to edit `.env` or check build output
- **Per-project** organization - different favorites for each workspace

## ❓ FAQ

### Why don't I see `node_modules/` in favorites?

By default, gitignored files and folders are hidden. Press `H` to toggle their visibility. They will appear in gray with `(ignored by .gitignore)` label.

### How do I search within favorites?

Press `/` for substring search or `#` for fzy fuzzy search. Type your query and press `Enter` to open the file, or `Esc` to cancel.

### Can I add individual files to favorites?

Yes! In file explorer (`<leader>e`), navigate to any file and press `s` to add it to favorites.

### What's the difference between `/` and `#` search?

- `/` - **Substring search**: Matches files containing the exact characters in order (e.g., `comp` matches `component.tsx`)
- `#` - **Fzy search**: Advanced fuzzy matching with scoring (e.g., `cmp` matches `component.tsx`)

### How do I remove deleted files from favorites?

Press `s` in the favorites view to remove all invalid (deleted/moved) paths at once.

### Will favorites be shared between different projects?

No, each project has its own favorites file. This is determined by the git root or current working directory.

### Can I customize the keymaps?

Yes! See the [Configuration](#configuration) section for examples.

## 📊 Benefits

### Storage & Organization
- ✅ **Compact** - only roots, not thousands of files
- ✅ **Isolated** - each project has separate favorites
- ✅ **Size control** - warning when favorites exceed 15 MB
- ✅ **Auto-cleanup** - invalid paths marked and easily removable

### Search & Navigation
- ✅ **Fast fuzzy search** - find files instantly with `/` or `#`
- ✅ **Smart filtering** - respects `.gitignore` by default
- ✅ **Visual feedback** - gray text for gitignored/hidden files
- ✅ **Preserved structure** - search shows parent folders

### Performance
- ✅ **Optimized rendering** - cached tree for each project
- ✅ **Smart file watching** - auto-refresh on changes
- ✅ **Minimal overhead** - only loads what's needed

## ⚙️ Configuration

### Default Settings

The plugin works out of the box, but you can customize these settings:

```lua
flat_favorites = {
  bind_to_cwd = false,  -- Don't change root when changing directory
  follow_current_file = { 
    enabled = false     -- Don't auto-expand to current file
  },
  
  -- Filter settings (inherited from neo-tree defaults)
  filtered_items = {
    visible = false,           -- Don't show hidden files by default
    hide_dotfiles = true,      -- Hide files starting with .
    hide_gitignored = true,    -- Hide gitignored files
    hide_by_name = {},         -- Additional files to hide
    hide_by_pattern = {},      -- Patterns to hide
  },
}
```

### Customizing Keymaps

You can change any keymap in the `window.mappings` section:

```lua
flat_favorites = {
  window = {
    mappings = {
      ["/"] = "fuzzy_finder",       -- Change to your preferred key
      ["<c-f>"] = "fuzzy_finder",   -- Add alternative binding
      ["H"] = "toggle_hidden",      -- Keep or change
    },
  },
}
```

### Customizing Renderers

To change how files are displayed:

```lua
flat_favorites = {
  renderers = {
    file = {
      { "indent" },
      { "icon", use_filtered_colors = true },
      { "name", use_filtered_colors = true },
      { "filtered_by" },  -- Remove this line to hide status labels
      { "git_status" },
    },
  },
}
```

## 📝 License

MIT

## 🙏 Credits

Built as a custom source for [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim).

## 🤖 About

This plugin was entirely created using AI assistance (Cascade/Claude-3.5-Sonnet). The implementation includes:

- Custom neo-tree source with per-project storage
- Fuzzy search integration (substring and fzy algorithm)
- Gitignore parsing and filtering
- Auto-cleanup of invalid paths
- Visual indicators and color coding

All code, documentation, and testing were AI-generated through iterative refinement and debugging sessions.

## 🚀 Roadmap

Potential future improvements:

- [ ] Support for `.ignore`, `.dockerignore` files
- [ ] Advanced gitignore patterns (negation `!pattern`, etc.)
- [ ] Export/import favorites between projects
- [ ] Favorites groups/tags
- [ ] Quick jump to favorite by number/letter
