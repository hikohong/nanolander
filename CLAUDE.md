# nanolander Agent Memory

## Identity
You are the **nanolander agent** for `hikohong/nanolander`.
Your job is to maintain and evolve a **minimal, universal terminal operating
environment** — one script that lands the same modern toolchain on any machine,
local or remote.

Owner: Hiko Hong (hikohong@gmail.com)
Default branch: `main`
Project site: `docs/` (GitHub Pages, English)

---

## What this project is

nanolander is not an installer for one machine — it is a **portable terminal
environment**. The promise is that a fresh box, whether it is the laptop in
front of you or a bare EC2 instance you just SSH'd into, ends up with the same
54 tools, the same shell behaviour and the same editor.

| Platform | Package manager | Shell config target if the login shell is unrecognised |
| --- | --- | --- |
| macOS | Homebrew | `~/.zshrc` (+ `~/.zprofile`) |
| Ubuntu | APT | `~/.bashrc` |
| Amazon Linux 2 / older | YUM | `~/.zshrc` |
| Amazon Linux 2023 | DNF | `~/.zshrc` |

The package manager comes from the platform; **the rc file comes from the login
shell**, since that is what decides which file is read. That column is only the
fallback. See `resolve_shell_rc` below.

Architectures: `x86_64`, `arm64` (full), `armv7` (most), `armv6` (partial).

Helper scripts live alongside the main script and all follow the same shape —
report by default, `--apply` to write, back up first, `--restore` to undo:

| Helper | Scope |
| --- | --- |
| `bin/nvim-land` | installs `share/nvim` into `~/.config/nvim` |
| `bin/iterm-tune` | iTerm2 rendering settings, macOS only |
| `bin/vlc-default` | VLC as the default video player, macOS only |

**More of these are expected**, so treat those three files as the template
rather than one-offs.

---

## Repository Structure

```
/
├── CLAUDE.md              ← this file (agent memory)
├── README.md              ← the specification, in English; keep it true
├── LICENSE                ← MIT
├── bin/
│   ├── nanolander         ← the main installer (bash 3.2, ~1900 lines)
│   ├── nvim-land          ← installs the Neovim config, macOS + Linux
│   ├── iterm-tune         ← iTerm2 performance tuning, macOS only
│   └── vlc-default        ← VLC as the default video player, macOS only
├── share/
│   └── nvim/              ← the Neovim config, vendored here on purpose
│       ├── init.vim       ← layers 1 and 2: sources ~/.vimrc, patches Neovim
│       ├── lua/hikovim/   ← layer 3: init, plugins, lsp, keys, ide, video, media
│       └── lazy-lock.json ← the pinned plugin set; written by --freeze
├── tests/                 ← the suites; ./tests/run.sh runs them all
├── .github/workflows/     ← CI: the only gate on an auto-merged PR
└── docs/
    └── index.html         ← project page (English; the site is English only)
```

`docs/` is served by GitHub Pages from the `/docs` folder.

**README.md and `docs/index.html` are the specification.** The scripts were
reconstructed from them. If you change behaviour, change all three together, or
the next reconstruction goes wrong the same way it did before.

---

## Hard constraints

These are not style preferences. Breaking any of them breaks a supported
platform.

- **bash 3.2 compatible.** macOS still ships bash 3.2. No associative arrays,
  no `mapfile`/`readarray`, no `${var,,}` / `${var^^}`, no `|&`. Indexed arrays
  are fine; `local` is fine.
- **ShellCheck clean at `-S style`.** Stricter than the warning-level bar the
  README claims. Any `disable=` needs a comment saying why.
- **No runtime dependencies beyond what a base system has**: `curl`, `tar`,
  `sed`, `awk`, `grep`, `find`. In particular **do not use `jq` to parse the
  GitHub API** — jq is one of the tools nanolander may still be installing.
- **The nvim config is nanolander's; the vim config is hikovim's.** `share/nvim`
  *sources* `~/.vimrc` and adds `~/.vim` to the runtimepath — it never copies
  or edits them. That is why there is only one copy of the settings vim and
  Neovim share, even though the Neovim half is vendored here. Do not move
  `_vimrc` content into this repository, and do not put `init.vim` into
  hikovim: two owners of one file is exactly the drift this avoids.
- **Neovide is the one tool that is not on every platform.** Upstream builds it
  for macOS and `x86_64` Linux only, so `tool_unsupported_here` records it
  `SKIPPED (platform)` elsewhere rather than `FAILED`. Any future entry with
  the same problem goes through that function, not through a new special case
  in the install loop.
