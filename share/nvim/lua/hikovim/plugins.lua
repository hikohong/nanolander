-- hikovim plugin set — the Neovim replacements for the plugins vendored in
-- ~/.vim, plus what vim here never had: treesitter, a language server client,
-- a completion menu, and the editing plugins behind <C-a> and the [ and ]
-- motions. Managed by lazy.nvim; :Lazy shows what is installed.
--
-- Each entry says which ~/.vim plugin it stands in for, so it is obvious what
-- to delete here if you ever want the old one back (its guard variable in
-- init.vim has to go too).

-- Treesitter highlighting replaces vim's regex syntax highlighting. It is
-- more accurate, but it paints with the @capture groups rather than the ones
-- hiko_color was hand-tuned for, so C code will not look pixel-identical to
-- vim. Set this to false to keep treesitter for folds only and let
-- `syntax on` keep the colours.
local TS_HIGHLIGHT = true

-- copilot_ready — whether Copilot can actually do anything on this machine.
--
-- Two things it needs that nanolander does not provide: Node, which is not in
-- the catalog, and credentials, which mean a subscription and `:Copilot auth`
-- once per machine. Without both, entering insert mode had copilot.lua fetch
-- its language server and announce the download in :messages — on a box that
-- could never use it. Same rule as image.nvim's terminal gate: a plugin that
-- cannot work here says nothing and costs nothing.
--
-- This gates the InsertEnter trigger only, never the plugin itself. lazy
-- refuses to load a spec whose `cond` is false even through its own command
-- (lazy/core/loader.lua), so a `cond` here would take `:Copilot auth` away
-- from the one machine that needs to run it — there would be no way in.
local function copilot_ready()
  if vim.fn.executable('node') == 0 then return false end
  -- Where copilot.lua's own auth module looks: $XDG_CONFIG_HOME when that is
  -- a directory, ~/.config otherwise. The directory rather than the file
  -- inside it, since the credential filename is the plugin's business and has
  -- changed before — auth.db today, hosts.json in older releases.
  local config = vim.fn.expand('$XDG_CONFIG_HOME')
  if vim.fn.isdirectory(config) == 0 then config = vim.fn.expand('~/.config') end
  return vim.fn.isdirectory(config .. '/github-copilot') == 1
end

local TS_LANGUAGES = {
  'bash', 'c', 'cmake', 'cpp', 'diff', 'dockerfile', 'git_config', 'gitcommit',
  'json', 'lua', 'make', 'markdown', 'python', 'query', 'rust', 'toml', 'vim',
  'vimdoc', 'yaml',
}

-- Ported from ~/.vim/autoload/airline/themes/badwolf.vim, the theme
-- ~/.vimrc selects, so the status line keeps the colours you are used to.
local badwolf = {
  normal = {
    a = { fg = '#141413', bg = '#aeee00', gui = 'bold' }, -- blackestgravel on lime
    b = { fg = '#f4cf86', bg = '#45413b' },              -- dirtyblonde on deepgravel
    c = { fg = '#8cffba', bg = '#242321' },               -- saltwatertaffy on darkgravel
  },
  insert = {
    a = { fg = '#141413', bg = '#0a9dff', gui = 'bold' }, -- tardis
    b = { fg = '#f4cf86', bg = '#005fff' },
    c = { fg = '#0a9dff', bg = '#242321' },
  },
  visual = {
    a = { fg = '#141413', bg = '#ffa724', gui = 'bold' }, -- orange
    b = { fg = '#000000', bg = '#fade3e' },               -- dalespale
    c = { fg = '#000000', bg = '#b88853' },               -- toffee
  },
  replace = {
    a = { fg = '#141413', bg = '#ff9eb8', gui = 'bold' }, -- dress
    b = { fg = '#f4cf86', bg = '#005fff' },
    c = { fg = '#0a9dff', bg = '#242321' },
  },
  inactive = {
    a = { fg = '#242321', bg = '#45413b' },
    b = { fg = '#242321', bg = '#45413b' },
    c = { fg = '#666462', bg = '#242321' },
  },
}

