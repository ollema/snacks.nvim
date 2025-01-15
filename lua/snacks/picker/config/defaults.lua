local M = {}

---@alias snacks.picker.Extmark vim.api.keyset.set_extmark|{col:number, row?:number}
---@alias snacks.picker.Text {[1]:string, [2]:string?, virtual?:boolean}
---@alias snacks.picker.Highlight snacks.picker.Text|snacks.picker.Extmark
---@alias snacks.picker.format fun(item:snacks.picker.Item, picker:snacks.Picker):snacks.picker.Highlight[]
---@alias snacks.picker.preview fun(ctx: snacks.picker.preview.ctx):boolean?
---@alias snacks.picker.sort fun(a:snacks.picker.Item, b:snacks.picker.Item):boolean

--- Generic filter used by finders to pre-filter items
---@class snacks.picker.filter.Config
---@field cwd? boolean|string only show files for the given cwd
---@field buf? boolean|number only show items for the current or given buffer
---@field paths? table<string, boolean> only show items that include or exclude the given paths
---@field filter? fun(item:snacks.picker.finder.Item):boolean custom filter function

---@class snacks.picker.matcher.Config
---@field fuzzy? boolean use fuzzy matching (defaults to true)
---@field smartcase? boolean use smartcase (defaults to true)
---@field ignorecase? boolean use ignorecase (defaults to true)

---@class snacks.picker.Item
---@field [string] any
---@field idx number
---@field score number
---@field match_tick? number
---@field text string
---@field pos? {[1]:number, [2]:number}
---@field end_pos? {[1]:number, [2]:number}
---@field highlights? snacks.picker.Highlight[][]

---@class snacks.picker.finder.Item: snacks.picker.Item
---@field idx? number
---@field score? number

---@class snacks.picker.sources.Config

---@class snacks.picker.preview.Config
---@field man_pager? string MANPAGER env to use for `man` preview
---@field file snacks.picker.preview.file.Config

---@class snacks.picker.preview.file.Config
---@field max_size? number default 1MB
---@field max_line_length? number defaults to 500
---@field ft? string defaults to auto-detect

---@class snacks.picker.layout.Config
---@field layout snacks.layout.Box
---@field reverse? boolean when true, the list will be reversed (bottom-up)
---@field fullscreen? boolean open in fullscreen
---@field cycle? boolean cycle through the list
---@field preview? boolean|"main" show preview window in the picker or the main window
---@field preset? string|fun(source:string):string

---@class snacks.picker.win.Config
---@field input? snacks.win.Config|{} input window config
---@field list? snacks.win.Config|{} result list window config
---@field preview? snacks.win.Config|{} preview window config