- **The Nerd Font never comes from a package manager.** The whole point is
  that all four platforms get identical font files, so it is always the
  upstream release. It also installs no command, so `command_works` and
  `pkg_candidates` both special-case it.
- **Installing a font cannot select it.** That belongs to the terminal, and
  for a remote box it belongs to the terminal on the user's laptop. Say so;
  do not imply the prompt will look right on its own.
- **Never feed a loop that installs anything from stdin.** `install_all_tools`
  reads the catalog on **descriptor 3** (`read … <&3`, `done 3<<CATALOG`)
  because the loop body runs package managers and dnf reads stdin to ask about
  importing a repository GPG key. On stdin, the first tool that actually
  installed something ate every remaining catalog line, the loop ended there,
  and the summary called it a success — one Amazon Linux box took six runs to
  get seven of the fifty-four tools. Descriptor 3 also leaves stdin on the
  terminal, so a package manager that must ask can still be answered.
- **A tool counts as installed only when its version query prints something.**
  Exit status is not enough; see `command_works`. Anything that adds a new
  verification path keeps that rule, or a file that merely has the right name
  gets reported verified.
- **Idempotent.** Re-running must not duplicate a shell rc line or reinstall
  what is already there. Shell config is written with whole-line comparison
  (`grep -Fqx`).
- **Never modify a shell config file without a backup.** `add_line_once` and
  `add_alias_block` call `backup_file_once` first and refuse to write when it
  fails. Backups are lazy: a run that changes nothing writes none.
- **Only ever append whole lines** to an rc file, never edit an existing one.
  That is what makes removal by exact match, and by hand, safe.
- **`--uninstall` deletes only what is recorded** in
  `~/.local/share/nanolander/installed`, and only under `~/.local`. It never
  removes system packages, and never touches the Homebrew line in
  `~/.zprofile`.
- **The log is the screen.** `~/nanolander-YYYYMMDD-HHMMSS.log` is a
  byte-for-byte copy of stdout, which is why the output helpers emit plain text
  with no ANSI colour. `grep '== Installing yq =='` on the log must keep working.
- **Never log a secret.** `GITHUB_TOKEN` may be set; report only that it exists.
- **The plugin set is pinned by `share/nvim/lazy-lock.json`.** With it present
  `nvim-land --apply` runs `Lazy! restore`, which checks out those commits;
  without it `Lazy! sync` takes each project's head and two machines set up
  weeks apart get different editors. nvim-treesitter tracks the `main` rewrite
  branch and has no tags, so the lockfile is the only mechanism there is.
  Regenerate it with `./bin/nvim-land --freeze` and commit the result.
- **README's keys reference is checked, not trusted.** `### Keys and commands`
  is the one place a reader is told what every mapping does, and
  `test-readme-keys.sh` fails when a key or a user command the configuration
  defines is missing from it — so a new mapping is not finished until it is
  documented. It asserts the section's sub-headings too, since deleting a
  pane's table would otherwise pass by finding each key elsewhere in the file.
  Only what this repository defines is checked; the plugin defaults the
  reference also lists are upstream's, pinned by `lazy-lock.json`.
- **CI is the only gate.** Every change lands through an auto-merged PR, so
  `.github/workflows/ci.yml` is what stands between a broken script and `main`.
  Do not add a change without running `./tests/run.sh` first.
- **Exit codes are API**: `0` all good · `1` environment prep failed · `2` some
  tools failed · `64` bad arguments · `130` interrupted.

---

## bin/nanolander architecture

Flow: detect environment → sudo check → Homebrew (macOS) → refresh package
index → per tool: filter, skip if present, package manager, GitHub release,
verify → shell config → summary.