return {
  -- Icons for lualine, aerial, oil and fzf-lua. Needs the Nerd Font
  -- nanolander installs; without it these show boxes.
  { 'nvim-tree/nvim-web-devicons', lazy = true },

  -----------------------------------------------------------------------
  -- syntax  ->  nvim-treesitter
  -----------------------------------------------------------------------
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = function()
      pcall(function() require('nvim-treesitter').update() end)
    end,
    config = function()
      local ts = require('nvim-treesitter')
      pcall(function() ts.setup({}) end)

      -- Compiling a parser needs the tree-sitter CLI (nanolander installs it)
      -- and a C compiler. Without the CLI there is nothing to gain from
      -- asking on every start, and Neovim already ships parsers for c, lua,
      -- markdown, query, vim and vimdoc, so those keep working regardless.
      -- Languages already installed are skipped.
      if vim.fn.executable('tree-sitter') == 1 then
        pcall(function() ts.install(TS_LANGUAGES) end)
      end

      if not TS_HIGHLIGHT then return end
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('hikovim_treesitter', { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match)
          if not lang then return end
          pcall(vim.treesitter.start, ev.buf, lang)
        end,
      })
    end,
  },

  -----------------------------------------------------------------------
  -- cscope + ctags  ->  a real language server
  -- Config data only; the servers are enabled in hikovim/lsp.lua.
  -----------------------------------------------------------------------
  { 'neovim/nvim-lspconfig', lazy = false },

  -----------------------------------------------------------------------
  -- taglist.vim + tagbar.vim  ->  aerial.nvim
  -- Same ,tb toggle, but the outline comes from the language server or
  -- treesitter, so there is no tags file to regenerate.
  -----------------------------------------------------------------------
  {
    'stevearc/aerial.nvim',
    cmd = { 'AerialToggle', 'AerialOpen', 'AerialNavToggle' },
    opts = {
      -- Tlist_Use_Right_Window = 1, Tlist_WinWidth = 60
      -- resize_to_content would have aerial widen its own window every time
      -- it redraws, which in the IDE layout drags the 4:1 column ratio around.
      layout = {
        default_direction = 'right', min_width = 40, max_width = 60,
        resize_to_content = false,
      },
      -- let g:tagbar_sort = 0 — file order, not alphabetical
      filter_kind = false,
      show_guides = true,
      close_on_select = false,
      attach_mode = 'global',
    },
  },

  -----------------------------------------------------------------------
  -- gitgutter.vim  ->  gitsigns.nvim
  -----------------------------------------------------------------------
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      signcolumn = true,
      current_line_blame = false,   -- ,gb toggles it, see hikovim/keys.lua
      preview_config = { border = 'single' },
    },
  },

  -----------------------------------------------------------------------
  -- vim-airline  ->  lualine.nvim, wearing the badwolf palette and the
  -- separators ~/.vimrc picked.
  -----------------------------------------------------------------------
  {
    'nvim-lualine/lualine.nvim',
    lazy = false,
    opts = {
      options = {
        theme = badwolf,
        section_separators = { left = '▶', right = '◀' },
        component_separators = { left = '»', right = '«' },
        globalstatus = false,
      },
      sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = { { 'filename', path = 1 } },
        -- ~/.vimrc's statusline showed the indent settings; keep that habit.
        lualine_x = {
          function() return 'ts=' .. vim.bo.tabstop .. ':sw=' .. vim.bo.shiftwidth end,
          'encoding', 'filetype',
        },
        lualine_y = { 'progress' },
        lualine_z = { 'location' },
      },
      -- let g:airline#extensions#tabline#enabled = 1
      tabline = {
        -- HikovimTabSel and HikovimTab are defined in hikovim/ide.lua, which
        -- paints the terminal pane's strip with the same two groups. badwolf's
        -- own inactive colours are too dark to read a filename through.
        lualine_a = {
          { 'buffers', mode = 2, buffers_color = { active = 'HikovimTabSel', inactive = 'HikovimTab' } },
        },
        lualine_z = { 'tabs' },
      },
      extensions = { 'aerial', 'quickfix', 'lazy' },
    },
  },

  -----------------------------------------------------------------------
  -- NERDTree  ->  oil.nvim. A directory is a normal buffer: dd deletes,
  -- p pastes, :w applies. `-` opens the parent, as oil does everywhere.
  --
  -- oil is the editor of directories, and stays on <F5> and on every :e of a
  -- directory. It shows one directory at a time by design, which is why the
  -- IDE layout's explorer pane holds neo-tree instead — see below.
  -----------------------------------------------------------------------
  {
    'stevearc/oil.nvim',
    lazy = false,
    opts = {
      default_file_explorer = true,
      view_options = { show_hidden = true },
      keymaps = { ['q'] = 'actions.close' },
    },
  },

  -----------------------------------------------------------------------
  -- NERDTree's other half  ->  neo-tree.nvim, the hierarchical list in the
  -- IDE layout's bottom-right pane. oil cannot do this: it is a
  -- single-directory buffer on purpose, so a whole-project tree needs a
  -- second plugin rather than a setting.
  --
  -- The two do not overlap: neo-tree navigates, oil edits. Nothing here
  -- hijacks netrw, because oil already has that job.
  -----------------------------------------------------------------------
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    cmd = 'Neotree',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-tree/nvim-web-devicons',
    },
    opts = {
      -- The layout owns the window, so neo-tree must render into the one it
      -- is given rather than opening a sidebar of its own.
      window = { position = 'current' },
      -- Never take the session down: the layout decides what happens when the
      -- last file closes, in ide.lua's editor_gone.
      close_if_last_window = false,
      popup_border_style = 'single',
      enable_git_status = true,
      enable_diagnostics = true,
      -- A file opened from the tree must not land in the terminal pane or the
      -- outline. ide.lua's enforce would move it out again, but naming the
      -- types here means it never goes there in the first place.
      --
      -- This list only applies to a neo-tree that has a window to choose from.
      -- At position 'current' it has none — see the handler below.
      open_files_do_not_replace_types = { 'terminal', 'aerial', 'qf', 'oil' },
      -- Where a file opened from the tree goes. Position 'current' means
      -- neo-tree opens it in the window it is already in, which is the explorer
      -- pane, and the layout then has to move it. That is a turn of the loop
      -- too late for image.nvim, which draws a picture into whichever window
      -- the buffer first appeared in and leaves it there. So the layout answers
      -- this event and puts the file in the editor pane itself; see
      -- ide.tree_open_request. Returning nothing leaves neo-tree's own logic in
      -- charge, which is what happens with the layout off.
      event_handlers = {
        {
          event = 'file_open_requested',
          handler = function(args)
            local ok, ide = pcall(require, 'hikovim.ide')
            if not ok then return nil end
            return ide.tree_open_request(args)
          end,
        },
      },
      filesystem = {
        -- <CR> and a double click on a video or a picture hand it to the
        -- system's own application instead of previewing it: `open` on macOS, so
        -- the LaunchServices binding decides — VLC for a video on a machine that
        -- has run bin/vlc-default, and whatever already opens pictures there.
        -- Both keys are bound because both mean "I have chosen this one"; a
        -- single click means "show me this one" and still previews. Every other
        -- file, and a directory, keep neo-tree's own open. See ide.tree_open.
        --
        -- Bound on the source rather than globally: the fall-through calls the
        -- filesystem source's own open, so this must not reach a source that
        -- would be handed the wrong one.
        window = {
          mappings = (function()
            local choose = {
              function(state)
                local ok, ide = pcall(require, 'hikovim.ide')
                if not ok then return end
                ide.tree_open(state)
              end,
              desc = 'open — a video or picture goes to the system',
            }
            return { ['<CR>'] = choose, ['<2-LeftMouse>'] = choose }
          end)(),
        },
        -- oil is the netrw replacement. Two plugins claiming it is how you
        -- get a directory opening in whichever one loaded last.
        hijack_netrw_behavior = 'disabled',
        follow_current_file = { enabled = true, leave_dirs_open = true },
        use_libuv_file_watcher = true,
        filtered_items = { visible = true, hide_dotfiles = false, hide_gitignored = false },
      },
      default_component_configs = {
        indent = { with_expanders = true },
        git_status = { symbols = { added = '+', modified = '~', deleted = '✖', renamed = '➜' } },
      },
    },
  },

  -----------------------------------------------------------------------
  -- Images in the editor pane  ->  image.nvim, over sixel.
  --
  -- Click a .png in the tree and the picture appears where the file contents
  -- would, the way yazi previews one.
  --
  -- The backend is the whole story here. Every Neovim image plugin draws with
  -- the Kitty graphics protocol — snacks.nvim has no iTerm2 code path at all,
  -- and image.nvim's default is kitty too. iTerm2 does not speak that; it has
  -- its own inline-images protocol, which is why yazi can show images here and
  -- these plugins cannot. What iTerm2 *does* speak is sixel, and sixel is
  -- image.nvim's third backend. It is an escape sequence like the others, so it
  -- survives SSH.
  --
  -- Sixel is the slow one — image.nvim says so itself. If it drags, or you move
  -- to a terminal that speaks the Kitty protocol (Ghostty, Kitty, WezTerm),
  -- `backend = 'kitty'` is the only line that changes.
  -----------------------------------------------------------------------
  {
    '3rd/image.nvim',
    lazy = false,
    -- Nothing to draw into without a UI, and it says so out loud: a headless
    -- Neovim printed "cannot query terminal size" on every start, which put a
    -- line in :messages that both scripts and the clean-load check read.
    --
    -- Two signals, either of which is enough, because the failure modes are not
    -- symmetric: loading this where it cannot draw costs one warning line,
    -- while failing to load it in a real terminal means the feature silently
    -- does not exist. So it errs toward loading.
    cond = function()
      return #vim.api.nvim_list_uis() > 0 or vim.fn.has('ttyout') == 1
    end,
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = {
      backend = 'sixel',
      -- Shells out to ImageMagick's identify and convert, which nanolander
      -- installs. The other processor wants a LuaRocks build of the magick
      -- rock, which is a build toolchain for no gain here.
      processor = 'magick_cli',
      -- Opening one of these shows the picture rather than the bytes. This is
      -- the setting the whole thing rests on.
      --
      -- The list lives in media.lua, because ide.lua needs the same one to
      -- decide what <CR> and a double click hand to the system viewer. Asking
      -- image.nvim was not an option: the module it returns has no accessor for
      -- its own options, so a second copy here is how the editor would end up
      -- previewing a format the tree refuses to open, or the reverse.
      hijack_file_patterns = require('hikovim.media').IMAGE,
      -- Four panes means windows are always next to each other, and a sixel
      -- image is painted on the terminal rather than owned by a buffer: without
      -- this it stays on screen over whatever moves in front of it.
      window_overlap_clear_enabled = true,
      -- Fill the editor pane. The default gives an image half the height.
      max_width_window_percentage = 100,
      max_height_window_percentage = 100,
      -- Do not keep drawing into a terminal that is not being looked at.
      editor_only_render_when_focused = true,
      tmux_show_only_in_active_window = true,
      integrations = { markdown = { enabled = true } },
    },
  },

  -----------------------------------------------------------------------
  -- The nested-Neovim problem  ->  flatten.nvim.
  --
  -- `nvim file` typed in the terminal pane, or a $EDITOR call from git in
  -- there, would otherwise start a second Neovim *inside* the pane: a
  -- separate process, so nothing in ide.lua can see it, let alone move the
  -- file to the editor pane. flatten intercepts that launch and hands the
  -- file to this instance instead.
  --
  -- priority puts it ahead of everything that reads the buffer list, because
  -- it has to answer the guest before any of them see a buffer.
  -----------------------------------------------------------------------
  {
    'willothy/flatten.nvim',
    lazy = false,
    priority = 1001,
    opts = {
      window = {
        -- Put the file in the one window of this layout that shows file
        -- contents, and fall back to the current window so flatten still
        -- works with the layout off, where any window will do.
        --
        -- A function handler does the opening itself and returns
        -- `bufnr, winnr` — buffer first. flatten's README documents that pair
        -- the other way round, but core.lua destructures `bufnr, winnr`, and
        -- returning a window id first makes flatten treat it as a buffer
        -- number and throw from its BufEnter handler. The buffer is also what
        -- it reads the filetype from to decide whether to block, so the order
        -- is load-bearing rather than cosmetic.
        open = function(o)
          local target
          local ok, ide = pcall(require, 'hikovim.ide')
          if ok then target = ide.editor_win() end
          if not (target and vim.api.nvim_win_is_valid(target)) then
            target = vim.api.nvim_get_current_win()
          end
          -- Piped stdin first, then the last file named, matching what
          -- flatten's own string handlers focus on.
          local focus = o.stdin_buf or o.files[#o.files]
          if not focus then return nil, nil end
          vim.api.nvim_win_set_buf(target, focus.bufnr)
          vim.api.nvim_set_current_win(target)
          return focus.bufnr, target
        end,
      },
      -- Defaults, spelled out because they are the reason `git commit` works:
      -- the guest blocks until the buffer is closed, so git waits for the
      -- message instead of committing an empty one.
      block_for = { gitcommit = true, gitrebase = true },
    },
  },

  -----------------------------------------------------------------------
  -- The picker the <C-\> family and the ,f maps run through. Uses the fzf
  -- binary nanolander installs.
  -----------------------------------------------------------------------
  {
    'ibhagwan/fzf-lua',
    cmd = 'FzfLua',
    opts = {
      winopts = { height = 0.85, width = 0.85, preview = { layout = 'vertical' } },
      grep = { rg_glob = true },
    },
  },

  -----------------------------------------------------------------------
  -- The completion menu. ~/.vimrc's OmniCppComplete block is commented out
  -- with a note that its popup interfered with typing, and for years the
  -- answer here was that completion stays on <C-x><C-o>. blink.cmp is the
  -- reason that changed: it ranks by a real fuzzy match, shows the menu
  -- without stealing a keystroke, and every key that drives it falls back to
  -- what vim does when the menu is closed.
  -----------------------------------------------------------------------
  {
    'saghen/blink.cmp',
    -- A tagged release, because blink publishes a prebuilt fuzzy matcher per
    -- tag. Building it from source would want cargo on a box whose whole
    -- point is that it just lands.
    version = '*',
    event = 'InsertEnter',
    opts = {
      -- The matcher is Rust. 'prefer_rust' takes the prebuilt binary when it
      -- is there and drops to the Lua implementation when it is not —
      -- silently, which is the point: 'prefer_rust_with_warning' writes to
      -- :messages on every start, and a clean :messages is what the headless
      -- load check asserts. Slower on a huge candidate list, and correct
      -- everywhere.
      fuzzy = { implementation = 'prefer_rust' },
      keymap = {
        preset = 'default',
        -- <C-k> is vim's digraph key. blink's default preset puts signature
        -- help there, which is the one key in that preset that takes
        -- something vim already uses, so it moves and digraphs stay.
        ['<C-k>'] = {},
        ['<C-s>'] = { 'show_signature', 'hide_signature', 'fallback' },
      },
      completion = {
        -- The menu follows the popup transparency ~/.vimrc chose.
        menu = { winblend = vim.o.pumblend },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        -- The rest of the line, in grey, ahead of the cursor. This is the
        -- half people mean by predictive text, and it costs no extra key:
        -- <C-y> accepts whatever the menu has selected.
        ghost_text = { enabled = true },
      },
      signature = { enabled = true, window = { winblend = vim.o.pumblend } },
      sources = { default = { 'lsp', 'path', 'snippets', 'buffer' } },
    },
  },

  -----------------------------------------------------------------------
  -- Rename with the result visible while you type it. Neovim's own grn
  -- renames in one go; this shows every call site changing as you edit.
  -----------------------------------------------------------------------
  {
    'smjonas/inc-rename.nvim',
    cmd = 'IncRename',
    config = true,
  },

  -----------------------------------------------------------------------
  -- [ and ] motions for the things vim has no motion for: a comment block, a
  -- diagnostic, an indent level, the jumplist.
  -----------------------------------------------------------------------
  {
    'nvim-mini/mini.bracketed',
    event = 'BufReadPost',
    config = function()
      require('mini.bracketed').setup({
        -- Off: vim already has these, or hikovim does.
        file     = { suffix = '' },   -- :next / :prev
        window   = { suffix = '' },   -- <C-w>w
        quickfix = { suffix = '' },   -- :cnext / :cprev
        yank     = { suffix = '' },
        -- ]c and [c are the git hunks in hikovim/keys.lua, and vimdiff's own
        -- change motion inside nvim -d. mini.bracketed would take both for
        -- its comment motion, so the comment target is off rather than moved:
        -- keys keep their letters here.
        comment  = { suffix = '' },
        -- t is taken by ]t / [t for tags, so treesitter nodes go on n.
        treesitter = { suffix = 'n' },
      })
    end,
  },

  -----------------------------------------------------------------------
  -- <C-a> and <C-x> on more than a number: a date, a bool, a semver, and
  -- let/const. vim's own increment only knows integers.
  -----------------------------------------------------------------------
  {
    'monaqa/dial.nvim',
    keys = {
      { '<C-a>', function() return require('dial.map').inc_normal() end,
        expr = true, desc = 'Increment' },
      { '<C-x>', function() return require('dial.map').dec_normal() end,
        expr = true, desc = 'Decrement' },
    },
    config = function()
      local augend = require('dial.augend')
      require('dial.config').augends:register_group({
        default = {
          augend.integer.alias.decimal,
          augend.integer.alias.hex,
          augend.date.alias['%Y/%m/%d'],
          augend.constant.alias.bool,
          augend.semver.alias.semver,
          augend.constant.new({ elements = { 'let', 'const' } }),
        },
      })
    end,
  },

  -----------------------------------------------------------------------
  -- Copilot's inline suggestion — the other half of predictive text, and the
  -- one entry here that cannot simply land: see copilot_ready above for what
  -- it needs and why only the InsertEnter trigger is gated. A machine that
  -- has signed in gets the grey suggestion as it types; one that has not gets
  -- blink.cmp's menu and silence.
  -----------------------------------------------------------------------
  {
    'zbirenbaum/copilot.lua',
    -- Always reachable, so `:Copilot auth` and `:Copilot status` work and can
    -- say what is missing. Auto-loading is what copilot_ready gates: signing
    -- in takes effect on the next start, like any other configuration change.
    cmd = 'Copilot',
    event = copilot_ready() and 'InsertEnter' or nil,
    opts = {
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept      = '<C-l>',
          accept_word = '<M-l>',
          accept_line = '<M-S-l>',
          next        = '<M-]>',
          prev        = '<M-[>',
          dismiss     = '<C-]>',
        },
      },
      filetypes = { markdown = true, help = true },
    },
  },
}
