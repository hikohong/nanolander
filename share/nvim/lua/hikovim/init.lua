-- hikovim — layer 3 of the nanolander Neovim configuration.
--
-- Everything here runs after ~/.vimrc, so it deliberately wins over the vim
-- settings. It only overrides what has a genuinely better Neovim answer;
-- every other mapping and option from hikovim is left exactly as it was.
--
-- Nothing in this file is required for Neovim to start. If lazy.nvim cannot
-- be fetched — no network on a freshly landed box — you get a warning and a
-- working editor with layers 1 and 2.

local M = {}

local LAZY_URL = 'https://github.com/folke/lazy.nvim.git'

-- bootstrap_lazy — clone lazy.nvim on first start and put it on the
-- runtimepath. Returns false when it is not usable, so the caller can carry
-- on without plugins instead of throwing errors at every keystroke.
local function bootstrap_lazy()
  local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
  local uv = vim.uv or vim.loop

  if not uv.fs_stat(lazypath) then
    if vim.fn.executable('git') == 0 then
      vim.notify('[nanolander] git is missing, so the plugin layer is off.',
        vim.log.levels.WARN)
      return false
    end
    vim.notify('[nanolander] first start: fetching lazy.nvim…', vim.log.levels.INFO)
    local out = vim.fn.system({
      'git', 'clone', '--filter=blob:none', '--branch=stable', LAZY_URL, lazypath,
    })
    if vim.v.shell_error ~= 0 then
      vim.notify('[nanolander] could not fetch lazy.nvim:\n' .. out ..
        '\nNeovim works; the plugin layer is off until this succeeds.',
        vim.log.levels.WARN)
      return false
    end
  end

  vim.opt.runtimepath:prepend(lazypath)
  return true
end

local function setup_diagnostics()
  vim.diagnostic.config({
    -- The whole point of hikovim's listchars and ExtraWhitespace match is a
    -- quiet screen, so diagnostics stay out of the text and in the gutter.
    virtual_text = false,
    signs = true,
    underline = true,
    severity_sort = true,
    float = { border = 'single', source = true },
  })
end

local function setup_folding()
  -- hikovim sets foldmethod=syntax with folding disabled. Treesitter folds
  -- are accurate where syntax folds guess, so switch the method but keep
  -- folding off by default, exactly as before.
  vim.o.foldmethod = 'expr'
  vim.o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  vim.o.foldenable = false
end

function M.setup()
  setup_diagnostics()

  if bootstrap_lazy() then
    require('lazy').setup(require('hikovim.plugins'), {
      -- lazy.nvim wipes the runtimepath by default, which would take ~/.vim
      -- with it and lose hiko_color, DirDiff and filter.vim.
      performance = { rtp = { reset = false } },
      change_detection = { notify = false },
      ui = { border = 'single' },
      -- ~/.local/share is where nanolander keeps everything else it installs.
      install = { colorscheme = { 'habamax' } },
      checker = { enabled = false },
      -- image.nvim's rockspec asks for the magick Lua rock, and lazy answers by
      -- bootstrapping hererocks — a LuaRocks build that wants Python and a
      -- compiler, on a box whose whole point is that it just lands. The plugin
      -- is configured with processor = 'magick_cli', which shells out to the
      -- ImageMagick nanolander installs, so the rock buys nothing here.
      rocks = { enabled = false, hererocks = false },
    })
    setup_folding()
  end

  require('hikovim.lsp').setup()
  require('hikovim.keys').setup()
  require('hikovim.video').setup()
  require('hikovim.picture').setup()
  require('hikovim.ide').setup()
end

M.setup()

return M