| Function | Responsibility |
| --- | --- |
| `detect_environment` | `uname -s` + `/etc/os-release` → package manager and a *fallback* rc file; `uname -m` → arch keyword set |
| `shell_kind_of` / `resolve_shell_rc` | the rc file the run actually writes. Precedence: `--shell` → `--set-default-shell` (implies zsh) → login shell → platform fallback. Suffix matching, so a wrapper counts (`logbash` is bash) |
| `report_foreign_rc` | says when the *other* rc file still carries managed lines, and never touches it |
| `wants_tool` / `list_contains` | `--only` / `--skip`, case- and whitespace-insensitive, command name or display name |
| `print_tool_catalog` | `--list-tools`, reads `TOOL_CATALOG` |
| `setup_homebrew` | macOS only; installs Homebrew non-interactively if missing. Fatal on failure |
| `package_available` / `package_installed` / `install_package` | one interface over brew / apt / dnf / yum |
| `try_package_candidates` | walks `pkg_candidates` in order (`fd` vs `fd-find`, `tlrc` vs `tldr`, `procps-ng` vs `procps`) |
| `github_install` | latest release → pick asset → verify SHA-256 → extract → install to `~/.local/bin` |
| `select_asset` | **full suffix match first, substring second** — this is what stops `linux_arm` matching an `arm64` host |
| `parse_assets` | flattens the release JSON without jq; pairs each URL with its own digest |
| `find_payload` | exact basename, then prefix — catches `yq_linux_amd64`, `shfmt_v3.10.0_linux_amd64`, `direnv.linux-amd64`. **Each pass prefers an executable**, because an archive can hold two files with the command's name and only one is the program (fastfetch ships a bash-completion script called `fastfetch`). The exec bit cannot be the only rule: a bare-binary release lands here as the 0644 file curl wrote |
| `install_neovim_tree` | Neovim needs its runtime dir: `~/.local/opt/nvim-github` + symlink |
| `tool_unsupported_here` / `ensure_tool` | the one platform exception (Neovide) and the wrapper that routes a catalog entry to the brew or Linux path |
| `make_compat_links` | Debian/Ubuntu ship `fdfind` / `batcat`; link them to `fd` / `bat` |
| `ensure_nerd_font` / `install_nerd_font` | the one catalog entry that installs no command; same upstream release on all four platforms, monospaced faces only, `~/Library/Fonts` on macOS and `~/.local/share/fonts` + `fc-cache` elsewhere |
| `select_named_asset` | picks a release asset by exact filename — the font release is one archive per family, not per architecture |
| `version_query` / `command_works` | runs a real version query and **requires it to print something**, on either stream — exit status alone passed a completion script that sources silently and exits 0. Spellings live in `version_query`: `tmux -V`, `unzip -v`, `cscope -V`, `pdftoppm -v`, `ffmpeg -version`. `entr` and `7zz` have no version flag, so PATH presence is their test |
| `shell_line` | **the only definition of every managed rc line**; both `configure_shell` and the uninstaller read it, so they cannot drift apart |
| `configure_shell` | PATH, zoxide, starship, direnv, fzf keys + `FZF_DEFAULT_COMMAND`, optional alias block |
| `script_dir` / `install_nvim_config` | `--with-nvim-config`; resolves `$0` through symlinks, because README tells people to link `bin/nanolander` onto PATH, then hands off to `bin/nvim-land --apply` |
| `backup_file_once` / `backup_path` | copies a shell config file to `~/.nanolander-backups` before the first write of a run; `backup_path` never reuses a name, so two runs in the same second cannot clobber each other |
| `restore_shell` | `--restore-shell`; snapshots the current file into `pre-restore/` — a subdirectory, so it is never a restore source and repeat runs stay idempotent |
| `uninstall_nanolander` | `--uninstall`; drops the managed lines and alias block, then removes manifest paths, refusing anything outside `~/.local` |

`NANOLANDER_LIB=1 . ./bin/nanolander` sources the functions without running
anything. Use it to test internals.

### Adding a tool

Three places, in this order:

1. `TOOL_CATALOG` — `command|display name|category|purpose`
2. `pkg_candidates` — distro package names to try, most specific first
3. `github_repo` — `owner/repo`, or omit it if the project ships no
   cross-platform binaries (`tig`, `cscope`, `entr`, `ctags` are repository-only)

Then update the tool count and the tables in `README.md` **and
`docs/index.html`** (the site's `54 tools` string appears three times: the hero
fact, the filter count and the JS reset).

Watch for a package that installs cleanly and still does not provide the
command — brew's `tree-sitter` is the library, `tree-sitter-cli` is the binary.
Both `ensure_brew_tool` and `ensure_linux_tool` now verify with
`command_works` before they stop looking, so put the candidate that carries the
binary first and let them fall through.

### The Neovim config (`share/nvim` + `bin/nvim-land`)

Three layers, and the layering is the design:

1. `~/.vimrc` and `~/.vim` sourced as they are, so vim and Neovim cannot drift
2. the Neovim deltas — `has('cscope')` is `0` there, so `~/.vimrc`'s whole
   cscope block is dead and its `<C-\>` keys have to be rebuilt; and shada is
   not viminfo, so `,sp` / `,lp` write `session.nvim` / `shada.nvim` instead of
   clobbering the pair vim wrote