---@class snacks.picker.Config
---@field source? string source name and config to use
---@field pattern? string|fun(picker:snacks.Picker):string pattern used to filter items by the matcher
---@field search? string|fun(picker:snacks.Picker):string search string used by finders
---@field cwd? string current working directory
---@field live? boolean when true, typing will trigger live searches
---@field limit? number when set, the finder will stop after finding this number of items. useful for live searches
---@field ui_select? boolean set `vim.ui.select` to a snacks picker
--- Source definition
---@field items? snacks.picker.finder.Item[] items to show instead of using a finder
---@field format? snacks.picker.format|string format function or preset
---@field finder? snacks.picker.finder|string finder function or preset
---@field preview? snacks.picker.preview|string preview function or preset
---@field matcher? snacks.picker.matcher.Config matcher config
---@field sort? snacks.picker.sort|snacks.picker.sort.Config sort function or config
--- UI
---@field win? snacks.picker.win.Config
---@field layout? snacks.picker.layout.Config|string|{}|fun(source:string):(snacks.picker.layout.Config|string)
---@field icons? snacks.picker.icons
---@field prompt? string prompt text / icon
--- Preset options
---@field previewers? snacks.picker.preview.Config
---@field sources? snacks.picker.sources.Config|{}
---@field layouts? table<string, snacks.picker.layout.Config>
--- Actions
---@field actions? table<string, snacks.picker.Action.spec> actions used by keymaps
---@field confirm? snacks.picker.Action.spec shortcut for confirm action
---@field auto_confirm? boolean automatically confirm if there is only one item
---@field main? snacks.picker.main.Config main editor window config
---@field on_change? fun(picker:snacks.Picker, item:snacks.picker.Item) called when the cursor changes
---@field on_show? fun(picker:snacks.Picker) called when the picker is shown
local defaults = {
  prompt = " ",
  sources = {},
  layout = {
    cycle = true,
    --- Use the default layout or vertical if the window is too narrow
    preset = function()
      return vim.o.columns >= 120 and "default" or "vertical"
    end,
  },
  ui_select = true, -- replace `vim.ui.select` with the snacks picker
  previewers = {
    file = {
      max_size = 1024 * 1024, -- 1MB
      max_line_length = 500,
    },
  },
  win = {
    -- input window
    input = {
      keys = {
        ["<Esc>"] = "close",
        -- to close the picker on ESC instead of going to normal mode,
        -- add the following keymap to your config
        -- ["<Esc>"] = { "close", mode = { "n", "i" } },
        ["<CR>"] = "confirm",
        ["G"] = "list_bottom",
        ["gg"] = "list_top",
        ["j"] = "list_down",
        ["k"] = "list_up",
        ["/"] = "toggle_focus",
        ["q"] = "close",
        ["?"] = "toggle_help",
        ["<a-m>"] = { "toggle_maximize", mode = { "i", "n" } },
        ["<a-p>"] = { "toggle_preview", mode = { "i", "n" } },
        ["<a-w>"] = { "cycle_win", mode = { "i", "n" } },
        ["<C-w>"] = { "<c-s-w>", mode = { "i" }, expr = true, desc = "delete word" },
        ["<C-Up>"] = { "history_back", mode = { "i", "n" } },
        ["<C-Down>"] = { "history_forward", mode = { "i", "n" } },
        ["<Tab>"] = { "select_and_next", mode = { "i", "n" } },
        ["<S-Tab>"] = { "select_and_prev", mode = { "i", "n" } },
        ["<Down>"] = { "list_down", mode = { "i", "n" } },
        ["<Up>"] = { "list_up", mode = { "i", "n" } },
        ["<c-j>"] = { "list_down", mode = { "i", "n" } },
        ["<c-k>"] = { "list_up", mode = { "i", "n" } },
        ["<c-n>"] = { "list_down", mode = { "i", "n" } },
        ["<c-p>"] = { "list_up", mode = { "i", "n" } },
        ["<c-b>"] = { "preview_scroll_up", mode = { "i", "n" } },
        ["<c-d>"] = { "list_scroll_down", mode = { "i", "n" } },
        ["<c-f>"] = { "preview_scroll_down", mode = { "i", "n" } },
        ["<c-g>"] = { "toggle_live", mode = { "i", "n" } },
        ["<c-u>"] = { "list_scroll_up", mode = { "i", "n" } },
        ["<ScrollWheelDown>"] = { "list_scroll_wheel_down", mode = { "i", "n" } },
        ["<ScrollWheelUp>"] = { "list_scroll_wheel_up", mode = { "i", "n" } },
        ["<c-v>"] = { "edit_vsplit", mode = { "i", "n" } },
        ["<c-s>"] = { "edit_split", mode = { "i", "n" } },
        ["<c-q>"] = { "qflist", mode = { "i", "n" } },
        ["<a-i>"] = { "toggle_ignored", mode = { "i", "n" } },
        ["<a-h>"] = { "toggle_hidden", mode = { "i", "n" } },
      },
      b = {
        minipairs_disable = true,
      },
    },
    -- result list window
    list = {
      keys = {
        ["<CR>"] = "confirm",
        ["gg"] = "list_top",
        ["G"] = "list_bottom",
        ["i"] = "focus_input",
        ["j"] = "list_down",
        ["k"] = "list_up",
        ["q"] = "close",
        ["<Tab>"] = "select_and_next",
        ["<S-Tab>"] = "select_and_prev",
        ["<Down>"] = "list_down",
        ["<Up>"] = "list_up",
        ["<c-d>"] = "list_scroll_down",
        ["<c-u>"] = "list_scroll_up",
        ["zt"] = "list_scroll_top",
        ["zb"] = "list_scroll_bottom",
        ["zz"] = "list_scroll_center",
        ["/"] = "toggle_focus",
        ["<ScrollWheelDown>"] = "list_scroll_wheel_down",
        ["<ScrollWheelUp>"] = "list_scroll_wheel_up",
        ["<c-f>"] = "preview_scroll_down",
        ["<c-b>"] = "preview_scroll_up",
        ["<c-v>"] = "edit_vsplit",
        ["<c-s>"] = "edit_split",
        ["<c-j>"] = "list_down",
        ["<c-k>"] = "list_up",
        ["<c-n>"] = "list_down",
        ["<c-p>"] = "list_up",
        ["<a-w>"] = "cycle_win",
        ["<Esc>"] = "close",
      },
    },
    -- preview window
    preview = {
      minimal = false,
      wo = {
        cursorline = false,
        colorcolumn = "",
      },
      keys = {
        ["<Esc>"] = "close",
        ["q"] = "close",
        ["i"] = "focus_input",
        ["<ScrollWheelDown>"] = "list_scroll_wheel_down",
        ["<ScrollWheelUp>"] = "list_scroll_wheel_up",
        ["<a-w>"] = "cycle_win",
      },
    },
  },
  ---@class snacks.picker.icons
    -- stylua: ignore
  icons = {
    files = {
      enabled = true, -- show file icons
    },
    indent = {
      vertical    = "│ ",
      middle = "├╴",
      last   = "└╴",
    },
    ui = {
      live        = "󰐰 ",
      selected    = "● ",
      -- selected = " ",
    },
    git = {
      commit = "󰜘 ",
    },
    diagnostics = {
      Error = " ",
      Warn  = " ",
      Hint  = " ",
      Info  = " ",
    },
    kinds = {
      Array         = " ",
      Boolean       = "󰨙 ",
      Class         = " ",
      Color         = " ",
      Control       = " ",
      Collapsed     = " ",
      Constant      = "󰏿 ",
      Constructor   = " ",
      Copilot       = " ",
      Enum          = " ",
      EnumMember    = " ",
      Event         = " ",
      Field         = " ",
      File          = " ",
      Folder        = " ",
      Function      = "󰊕 ",
      Interface     = " ",
      Key           = " ",
      Keyword       = " ",
      Method        = "󰊕 ",
      Module        = " ",
      Namespace     = "󰦮 ",
      Null          = " ",
      Number        = "󰎠 ",
      Object        = " ",
      Operator      = " ",
      Package       = " ",
      Property      = " ",
      Reference     = " ",
      Snippet       = "󱄽 ",
      String        = " ",
      Struct        = "󰆼 ",
      Text          = " ",
      TypeParameter = " ",
      Unit          = " ",
      Uknown        = " ",
      Value         = " ",
      Variable      = "󰀫 ",
    },
  },
}

M.defaults = defaults

return M