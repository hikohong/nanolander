-- Language servers.
--
-- This is the part cscope and a tags file cannot do: "who calls this" and
-- "where is this defined" answered from a parse of the project rather than
-- from a text index that was accurate the last time you regenerated it.
--
-- Uses Neovim's own vim.lsp.config/vim.lsp.enable, so there is no plugin
-- glue here; nvim-lspconfig only supplies the per-server defaults.
--
-- A server is enabled only when its executable is on PATH — nanolander does
-- not install language servers, so a fresh box has none and this quietly
-- does nothing.

local M = {}

-- server name (as nvim-lspconfig calls it) -> the binary it needs.
--
-- The binary is the one nvim-lspconfig's own cmd runs, not the one you type to
-- install it: pyright's cmd is `pyright-langserver --stdio`, and pip's pyright
-- package installs a `pyright` wrapper that need not have brought the language
-- server binary with it. Checking the wrapper enabled a server whose cmd then
-- did not exist.
--
-- bin/nvim-land parses this table, so keep it one `name = 'binary'` per line.
local SERVERS = {
  clangd               = 'clangd',                  -- C, C++, ObjC
  lua_ls               = 'lua-language-server',
  bashls               = 'bash-language-server',
  basedpyright         = 'basedpyright-langserver', -- Python, see PREFER
  pyright              = 'pyright-langserver',
  pylsp                = 'pylsp',
  jedi_language_server = 'jedi-language-server',
  rust_analyzer        = 'rust-analyzer',
  gopls                = 'gopls',
}

-- Languages with more than one server above, in preference order: the first
-- one on PATH wins and the rest are left alone. Same rule as pkg_candidates
-- in bin/nanolander, and for the same reason — several of these answer for the
-- same files, and enabling two means two sets of diagnostics and two copies of
-- every completion candidate.
--
-- Only servers that actually complete belong here. ruff is a Python language
-- server too and is deliberately absent: it declares no completionProvider,
-- so it complements a type server rather than replacing one, and listing it
-- would make it exclude one.
local PREFER = {
  python = { 'basedpyright', 'pyright', 'pylsp', 'jedi_language_server' },
}

local function configure_clangd()
  vim.lsp.config('clangd', {
    cmd = {
      'clangd',
      '--background-index',
      '--clang-tidy',
      -- Inserting headers behind your back is exactly the kind of surprise
      -- this configuration avoids elsewhere.
      '--header-insertion=never',
      '--completion-style=detailed',
    },
  })
end

local function on_attach(args)
  local client = vim.lsp.get_client_by_id(args.data.client_id)
  if not client then return end

  -- Completion on demand with <C-x><C-o>, not as you type: hikovim
  -- deliberately turned OmniCppComplete's popup off because it interfered
  -- with normal typing, and that preference still stands.
  if client:supports_method('textDocument/completion') then
    pcall(vim.lsp.completion.enable, true, client.id, args.buf, { autotrigger = false })
  end

  -- Neovim already binds K (hover), grn (rename), gra (code action),
  -- grr (references), gri (implementation) and gO (document symbols) when a
  -- client attaches, so nothing more is needed here. The <C-\> family is
  -- rebound in hikovim/keys.lua.
end

-- losers — every server a PREFER list passes over, so the loop below skips
-- them even though their binary is there.
local function losers()
  local skip = {}
  for _, candidates in pairs(PREFER) do
    local chosen
    for _, server in ipairs(candidates) do
      if chosen == nil and vim.fn.executable(SERVERS[server]) == 1 then
        chosen = server
      else
        skip[server] = true
      end
    end
  end
  return skip
end

function M.setup()
  local enable = {}
  local skip = losers()
  for server, binary in pairs(SERVERS) do
    if not skip[server] and vim.fn.executable(binary) == 1 then
      table.insert(enable, server)
    end
  end

  if vim.fn.executable('clangd') == 1 then
    configure_clangd()
  end

  if #enable > 0 then
    pcall(vim.lsp.enable, enable)
  end

  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('hikovim_lsp', { clear = true }),
    callback = on_attach,
  })
end

-- Reported by bin/nvim-land so you can see which servers this box can run.
function M.servers()
  return SERVERS
end

-- Exposed for the same reason, and so the choice can be checked.
function M.preferred()
  return PREFER
end

M.losers = losers

return M