3. `lua/hikovim/` — lazy.nvim with treesitter, LSP, aerial, gitsigns, lualine,
   oil, neo-tree, flatten, fzf-lua, and `ide.lua`, which arranges those plugins
   into a four-pane layout rather than adding any

Rules that are easy to break:

- **Layer 1 must stay optional.** `init.vim` guards both the runtimepath line
  and the `source`, and falls back to `habamax`, so a box without hikovim still
  gets a working editor.
- **Layer 3 must stay optional too.** `bootstrap_lazy` returns false rather
  than throwing when git is missing or the clone fails; a freshly landed box
  with no network still opens files.
- **`ide.lua` owns no plugins.** It places aerial, neo-tree and `:terminal` in
  windows it built itself, and every call into them is wrapped so that a
  missing plugin degrades to a notification rather than an error on every
  keystroke. It also keeps the layout out of the way of the starts where it
  would be wrong: a `$EDITOR` call from git, `nvim -d`, piped stdin, or a
  session that restored its own windows.
- **oil and neo-tree split what NERDTree did, and neither replaces the other.**
  oil is the directory *editor* — a directory is a buffer — and owns `<F5>`,
  `:e <dir>` and netrw (`default_file_explorer = true`). neo-tree is the
  *navigator* in the explorer pane, because oil shows one directory at a time by
  design and cannot be a tree. So neo-tree must keep
  `hijack_netrw_behavior = 'disabled'`: two plugins claiming netrw means a
  directory opens in whichever loaded last.
- **`video.lua` previews, it does not play, and that boundary is the design.**
  A `BufReadCmd` replaces the binary read with ffprobe's numbers and one ffmpeg
  frame. Playback in a buffer was measured and rejected: a 960×540 frame is
  625 KB of sixel, so 24 fps is 14 MB/s of escape sequences, and a sixel image
  is painted on the terminal rather than owned by a buffer, so every statusline
  tick tears it. Hand a video to `open` or `mpv --vo=tct` instead.
- **`<CR>` and a double click in the tree hand a video or a picture to the
  system; a single click previews it.** Both keys mean "I have chosen this one",
  a single click means "show me this one". Three things make it work and each
  has already been got wrong once. It goes through `vim.ui.open`, so no
  application is named twice — `bin/vlc-default` owns the video binding and the
  system owns the picture one. The single click **must not move the cursor out
  of the tree**, because a mouse mapping is looked up in the buffer that is
  current when the key is processed, so a preview that jumps to the editor pane
  leaves the second click of a double click reaching nothing. And a plain keymap
  asking neo-tree for its state must use `get_state_for_window`:
  `get_state('filesystem')` returns the state held *for the tab*, and this tree
  is at `position = 'current'`, whose state is held per window, so that call
  creates and returns an empty one and every click falls through to `<CR>`.
- **The explorer pane's root-picker button has one owner for its icon.**
  `ide.lua` declares `M.ROOT_PICK_ICON`; `plugins.lua` reads it to render into
  the root name and `root_click` searches the rendered line for it again. A
  second copy is how the button appears and clicking it does nothing — the same
  failure `media.lua`'s single extension list exists to prevent. Three more
  rules there: override neo-tree's `name` component, never copy its `directory`
  renderer, or upstream's layout of that line goes stale here; **find** the
  icon in the line rather than counting columns, because everything before it
  is neo-tree's and changes width; and `root_set` must make the tree window
  current before `:Neotree`, since the pane is at position `current` and the
  picker is a float, so otherwise the editor pane becomes a second tree.
- **The root picker is a browser, and its key goes through neo-tree.** Rows are
  `✓ use` / `↑ up` / `↓ down`; `<CR>` and a double click are fzf-lua `reload`
  actions, so the window stays open while walking, and only the `✓` row or
  `<C-y>` sets a root. Two things shipped broken in the first version and were
  only caught by driving a real Neovim in tmux, not headless:
  - its key was `<C-r>`, which is neo-tree's own `clear_clipboard`. neo-tree
    resets buffer mappings on render, so a `FileType` binding for a key neo-tree
    also binds is silently lost. Bind tree keys in
    `filesystem.window.mappings`. And the check that let it ship asked only
    whether *something* was mapped — compare `desc`, and normalise key names
    through `keytrans` (`<C-r>` and `<C-R>` are the same key; the raw strings
    are not, which is how a probe called a taken key free).
  - the button vanished after first use. neo-tree truncates a line from the
    right, and the explorer pane is a fifth of the screen, so a deep root
    pushed the button off the end. `root_label` shortens the path from the
    left to fit the real window width instead.
