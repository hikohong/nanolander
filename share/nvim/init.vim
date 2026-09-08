" nanolander — Neovim configuration
"
" Three layers, loaded in this order:
"
"   1. hikovim       ~/.vimrc and ~/.vim, shared byte for byte with vim, so
"                    every setting and mapping you already know still applies
"   2. Neovim deltas the handful of places where Neovim is not vim: cscope is
"                    gone, and shada is not viminfo
"   3. lua/hikovim   the modern stack — treesitter, LSP, aerial, gitsigns,
"                    lualine, oil, fzf-lua — managed by lazy.nvim
"
" Layer 1 is optional. On a machine where hikovim was never installed this
" file still loads and layers 2 and 3 still work. Layer 3 needs one network
" fetch on the very first start; without it Neovim still opens, just without
" the plugins.
"
" This file is installed by bin/nvim-land. Edit the copy in the nanolander
" repository, not the installed one, or the next --apply overwrites you.

"===========================================================================
" Layer 1 — hikovim
"===========================================================================
" The plugins vendored in ~/.vim/plugin that layer 3 replaces. Setting their
" guard variables before ~/.vimrc is read stops them loading here; vim itself
" is untouched and keeps using them exactly as before.
let g:loaded_airline        = 1      " replaced by lualine.nvim
let g:loaded_airline_themes = 1
let g:loaded_gitgutter      = 1      " replaced by gitsigns.nvim
let g:loaded_nerd_tree      = 1      " replaced by oil.nvim
let g:loaded_tagbar         = 1      " replaced by aerial.nvim
let g:loaded_taglist        = 'no'   " replaced by aerial.nvim
let g:loaded_vimirc         = 1      " an IRC client is not an editor's job

" DirDiff and filter.vim have no replacement in layer 3, so they stay.

if isdirectory(expand('~/.vim'))
  set runtimepath^=~/.vim runtimepath+=~/.vim/after
  let &packpath = &runtimepath
endif
if filereadable(expand('~/.vimrc'))
  source ~/.vimrc
endif

if !exists('g:colors_name')
  " hikovim is not installed, so hiko_color is not on the runtimepath.
  silent! colorscheme habamax
endif

"===========================================================================
" Layer 2 — where Neovim is not vim
"===========================================================================

" Neovim dropped cscope, so the whole `if has("cscope")` block in ~/.vimrc is
" skipped and its <C-\> mappings never exist here. Give the same letters a
" ripgrep and tags fallback, landing in the quickfix window rather than a
" split. Layer 3 replaces these again with LSP-accurate versions once a
" language server is attached; these are what remains on a bare box.
if !has('cscope')
  if executable('rg')
    set grepprg=rg\ --vimgrep\ --smart-case
    set grepformat=%f:%l:%c:%m
  endif
  " s: symbol  c: callers  d: callees  t: text  e: pattern
  "
  " grep cannot build a call graph, so c and d cannot really answer "who calls
  " this" and "what does this call" — they return the same word search as s.
  " Say so rather than letting the letter imply an answer it did not give;
  " layer 3 replaces both with real LSP call hierarchies once a server is
  " attached.
  function! s:NoCallGraph(kind) abort
    echohl WarningMsg
    echomsg 'cscope ' . a:kind . ': no call graph without a language server — showing every occurrence'
    echohl None
  endfunction

  nnoremap <C-\>s :silent grep! -w <C-R>=expand('<cword>')<CR><CR>:copen<CR>
  nnoremap <C-\>c :silent grep! -w <C-R>=expand('<cword>')<CR><CR>:copen<CR>:call <SID>NoCallGraph('c callers')<CR>
  nnoremap <C-\>d :silent grep! -w <C-R>=expand('<cword>')<CR><CR>:copen<CR>:call <SID>NoCallGraph('d callees')<CR>
  nnoremap <C-\>t :silent grep! -F <C-R>=expand('<cword>')<CR><CR>:copen<CR>
  nnoremap <C-\>e :silent grep!    <C-R>=expand('<cword>')<CR><CR>:copen<CR>
  " g: definition through the tags file  f: open file  i: who includes this
  nnoremap <C-\>g <C-]>
  nnoremap <C-\>f :find <C-R>=expand('<cfile>')<CR><CR>
  nnoremap <C-\>i :silent grep! -F <C-R>=expand('<cfile>')<CR><CR>:copen<CR>
endif

" ,sp and ,lp write session.vim plus viminfo.vim into the project directory.
" Neovim's info file is msgpack shada, not vim's text viminfo, and its
" 'sessionoptions' has no "options", so sharing the pair means whichever
" editor wrote last leaves the other unable to read it. Keep a separate pair
" instead. Delete this block to go back to sharing with vim.
function! LoadProject()
    cd %:h
    let g:prj_dir = expand("%:p:h")
    if filereadable("session.nvim") | source session.nvim | endif
    if filereadable("shada.nvim")   | rshada shada.nvim  | endif
    exe 'syntax enable'
endfunction

function! SaveProject()
    mksession! session.nvim
    wshada! shada.nvim
    echo "Write session done! (session.nvim)"
endfunction

function! SaveProject_Exit()
    call SaveProject()
    exe "qall"
endfunction

"===========================================================================
" Layer 3 — the modern stack
"===========================================================================
lua require('hikovim')

" vim:ts=2:sw=2:et
