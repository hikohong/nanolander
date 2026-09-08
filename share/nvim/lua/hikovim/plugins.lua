-- hikovim plugin set — the Neovim replacements for the plugins vendored in
-- ~/.vim, plus the two things vim never had: treesitter and a language server
-- client. Managed by lazy.nvim; :Lazy shows what is installed.
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
      layout = { default_direction = 'right', min_width = 40, max_width = 60 },
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
        lualine_a = { { 'buffers', mode = 2 } },
        lualine_z = { 'tabs' },
      },
      extensions = { 'aerial', 'quickfix', 'lazy' },
    },
  },

  -----------------------------------------------------------------------
  -- NERDTree  ->  oil.nvim. A directory is a normal buffer: dd deletes,
  -- p pastes, :w applies. `-` opens the parent, as oil does everywhere.
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
}