- **Drive a real Neovim for anything interactive.** `tmux -L <socket> -f
  /dev/null` gives an isolated server that ignores the user's tmux.conf (whose
  `xterm-keys` changes what keys send); `send-keys` and `capture-pane` then
  press real keys and read the real screen. Headless cannot show a fzf window,
  a truncated line, or a key neo-tree has taken.
- **`tree_state()` is the only place the per-window state is asked for.**
  `get_state('filesystem')` returns the state held for the tab, and this tree
  is at position `current`, whose state is held per window. `tree_node` and
  `root_pick` both come through `tree_state`; a second caller asking in its own
  way is what the suite's "the state is asked per window" check catches.
- **`media.lua` owns both extension lists, and nothing else may keep a copy.**
  `video.lua`'s `BufReadCmd`, image.nvim's `hijack_file_patterns` and `ide.lua`'s
  tree handoff all read it. image.nvim exposes no accessor for what it was told
  to hijack, so a second copy is how a format gets a preview and no viewer, or
  the reverse. It matches the file *name*: matching the whole path hands a text
  file to the viewer because a directory above it is called `something.mkv`.
- **The video buffer is `nowrite`.** It keeps the real filename, so without that
  a `:w` would write the preview text over the video.
- **iTerm2 does not speak the Kitty graphics protocol, and every Neovim image
  plugin does.** snacks.nvim has no iTerm2 path at all; image.nvim defaults to
  kitty. iTerm2 speaks sixel, so `backend = 'sixel'` is load-bearing — that is
  the only reason images render at all here. `backend = 'kitty'` is the one line
  to change on Ghostty/Kitty/WezTerm, and is faster.
- **`processor = 'magick_cli'`, and lazy's rocks are off.** image.nvim's
  rockspec asks for the `magick` Lua rock; lazy answers by bootstrapping
  hererocks, which wants Python and a compiler. `rocks = { enabled = false }` in
  `init.lua` keeps that off a freshly landed box, and the CLI processor uses the
  ImageMagick the catalog installs instead. The lockfile must not gain a
  `hererocks` entry; there is a test for that.
- **image.nvim is gated on there being a terminal to draw into**, because it
  prints `cannot query terminal size` on every headless start otherwise, which
  lands in `:messages` and breaks both scripting and the clean-load check. The
  gate takes either `nvim_list_uis()` or `has('ttyout')`: the failure modes are
  asymmetric, so it errs toward loading.
- **lualine invents a tabline entry for an unlisted current buffer.** Focus a
  panel and it appears as a tab — `[No Name]` for the outline — with the ✕ that
  `add_tabline_close_button` adds, and that ✕ ran `:q` on the pane. `is_current`
  is patched so the editor's buffer answers yes while the cursor is in a panel,
  which stops the tab being invented at all, and the ✕ goes through
  `M.close_tab`, which acts only on listed buffers. `:q` in a panel still closes
  that window — that is `close_buffer`, and it is meant to.
- **`startinsert` is spent on whichever window is current when the main loop
  resumes**, not where it is called. The terminal pane's `term://*` autocmd
  fired it while `M.open` was still building, so the flag landed on the *editor*
  pane and a fresh Neovim came up in insert mode — where every panel mapping,
  all normal-mode, answers nothing. It defers and re-checks `buftype` now.
- **The panes fill asynchronously, so focus cannot be set once and assumed.**
  neo-tree focuses its own window when its scan lands, after `M.open` has
  returned, which undid a single `vim.schedule`. `settle_focus` re-checks a few
  times across ~200ms and stops early; it is bounded so it cannot fight someone
  who clicks into a panel on purpose.
- **neo-tree binds only `<2-LeftMouse>`.** A single click in the explorer pane
  therefore moved the cursor and did nothing else, which reads as a dead pane
  rather than a default. `ide.lua` maps `<LeftRelease>` (guarded by
  `CLICK_OPENS`) and delegates to whatever `<CR>` is bound to in that buffer,
  rather than calling neo-tree's command modules — the click has already moved
  the cursor by then, and delegating survives a rename behind its keymaps.
- **A nested Neovim is invisible to `ide.lua`.** `nvim file` in the terminal
  pane is a separate process, so `enforce` cannot move its buffer anywhere.
  flatten.nvim is what routes it to the editor pane, via `M.editor_win()`, and
  its window handler returns **`bufnr, winnr` — buffer first**. flatten's README
  documents that pair the other way round; returning a window id first makes
  flatten treat it as a buffer number and throw from its `BufEnter` handler on
  every open. There is a test for the order.
