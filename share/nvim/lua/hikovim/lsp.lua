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

-- server name (as nvim-lspconfig calls it) -> the binary it needs
local SERVERS = {
  clangd         = 'clangd',                       -- C, C++, ObjC
  lua_ls         = 'lua-language-server',
  bashls         = 'bash-language-server',
  pyright        = 'pyright',
  rust_analyzer  = 'rust-analyzer',
  gopls          = 'gopls',
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

function M.setup()
  local enable = {}
  for server, binary in pairs(SERVERS) do
    if vim.fn.executable(binary) == 1 then
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

return M
