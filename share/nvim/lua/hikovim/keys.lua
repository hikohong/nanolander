-- Keymaps.
--
-- The rule here is that muscle memory wins. ~/.vimrc's mappings are left
-- alone; the only ones rebound are those whose vim plugin does not exist in
-- Neovim, and they keep their original keys:
--
--   ,tb          outline          was :TagbarToggle      now :AerialToggle
--   <C-\>s g c   cscope queries   was :cs find …         now LSP, else ripgrep
--   <C-\>t e f i d
--
-- Everything else — ,sp ,lp ,ic ,f ,F <space> <backspace> <C-h> <C-Z> — comes
-- straight from ~/.vimrc and behaves as it always did.

local M = {}

local function map(lhs, rhs, desc)
  vim.keymap.set('n', lhs, rhs, { silent = true, desc = desc })
end

-- ~/.vimrc defines ,tb with :map, which covers normal, visual and operator
-- pending. All three have to be replaced or the leftovers still call the
-- :TagbarToggle command that no longer exists here.
local function map_nxo(lhs, rhs, desc)
  vim.keymap.set({ 'n', 'x', 'o' }, lhs, rhs, { silent = true, desc = desc })
end

local function has_lsp()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end

-- fallback_grep — what the <C-\> keys do when fzf-lua is not installed yet
-- (first start, no network): exactly what layer 2 in init.vim does.
local function fallback_grep(pattern, whole_word)
  local flag = whole_word and '-w ' or '-F '
  vim.cmd('silent grep! ' .. flag .. vim.fn.shellescape(pattern))
  vim.cmd('copen')
end

-- pick — run an fzf-lua picker, or fall back to the quickfix grep.
local function pick(picker, opts, fallback_pattern, whole_word)
  local ok, fzf = pcall(require, 'fzf-lua')
  if ok and fzf[picker] then
    fzf[picker](opts or {})
    return
  end
  if fallback_pattern then
    fallback_grep(fallback_pattern, whole_word)
  else
    vim.notify('[nanolander] fzf-lua is not installed yet (:Lazy sync).',
      vim.log.levels.WARN)
  end
end

local function cword()
  return vim.fn.expand('<cword>')
end

-- ]c and [c are vimdiff's own keys, so in a diff they stay vimdiff's.
local function nav_hunk(direction, in_diff)
  return function()
    if vim.wo.diff then
      vim.cmd('normal! ' .. in_diff)
      return
    end
    local ok, gs = pcall(require, 'gitsigns')
    if ok then gs.nav_hunk(direction) end
  end
end

-- The cscope letters, kept verbatim from ~/.vimrc. With a language server
-- attached these are precise; without one they degrade to a word search,
-- which is what cscope was approximating anyway.
local function cscope_keys()
  map('<C-\\>s', function()          -- s: this symbol
    if has_lsp() then pick('lsp_references') else pick('grep_cword', {}, cword(), true) end
  end, 'cscope s: references to this symbol')

  map('<C-\\>g', function()          -- g: its definition
    if has_lsp() then
      pick('lsp_definitions')
    elseif not pcall(vim.cmd, 'tag ' .. cword()) then
      -- No language server and no tags file: fall back to a word search.
      pick('grep_cword', {}, cword(), true)
    end
  end, 'cscope g: definition of this symbol')

  map('<C-\\>c', function()          -- c: functions calling this one
    if has_lsp() then pick('lsp_incoming_calls') else pick('grep_cword', {}, cword(), true) end
  end, 'cscope c: callers of this function')

  map('<C-\\>d', function()          -- d: functions this one calls
    if has_lsp() then pick('lsp_outgoing_calls') else pick('grep_cword', {}, cword(), true) end
  end, 'cscope d: functions called by this one')

  map('<C-\\>t', function()          -- t: this text string
    pick('grep_cword', {}, cword(), false)
  end, 'cscope t: this text string')

  map('<C-\\>e', function()          -- e: egrep pattern
    pick('live_grep', {}, cword(), false)
  end, 'cscope e: search for a pattern')

  map('<C-\\>f', function()          -- f: this file
    pick('files', { query = vim.fn.expand('<cfile>') })
  end, 'cscope f: open this file')

  map('<C-\\>i', function()          -- i: files #including this one
    pick('grep', { search = vim.fn.expand('<cfile>'), no_esc = false },
      vim.fn.expand('<cfile>'), false)
  end, 'cscope i: files including this one')
end

function M.setup()
  -- ,tb kept its meaning: the outline window on the right.
  map_nxo('<leader>tb', '<cmd>AerialToggle!<CR>', 'Outline (was TagbarToggle)')

  -- The NERDTree toggle ~/.vimrc has commented out on <F5>, now a real
  -- editable directory buffer.
  map('<F5>', '<cmd>Oil<CR>', 'File explorer (oil.nvim)')

  cscope_keys()

  -- New, and only on keys hikovim leaves free.
  map('<leader>gb', '<cmd>Gitsigns toggle_current_line_blame<CR>', 'Git blame on this line')
  map('<leader>gp', '<cmd>Gitsigns preview_hunk<CR>', 'Preview this hunk')
  map(']c', nav_hunk('next', ']c'), 'Next git hunk')
  map('[c', nav_hunk('prev', '[c'), 'Previous git hunk')
  map('<leader>ff', '<cmd>FzfLua files<CR>', 'Find file')
  map('<leader>fg', '<cmd>FzfLua live_grep<CR>', 'Live grep')
  map('<leader>fb', '<cmd>FzfLua buffers<CR>', 'Switch buffer')
  map('<leader>fd', '<cmd>FzfLua diagnostics_document<CR>', 'Diagnostics in this file')
end

return M