- **Neovim has no `--remote-wait`.** The wait commands are Vim's; Neovim answers
  `E5600`. The `nvimremote` shell line therefore uses plain `--remote` and does
  not block, which is fine because a shell function is invisible to the `sh -c`
  git runs `$EDITOR` through — so it can only affect a typed command. Blocking
  for `gitcommit` is flatten's job, over RPC.
- **`pending_count` must keep ignoring the lockfile for `--freeze`.** Rewriting
  `lazy-lock.json` is what `--freeze` does, and installing a new plugin
  necessarily makes the target's copy differ, so counting it made `--freeze`
  refuse in exactly the case it exists for and no plugin could ever be added.
- **Completion is automatic, and it used to be a documented decision that it
  was not.** `~/.vimrc` has OmniCppComplete's block commented out with a note
  that its popup interfered with typing, and for years layer 3 answered that by
  leaving completion on `<C-x><C-o>`. `blink.cmp` reverses it. Keep the reason
  straight when editing this: the objection was a popup that stole keystrokes,
  so every key that drives this menu ends in `fallback` and does what vim does
  when the menu is closed. `<C-x><C-o>` still works. README says so in
  `### Keys and commands`, and a test fails if the old claim comes back.
- **blink's fuzzy matcher must fall back silently.** `implementation =
  'prefer_rust'`, never `'prefer_rust_with_warning'`: the warning lands in
  `:messages` on every start on a box where the prebuilt binary cannot run,
  which breaks the same clean-load check that image.nvim's UI gate exists for.
  `version = '*'` is what gets a prebuilt binary at all — building from source
  wants cargo.
- **blink takes `<C-k>` in its default preset, and that is vim's digraph key.**
  It is moved to `<C-s>`. Same rule as everywhere else here: new maps go on
  keys vim leaves free.
- **Copilot is gated on its credentials, not on a `cond`.** lazy refuses to
  load a spec whose `cond` is false even through its own `cmd`
  (`lazy/core/loader.lua`), so a `cond` would take `:Copilot auth` away from
  the only machine that needs to run it. So `cmd = 'Copilot'` is always
  registered and only `event = 'InsertEnter'` is conditional, via
  `copilot_ready()`. Without that gate, entering insert mode on a box with no
  subscription had copilot.lua fetch its language server and announce the
  download in `:messages`.
- **mini.bracketed's targets collide with keys that are already owned**, and
  the fix is to switch the target off rather than move the key: `comment` is
  off because `]c` and `[c` are the git hunks and vimdiff's change motion,
  `quickfix` and `file`/`window`/`yank` are off because Neovim's own `]q` and
  vim's `:next`, `<C-w>w` and registers already do those, and `treesitter`
  moved to `n` so `]t` stays Neovim's `:tnext`. Keys keep their letters.
- **`performance.rtp.reset = false` in the lazy setup is load-bearing.** lazy
  wipes the runtimepath by default, which would take `~/.vim` with it and lose
  `hiko_color`, DirDiff and filter.vim.
- **Replacing a `~/.vim` plugin means setting its guard variable** in
  `init.vim` *before* `~/.vimrc` is sourced (`g:loaded_airline`,
  `g:loaded_gitgutter`, `g:loaded_nerd_tree`, `g:loaded_tagbar`,
  `g:loaded_taglist = 'no'`). Add a `" replaced by …` comment: `nvim-land`
  parses those comments for its report, so the list is never written twice.
- **Keys keep their letters.** `,tb` stays the outline toggle and the `<C-\>`
  family stays the cscope letters. `~/.vimrc` defines `,tb` with `:map`, so all
  three of n/x/o have to be replaced or the leftover calls a command that no
  longer exists.
- **`nvim-land` never deletes a file it does not ship** and never touches
  `~/.vimrc` or `~/.vim`. Foreign files in `~/.config/nvim` are reported only.
- **The server list is parsed, not repeated.** `nvim-land` reads the `SERVERS`
  and `PREFER` tables out of `lua/hikovim/lsp.lua`; keep both shapes
  parseable — one `name = 'binary'` per line, one
  `language = { 'a', 'b' }` per line.
- **The binary in `SERVERS` is the one nvim-lspconfig's `cmd` runs**, not the
  one you type to install the server. pyright's cmd is
  `pyright-langserver --stdio`, and the table checked `pyright` — pip's
  pyright package installs that wrapper without necessarily having the
  language server binary, so the server was enabled and its cmd then did not
  exist. Read `lsp/<server>.lua` in nvim-lspconfig before adding a row.
