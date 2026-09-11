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

**More of both are expected**, so treat those two files as the template rather
than one-offs.

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
│   └── iterm-tune         ← iTerm2 performance tuning, macOS only
├── share/
│   └── nvim/              ← the Neovim config, vendored here on purpose
│       ├── init.vim       ← layers 1 and 2: sources ~/.vimrc, patches Neovim
│       ├── lua/hikovim/   ← layer 3: init, plugins, lsp, keys, ide
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
  table out of `lua/hikovim/lsp.lua`; keep that table's shape parseable.
- Treesitter parsers need the `tree-sitter` CLI *and* a C compiler. Neovim
  bundles `c`, `lua`, `markdown`, `query`, `vim`, `vimdoc`, which is why C
  still works on a bare box.

### Adding a terminal helper

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