- **One server per language, chosen in order.** `PREFER` lists the several
  servers that answer for the same files and `losers()` stands down all but
  the first on PATH — two attached means two sets of diagnostics and two
  copies of every completion candidate. Same rule as `pkg_candidates` in
  `bin/nanolander`. Only servers that actually complete belong there: `ruff`
  is a Python language server with no `completionProvider`, so it complements
  a type server and listing it would make it exclude one.
- **An attached server is not proof it can answer the request.** Every LSP
  request is optional in the protocol, so `keys.lua` checks
  `client:supports_method` for the exact method its own picker will send —
  `lsp_can(...)`, one method per key — and falls back to the ripgrep word
  search when the answer is no. The coarse "is a server attached" check put
  `[Fzf-lua] LSP: server does not support callHierarchy/outgoingCalls` on
  screen in Python while the same keys worked in C: pylsp has references and
  definition and no `callHierarchyProvider` at all. Third instance of the same
  rule, after `command_works` and `parse_handler_dump`.
- **Neovim's own `gr` keys are left alone, including when they fail.** `gri` on
  a server with no `implementationProvider` prints
  `vim.lsp: method "textDocument/implementation" is not supported…`, which is
  clear, harmless and upstream's to own. Do not rebind them to add a fallback:
  `implementation` has no Python meaning, so a word search there would answer
  a question nobody asked.
- **A dot completing nothing is a missing language server, not a broken
  menu.** `self.` asks what an object has, and neither the path nor the buffer
  source can answer that, so the menu is empty there while working normally
  for a word. nanolander installs no language servers by design; the report is
  where a user finds that out, which is why it has to name the one that
  answers rather than every one that is installed.
- Treesitter parsers need the `tree-sitter` CLI *and* a C compiler. Neovim
  bundles `c`, `lua`, `markdown`, `query`, `vim`, `vimdoc`, which is why C
  still works on a bare box.

### Adding a helper

Follow `bin/iterm-tune`:

- **Report by default.** Writing requires an explicit `--apply`.
- **Back up before writing**, into `~/.nanolander-backups/`, and provide
  `--restore`.
- **Refuse to write while the terminal is running** — it will overwrite the
  file with its in-memory state on quit.
- Keep the "what to change" as a `key|type|desired|label` table so it can be
  unit-tested without the target OS.
- Report the user's own content (triggers, background images, the chosen
  font); never modify it. The font report exists so a user can see why their
  prompt is full of boxes.
- **Add nothing to CI's file lists.** `ci.yml` lints and parses `bin/*`, not a
  list of names, because a helper added without being added there went
  unchecked — and the whole point of that table above is that helpers keep
  arriving.

### bin/iterm-tune

- **A PlistBuddy key path needs a quote around every segment.** PlistBuddy
  splits its `-c` command on whitespace, so `Print :New Bookmarks:0:Guid` asks
  for an entry called `:New`. Every per-profile key in iTerm2's preferences is
  under a name with a space, so `profile_count` answered 0 on every machine:
  the whole per-profile report never ran, the font advisory never printed, and
  `--apply` wrote none of `PROFILE_SETTINGS` while reporting that it had. Go
  through `pb_path`, which takes the path as segments — a preassembled string
  is how it was got wrong. A quoted array index is accepted, so there is no
  exception for the index.
- **The exit status of a lookup is not proof it found anything**, same rule as
  `command_works` and `parse_handler_dump`: a count of 0 profiles read exactly
  like a machine with no profiles.
- **Both fonts are reported, neither is written.** iTerm2's second font — the
  non-ASCII one — overrides the main face for every icon while it is on, and
  the icons are all Private Use Area, which macOS's fallback chain cannot
  resolve, so a `PowerlineSymbols` there means boxes everywhere however good
  `Normal Font` is. That is `non_ascii_hides_icons`. The two keys are spelled
  differently in iTerm2 itself — the switch is `Use Non-ASCII Font`, the font
  is `Non Ascii Font` — and neither spelling is a typo to be tidied.
- **Compare a plist value, not its text.** PlistBuddy prints a real back as
  `0.000000`, which is not the `0` in the table; `same_value` compares numbers
  numerically so the report does not claim a change that is not one.

### bin/vlc-default

- **A bundle identifier is the only safe way to name an application.** Parallels
  publishes a Windows VM's applications into `~/Applications (Parallels)` as
  genuine `.app` bundles, so a machine with VLC inside Windows has two
  applications called VLC, and the Windows one can own `.mp4` — a double click
  then boots a virtual machine. The script writes `org.videolan.vlc` and
  reports every other VLC it finds without touching it.
- **`duti -x <ext>` is not a verification path.** It resolves by application
  *name* and returns the Parallels bundle even when the binding is correct.
  Read the preference file: `parse_handler_dump` over
  `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`.
- **duti exits 0 whether or not the write took**, so `--apply` re-reads the
  preference file afterwards and reports per type. Same rule as `command_works`.
- **The table is content types, not extensions.** Every extension maps to one,
  and a type covers the extensions a later VLC adds to it. Audio, images and
  playlists stay out of the table even though VLC opens them.
- **The parser is split from the PlistBuddy call.** `parse_handler_dump` reads a
  dump on stdin so it can be tested on Linux. It keys on brace depth because
  every handler carries a nested `LSHandlerPreferredVersions` dictionary whose
  own `LSHandlerRoleAll` is always `-`; reading fields at any depth returns `-`
  as the handler for everything.
- **`duti` is not in the catalog**, and does not need to be: it is macOS-only,
  and `--apply` installs it through the Homebrew that `setup_homebrew`
  guarantees. Reporting needs only PlistBuddy, so a bare machine still gets a
  useful report.

---

## Testing

```bash
./tests/run.sh              # every suite; this is what CI runs
./tests/run.sh nerd-font    # only the suites whose name contains this
shellcheck -S style bin/* tests/*.sh   # must be silent
```

`tests/README.md` lists what each suite covers. The six that exist because
of shipped bugs — the `linux_arm` mismatch, the dropped last asset, the
same-second backup collision, an rc file chosen from the platform instead
of the login shell, **a run that stopped after the first tool it installed**,
and **a completion script installed as the binary and reported verified** —
are the ones to keep when refactoring.

The suites need no network, no root and no particular platform: `github_api`
is overridden to emit a fixture and asset URLs point at `file://` paths, which
still exercises download, SHA-256 verification, extraction and install for
real. Anything that writes uses `temp_home`.

`temp_home` sets `TEST_HOME` rather than printing the path. `H=$(temp_home)`
would run its `export HOME` inside a subshell and leave the suite writing into
the real home directory — which is how it was first written, and what the
companions suite caught.

`NANOLANDER_LIB=1`, `ITERM_TUNE_LIB=1` and `NVIM_LAND_LIB=1` source each script
without running it.

A real Neovim load is still worth checking by hand after any change to layer 1
or 2, because no suite can:

```bash
nvim --headless file.c -c 'echo g:colors_name' -c 'silent messages' -c qa
```

`hiko_color` must still be the colorscheme and `messages` must be empty.

Point Neovim at the repository copy with a *copy*, never a symlink: lazy.nvim
writes `lazy-lock.json` next to the config it loaded.

**What CI cannot cover:** the macOS path (Homebrew, `ensure_brew_tool`, all of
`iterm-tune`) and Amazon Linux. Those need a real machine. Neovide on Linux is
another one — the binary installs fine headless but cannot run without a
desktop. The live GitHub API is a third: asset names are asserted against
fixtures shaped like the real ones. Say so plainly when reporting instead of
implying they were tested.

---

## Git Workflow

### Standing policy — every change ships as an auto-merged PR

Owner instruction (2026-09-07):

1. **Never commit on `main` locally.** Every change starts with
   `git checkout -b claude/<slug>`.
2. Commit there and `git push -u origin claude/<slug>`.
3. Open a PR against `main` as soon as the change is complete.
4. Merge it — **squash**. Prefer `enable_pr_auto_merge` so it lands when checks
   pass; fall back to `merge_pull_request` (squash) when the PR is already clean.
5. Delete the dev branch, remote **and** local, then
   `git checkout main && git pull origin main`.

No confirmation is needed before opening or merging these PRs — this instruction
is the standing authorization. Report the PR number and the merge result each
time.

**"PR and merge" — in either language, however briefly it is put — means all
five steps**, not just the first: branch, push, open the PR, squash-merge it
into `main`, then delete the branch at both ends and close the PR out. Owner
instruction, 2026-09-11. Do not stop at an open PR and wait to be told to merge
it. (The owner's usual phrasing is Chinese and cannot be quoted here: CI holds
this file to English only.)

```bash
git checkout -b claude/<slug>
# ... work, test ...
git commit -am "..."
git push -u origin claude/<slug>
# open PR → squash merge → delete branch
git checkout main && git pull origin main
git branch -d claude/<slug>
```

Commit messages: imperative mood, and say *why* when the reason is not obvious
from the diff.
