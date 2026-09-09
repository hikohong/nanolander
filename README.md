# nanolander

> Land on any machine with the whole kit.

One script that installs the same modern terminal toolchain on macOS, Ubuntu, Amazon Linux 2 and Amazon Linux 2023, then wires up the shell for you. It uses the distribution's package manager where the tool exists there, and falls back to the project's official GitHub release where it does not.

| Item | Detail |
| --- | --- |
| Main program | `bin/nanolander` |
| Companion tools | `bin/nvim-land` (Neovim configuration), `bin/iterm-tune` (iTerm2 performance tuning, macOS) |
| Tools installed | 54 |
| Install source | Package manager first, official GitHub release when missing |
| Install location | The package manager's default path, or `~/.local/bin` |
| Log | `~/nanolander-YYYYMMDD-HHMMSS.log` |

---

## Contents

- [Supported platforms](#supported-platforms)
- [Getting started](#getting-started)
- [Command-line options](#command-line-options)
- [Tool overview](#tool-overview)
- [Neovim configuration](#neovim-configuration)
- [How the script works](#how-the-script-works)
- [Shell configuration changes](#shell-configuration-changes)
- [Terminal font](#terminal-font)
- [File previews](#file-previews)
- [Tests](#tests)
- [Undoing a run](#undoing-a-run)
- [Logs and exit codes](#logs-and-exit-codes)
- [Notes and troubleshooting](#notes-and-troubleshooting)
- [Project structure](#project-structure)
- [iTerm2 tuning](#iterm2-tuning)
- [What changed in this release](#what-changed-in-this-release)

---

## Supported platforms

### Operating systems

| Operating system | Package manager | Shell config file |
| --- | --- | --- |
| macOS | Homebrew | `~/.zshrc` (plus `~/.zprofile`) |
| Ubuntu | APT | `~/.bashrc` |
| Amazon Linux 2 / legacy | YUM | `~/.zshrc` |
| Amazon Linux 2023 | DNF | `~/.zshrc` |

### CPU architectures

| Architecture | Coverage |
| --- | --- |
| `x86_64` / `amd64` | All tools |
| `arm64` / `aarch64` | All tools on macOS; on Linux all but Neovide and resvg, which upstream builds for `x86_64` only |
| `armv7` | Most tools (`dive` and `yazi` have no official armv7 build) |
| `armv6` | Some tools; the rest are reported as failed and can be skipped |

---

## Getting started

```bash
git clone https://github.com/hikohong/nanolander.git
cd nanolander
./bin/nanolander
```

You can also invoke Bash explicitly:

```bash
bash bin/nanolander
```

To call it from anywhere, link it onto your PATH:

```bash
ln -s "$PWD/bin/nanolander" ~/.local/bin/nanolander
```

Load the new settings once the run finishes:

```bash
# Ubuntu
source ~/.bashrc

# macOS / Amazon Linux
source ~/.zshrc
```

Or simply log out and back in.

---

## Command-line options

Every option combines with every other one, for example:

```bash
./bin/nanolander --set-default-shell --with-aliases --configure-git
```

### `--help` / `-h`

Show usage and examples without installing anything.

```bash
./bin/nanolander --help
```

### `--list-tools`

Print every tool the script can install (command name, tool name, purpose), so you can review the list before deciding whether to filter it with `--only` or `--skip`.

```bash
./bin/nanolander --list-tools
```

### `--only a,b,c`

Install just these tools; everything else is marked `SKIPPED`. Useful for topping up a few tools, or for getting the essentials onto a machine with limited network access. Names may be either the command or the tool name, comma separated.

```bash
./bin/nanolander --only nvim,tmux,fzf,ripgrep
```

### `--skip a,b,c`

Install everything except these. Handy for machines without Docker (drop `lazydocker` and `dive`), or when you would rather not reinstall something you already have.

```bash
./bin/nanolander --skip lazydocker,dive
```

### `--set-default-shell`

On macOS and Amazon Linux, change the current user's login shell to zsh. It does nothing if zsh is already the login shell. Ubuntu is configured through bash, so the option has no effect there.

```bash
./bin/nanolander --set-default-shell
```

### `--with-aliases`

Add an optional alias block to the shell config file, pointing familiar commands at the new tools. Every line checks that its tool exists first, so a missing tool never breaks your shell.

| Alias | Runs |
| --- | --- |
| `ls` | `eza --group-directories-first` |
| `ll` | `eza -lah --group-directories-first --git` |
| `lt` | `eza --tree --level=2` |
| `cat` | `bat --paging=never` |
| `du` | `dust` |
| `df` | `duf` |
| `top` | `btm` |

The block is fenced with `# >>> nanolander aliases >>>` and `# <<< nanolander aliases <<<`, so removing it later means deleting everything between those two lines. Without this option the script never overrides an existing command.

### `--configure-git`

Set git-delta as the global Git pager, so `git diff`, `git log` and `git show` get syntax highlighting and line numbers. The settings written:

```gitconfig
core.pager = delta
interactive.diffFilter = delta --color-only
delta.navigate = true
delta.line-numbers = true
merge.conflictStyle = zdiff3
```

If either `git` or `delta` is missing, the script prints a warning and skips it rather than writing the configuration.

### `--with-nvim-config`

Install the Neovim configuration too, by handing off to `./bin/nvim-land --apply` once the tools are in. Without it the editor is installed but left unconfigured, which is what the separate helper is for.

```bash
./bin/nanolander --with-nvim-config
```

Skipped with a warning when Neovim itself is not installed, and when the helper cannot be found beside this script — it ships in the checkout, so a copy of `bin/nanolander` on its own does not have it.

### `--restore-shell`

Put your shell config file back the way it was, from the most recent backup in `~/.nanolander-backups`. The version being replaced is saved first, under `~/.nanolander-backups/pre-restore/`, so the restore is itself undoable. Running it twice restores the same content rather than toggling.

```bash
./bin/nanolander --restore-shell
```

### `--uninstall`

Back the changes out rather than rolling the whole file back: remove only the lines nanolander added, and the tools it recorded under `~/.local`. Anything you wrote yourself stays, including edits you made after installing.

```bash
./bin/nanolander --uninstall
```

Packages installed through Homebrew, APT, DNF or YUM are left alone, because other things on the machine may depend on them. The Homebrew line in `~/.zprofile` is also left in place, since removing it takes `brew` off your PATH and it may well predate nanolander; the script says so and leaves the decision to you.

---

## Tool overview

Each entry comes with its purpose and a one-line command to get started.

### Monitoring

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **btop** | `btop` | Colourful resource monitor with live graphs for CPU, memory, disk and network, and mouse-driven process selection.<br>`btop` |
| **htop** | `htop` | Classic interactive process viewer for sorting by load and signalling heavy processes.<br>`htop -u $(whoami)` |
| **bottom** | `btm` | Second monitor with configurable widgets and a searchable process table; lighter on remote or modest machines.<br>`btm --basic` |
| **fastfetch** | `fastfetch` | Instant system summary, handy for confirming which box you just SSH'd into.<br>`fastfetch` |

### Git and development

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **lazygit** | `lazygit` | Terminal UI for Git: stage hunks, run interactive rebases and browse history without memorising flags.<br>`lazygit` |
| **tig** | `tig` | ncurses Git browser for reading log, blame and per-line history far faster than plain CLI output.<br>`tig blame src/main.c` |
| **git-delta** | `delta` | Pager built for Git diffs, with syntax highlighting, line numbers and side-by-side view.<br>`git diff \| delta` (or `--configure-git` to enable it globally) |
| **difftastic** | `difft` | Structural diff that compares syntax trees, so reindents and moved blocks stop reading as changes.<br>`difft old.py new.py` |
| **GitHub CLI** | `gh` | Work with GitHub pull requests, issues, releases and Actions from the shell.<br>`gh pr create --fill` |
| **Git** | `git` | Version control itself, installed and version-checked on all four platforms.<br>`git status -sb` |

### Code navigation and quality

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **universal-ctags** | `ctags` | Build tag indexes so Vim and Neovim can jump straight to a definition.<br>`ctags -R --exclude=.git .` |
| **cscope** | `cscope` | Cross-reference browser for C and C++ symbols, callers and callees. Note that Neovim removed cscope support; see [Neovim configuration](#neovim-configuration).<br>`cscope -Rbq` |
| **tree-sitter CLI** | `tree-sitter` | Grammar compiler. The Neovim configuration needs it to build parsers for anything beyond the six Neovim ships with.<br>`tree-sitter --version` |
| **ShellCheck** | `shellcheck` | Static analysis for shell scripts: quoting, portability and the classic footguns.<br>`shellcheck bin/nanolander` |
| **shfmt** | `shfmt` | Formatter for sh and bash, keeping indentation and style consistent across a repo.<br>`shfmt -i 2 -w script.sh` |

### Project workflow

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **just** | `just` | Task runner for per-project recipes, with syntax simpler than a Makefile.<br>`just --list` |
| **entr** | `entr` | Re-run a command whenever watched files change; the easiest test loop there is.<br>`fd -e py \| entr -c pytest` |
| **direnv** | `direnv` | Load environment variables on entering a directory and unload them on leaving. Enabled automatically.<br>`direnv allow` |

### Containers

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **lazydocker** | `lazydocker` | Terminal UI for Docker containers, images, volumes and streaming logs.<br>`lazydocker` |
| **dive** | `dive` | Inspect a Docker image layer by layer and find the wasted space.<br>`dive nginx:latest` |

### Terminal environment

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **Neovim** | `nvim` | Modern Vim fork with Lua config and LSP support, installed as the default terminal editor.<br>`nvim file.py` |
| **Neovide** | `neovide` | GUI Neovim client with smooth cursor animation and ligature support, reading the same configuration as the terminal one. Upstream builds it for macOS and `x86_64` Linux only, so elsewhere it is reported `SKIPPED`, not failed.<br>`neovide` |
| **tmux** | `tmux` | Terminal multiplexer for persistent sessions and splits, so a dropped SSH connection doesn't kill your work.<br>`tmux new -s dev` |
| **Starship** | `starship` | Fast cross-shell prompt showing Git state, language versions and run times. Enabled automatically.<br>`starship preset nerd-font-symbols` |
| **zoxide** | `zoxide` | A `cd` that remembers where you go, so a fragment of a path is enough to jump there.<br>`z proj` (`z` comes from the shell integration) |
| **Nerd Font** | — | Patched font carrying the glyphs the Starship prompt and eza icons draw with. Fetched from the upstream release on every platform, so all four get identical files.<br>See [Terminal font](#terminal-font) |

### Files and search

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **yazi** | `yazi` | Terminal file manager with asynchronous I/O, so a directory of ten thousand files does not block it, and real image previews rather than ASCII approximations. Upstream builds `x86_64` and `aarch64`, so on 32-bit ARM it is `SKIPPED`, not failed. See [File previews](#file-previews).<br>`yazi` |
| **eza** | `eza` | Modern `ls` replacement with colours, icons, tree view and Git status.<br>`eza -lah --git` |
| **bat** | `bat` | `cat` with syntax highlighting and line numbers, and a decent reader in its own right.<br>`bat script.sh` |
| **fd** | `fd` | Fast, ergonomic `find` replacement that respects `.gitignore` by default.<br>`fd --extension py` |
| **ripgrep** | `rg` | Extremely fast recursive text search across large repositories.<br>`rg "TODO" --type py` |
| **sd** | `sd` | Find and replace with syntax that is much easier to remember than `sed -i`.<br>`sd 'old_name' 'new_name' src/*.py` |
| **fzf** | `fzf` | Fuzzy finder for any list. `Ctrl-R` searches shell history and `Ctrl-T` picks files, both wired up for you.<br>`nvim $(fzf)` |
| **tree** | `tree` | Print a directory hierarchy as an indented tree.<br>`tree -L 2` |

### File preview backends

yazi renders text, code and common raster images itself. Everything else it hands to one of these, which is why they are in the catalog — though each is a useful tool in its own right.

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **file** | `file` | MIME detection: how yazi decides which previewer a file needs in the first place.<br>`file -b --mime-type report.pdf` |
| **FFmpeg** | `ffmpeg` | Video and audio thumbnails, and the duration and dimensions shown beside them. `ffprobe` is installed alongside it and is the half yazi actually calls.<br>`ffprobe -hide_banner clip.mp4` |
| **Poppler** | `pdftoppm` | Renders a PDF page to an image, so the preview pane shows the page rather than the words "PDF document".<br>`pdftoppm -png -f 1 -l 1 doc.pdf page` |
| **7-Zip** | `7zz` | Reads the contents of an archive without unpacking it, so `Enter` on a `.zip` lists what is inside.<br>`7zz l archive.zip` |
| **ImageMagick** | `magick` | Converts the formats nothing else reads — HEIC, JPEG XL, font files.<br>`magick photo.heic photo.png` |
| **resvg** | `resvg` | Renders SVG properly, rather than rasterising it badly. Upstream publishes macOS builds and one Linux build, `x86_64` only, and no distribution packages it, so elsewhere it is `SKIPPED`.<br>`resvg logo.svg logo.png` |

> `file` is already on every supported platform, so it normally reports `existing`. The others come from the package manager where it has them — including Amazon Linux 2023's `ffmpeg-free` — and from the project's release otherwise.

### Disk and space

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **dust** | `dust` | Visual `du` that points straight at the directories eating your disk.<br>`dust -d 2` |
| **duf** | `duf` | Readable `df` with a table of mounted filesystems and usage bars.<br>`duf` |
| **ncdu** | `ncdu` | Interactive disk usage browser that can delete large files in place.<br>`ncdu /var` |

### Data and documents

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **jq** | `jq` | The standard command-line JSON processor for querying and reshaping payloads.<br>`curl -s api/url \| jq '.items[].name'` |
| **yq** | `yq` | jq-style processor for YAML, JSON, TOML and XML, ideal for Kubernetes and CI config.<br>`yq '.services.web.image' docker-compose.yml` |
| **glow** | `glow` | Render Markdown files beautifully in the terminal.<br>`glow README.md` |
| **tldr** | `tldr` | Community-written practical examples, faster to scan than a man page.<br>`tldr tar` |

### Network and measurement

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **xh** | `xh` | Fast HTTP client with HTTPie-like syntax for poking at APIs by hand.<br>`xh GET httpbin.org/get name==value` |
| **gping** | `gping` | `ping` with a live latency graph, so jitter is obvious at a glance.<br>`gping 8.8.8.8 google.com` |
| **hyperfine** | `hyperfine` | Benchmark commands with warmup runs and proper statistics.<br>`hyperfine 'rg TODO' 'grep -r TODO .'` |
| **wget** | `wget` | Non-interactive downloader with resume and whole-site mirroring.<br>`wget -c https://example.com/file.iso` |

### System basics

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **watch** | `watch` | Re-run a command on a fixed interval and watch the output change.<br>`watch -n 2 'kubectl get pods'` |
| **rsync** | `rsync` | Reliable incremental file sync, locally or over SSH.<br>`rsync -avz ./src/ user@host:/dst/` |
| **unzip** | `unzip` | Extract `.zip` archives.<br>`unzip archive.zip -d target/` |

> macOS and most Linux distributions already ship `rsync`, `unzip` and `watch`. The summary then shows `existing` and the script does not reinstall them.

---

## Neovim configuration

`bin/nanolander` installs Neovim; `bin/nvim-land` configures it. They are separate steps because a configuration is an opinion, and installing a binary is not.

```bash
./bin/nvim-land              # report only, changes nothing
./bin/nvim-land --apply      # back up ~/.config/nvim, then install
./bin/nvim-land --apply --no-sync   # install the files, fetch plugins later
./bin/nvim-land --restore    # restore the most recent backup
```

The files live in `share/nvim` and are copied to `~/.config/nvim`. Only files nanolander ships are written; anything else you keep there is reported and left alone.

### Three layers

| Layer | What it is | Where it comes from |
| --- | --- | --- |
| 1 | `~/.vimrc` and `~/.vim`, sourced as they are | your own vim configuration, shared byte for byte with vim |
| 2 | the places where Neovim is not vim | `init.vim` |
| 3 | treesitter, LSP and the modern plugin set | `lua/hikovim/`, fetched by lazy.nvim |

Layer 1 is optional: without a `~/.vimrc` the configuration still loads, and falls back to Neovim's `habamax` colourscheme. Sourcing it rather than copying it is the point — vim and Neovim never drift apart, and re-running your vim installer updates both.

### What layer 3 replaces

Each replacement disables its predecessor in Neovim only, by setting the plugin's guard variable before `~/.vimrc` is read. Vim keeps using the old one exactly as before.

| Was, in `~/.vim/plugin` | Now | Why |
| --- | --- | --- |
| `airline.vim` | `lualine.nvim` | Same badwolf palette and separators, a fraction of the startup cost |
| `gitgutter.vim` | `gitsigns.nvim` | Asynchronous, so it does not stall on a large file |
| `taglist.vim`, `tagbar.vim` | `aerial.nvim` | Outline from the language server or treesitter, with no tags file to regenerate |
| `NERD_tree.vim` | `oil.nvim` | A directory is an ordinary buffer: `dd` deletes, `p` pastes, `:w` applies |
| `syntax on` | `nvim-treesitter` | Accurate folds and highlighting from a real parse |
| `vimirc.vim` | — | An IRC client is not an editor's job |

`DirDiff.vim` and `filter.vim` have no replacement, so they keep loading.

### Keys

Muscle memory wins. Only the mappings whose vim plugin no longer exists are rebound, and they keep their original keys.

| Key | Was | Now |
| --- | --- | --- |
| `,tb` | `:TagbarToggle` | `:AerialToggle` |
| `<C-\>s` | `cs find s` — this symbol | LSP references, else a ripgrep word search |
| `<C-\>g` | `cs find g` — its definition | LSP definition, else the tags file |
| `<C-\>c` | `cs find c` — callers | LSP incoming calls |
| `<C-\>d` | `cs find d` — callees | LSP outgoing calls |
| `<C-\>t` `<C-\>e` | text and pattern search | ripgrep through fzf-lua |
| `<C-\>f` `<C-\>i` | this file, files including it | fzf-lua file and grep pickers |
| `<F5>` | (commented out) `:NERDTreeToggle` | `:Oil` |

Everything else — `,sp`, `,lp`, `,ic`, `,f`, `,F`, `<space>`, `<backspace>`, `<C-h>`, `<C-Z>` — comes straight from `~/.vimrc` and behaves as it always did. New maps only go on keys the vim configuration leaves free: `,gb`, `,gp`, `,ff`, `,fg`, `,fb`, `,fd`, `]c`, `[c`.

### Things worth knowing

- **Neovim removed cscope.** `has('cscope')` is `0`, so `~/.vimrc`'s cscope block never runs there. The `<C-\>` keys above are the replacement; for real cscope, use `vim`.
- **A language server beats both cscope and ctags**, and nanolander does not install one. `clangd` for C and C++ is the one worth having; `./bin/nvim-land` reports which servers this machine can already run.
- **Parsers need the tree-sitter CLI and a C compiler.** Neovim ships parsers for `c`, `lua`, `markdown`, `query`, `vim` and `vimdoc`, so C works out of the box; anything else compiles on first start once `tree-sitter` is installed.
- **Treesitter highlighting does not look pixel-identical to vim**, because it paints with `@capture` groups rather than the ones `hiko_color` was tuned for. Set `TS_HIGHLIGHT = false` at the top of `lua/hikovim/plugins.lua` to keep treesitter for folds only.
- **`,sp` and `,lp` write `session.nvim` and `shada.nvim`**, not `session.vim` and `viminfo.vim`. Neovim's info file is msgpack shada and vim's is text, so sharing one pair would leave whichever editor wrote last unreadable to the other.
- **Completion is on demand** (`<C-x><C-o>`), not as you type, matching the reason `~/.vimrc` turned OmniCppComplete's popup off.
- **A running Neovim keeps its old configuration** until you restart it. That is harmless, so unlike `bin/iterm-tune` this script does not refuse to write while the program is open.

---

## How the script works

This section describes what each function is responsible for, which should make maintaining or extending the script easier.

### Environment detection

On startup the script reads `uname -s` and `/etc/os-release` to decide the package manager (brew / apt-get / dnf / yum) and the shell config target. It also normalises `uname -m` into `x86_64`, `arm64`, `armv7` or `armv6`, which is what later selects the right GitHub release asset. An unsupported system exits immediately with status `1`.

### `wants_tool`

The `--only` and `--skip` filter. Matching ignores case and surrounding whitespace, and either the command name or the tool name will match. Filtered tools are marked `SKIPPED` in the summary and are never treated as failures.

### `print_tool_catalog`

Produces the `--list-tools` output. The catalog itself lives in the `TOOL_CATALOG` variable at the top of the script, so adding a tool means updating that one place.

### `setup_homebrew`

macOS only. If `brew` is missing, the script downloads the official installer and runs it non-interactively, then loads `brew shellenv` from `/opt/homebrew` or `/usr/local`. A failure here aborts the run, because every later macOS step depends on Homebrew.

### `package_available` / `package_installed` / `install_package`

These answer, in order, "does the repository carry this package", "is it already installed locally" and "install it". Each switches on `PKG_MANAGER` to the matching command — `apt-cache`, `dpkg-query`, `rpm`, `brew list` and so on — so the calling code never has to care about the platform. Packages that are already installed are skipped.

### `try_package_candidates`

The same tool can be packaged under different names across distributions, for example `fd-find` versus `fd`, `tlrc` versus `tldr`, or `procps-ng` versus `procps`. This function walks the candidate names in order and returns as soon as one succeeds.

### `github_install`

The path taken for tools the repositories do not carry:

1. Call the GitHub API for the project's latest release.
2. Pick the right archive using the keywords for this CPU architecture.
3. After downloading, verify the SHA-256 digest when GitHub supplies one, and abort on a mismatch.
4. Extract, locate the executable, and install it into `~/.local/bin`.
5. Asset selection tries a full suffix match before falling back to keyword containment, so `linux_arm` never gets picked for an `arm64` host.
6. Some projects use a different name inside the archive (yq ships `yq_linux_amd64`); the file is extracted under the correct name and installed as the plain command.
7. Some projects publish a single bare executable rather than an archive (shfmt, direnv); the extraction step is skipped.
8. Neovim needs its full runtime directory, so it is installed into `~/.local/opt/nvim-github` with a symlink in `~/.local/bin`.

Setting the `GITHUB_TOKEN` environment variable adds an authentication header, which raises the API rate limit.

### `github_asset_name`

Two projects publish more than one build per architecture, and for both of them keyword matching picks the wrong one, so their asset is named outright:

| Tool | Why matching gets it wrong |
| --- | --- |
| yazi | Upstream ships a `gnu` and a `musl` build of each target. The `gnu` one wants a newer glibc than Amazon Linux 2 has, so it installs and then cannot run. The `musl` one is static and runs everywhere. |
| FFmpeg | Every target comes as `-gpl` and `-gpl-shared`, and containment finds the shared one first because it sorts earlier. Its `ffmpeg` needs the archive's `lib` directory, which the install throws away. |

If upstream ever renames one of those files, the run says so and falls back to keyword matching rather than failing.

### `github_extras`

Some archives carry a second binary that is not optional. yazi ships `ya`, which is what runs `ya pkg` for plugins; FFmpeg ships `ffprobe`, which is the half yazi calls to read a video's dimensions. Both are installed alongside the catalog command and recorded for `--uninstall`. A missing extra is a warning, not a failure.

### `tool_unsupported_here` / `ensure_tool`

The catalog is deliberately the same on all four platforms, with three exceptions. Neovide is a GUI client and resvg has a single Linux target, so upstream builds both for macOS and `x86_64` Linux only; yazi has no 32-bit ARM build anywhere. None of the three is in the Debian, Ubuntu or Amazon Linux repositories either, so on a Graviton instance or a Raspberry Pi there is genuinely nothing to fetch. Those are recorded `SKIPPED` with the reason `platform` rather than counted as failures. `ensure_tool` is the wrapper that makes that decision before choosing the Homebrew or the Linux path.

### `make_compat_links`

Three tools are packaged under a different executable name than the one everything else expects. Debian and Ubuntu call them `fdfind` and `batcat`; the older p7zip packages call 7-Zip `7z` rather than `7zz`; and ImageMagick 6 — still what Ubuntu and Amazon Linux package — has `convert` but no `magick`. This function creates `fd`, `bat`, `7zz` and `magick` links in `~/.local/bin` so that usage stays the same on every platform. The ImageMagick link covers the plain `convert in out` form the previewers use; it is not a general ImageMagick 7 substitute.

### `command_works`

Confirms a tool really is usable: first that the command exists, then by actually running a version query. `tmux` uses `-V`, `unzip` and `pdftoppm` use `-v`, `cscope` uses `-V`, `ffmpeg` uses `-version`; everything else uses `--version`. `entr` and 7-Zip have no version flag at all — a bare `7zz` prints its banner and then a usage screen — so for those two being on the PATH is the test. Only a tool that passes is recorded as a success.

### `ensure_linux_tool` / `ensure_brew_tool`

The body of the install flow for one tool. The order is: filter check → skip if already present → package manager → GitHub release if needed → final verification → record the result and its source. `ensure_brew_tool` is the simplified macOS version and only uses Homebrew.

### Shell configuration

Before writing to a config file the script always compares the whole line, so re-running never produces a duplicate. The exact content is listed in the next section.

### Installation summary

At the end the script prints a table showing each tool, its status (`SUCCESS` / `FAILED` / `SKIPPED`), its source (`existing`, `package manager`, `GitHub release`, `filter`) and its path, followed by counts of successes, skips and failures.

---

## Shell configuration changes

Depending on the platform, the script writes to `~/.bashrc` or `~/.zshrc`:

| Setting | Content | Condition |
| --- | --- | --- |
| PATH | `export PATH="$HOME/.local/bin:$PATH"` | Always |
| Homebrew | `eval "$(brew shellenv)"` added to `~/.zprofile` | macOS only |
| zoxide | `eval "$(zoxide init zsh\|bash)"` | zoxide installed successfully |
| Starship | `eval "$(starship init zsh\|bash)"` | Starship installed successfully |
| direnv | `eval "$(direnv hook zsh\|bash)"` | direnv installed successfully |
| fzf key bindings | `eval "$(fzf --zsh\|--bash)"`, enabling `Ctrl-R` and `Ctrl-T` | fzf installed successfully |
| fzf search source | `export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'` | both fzf and fd available |
| Alias block | See `--with-aliases` | `--with-aliases` given |

The fzf lines are guarded with a `command -v fzf` check and have their errors suppressed, so removing fzf later, or running an older version of it, will not make your shell complain at startup.

---

## Terminal font

The Starship prompt and eza's icons draw glyphs from the Nerd Font range. A terminal whose font lacks them shows a box for each one, which is what a prompt like `nanolander on □ main` means — a missing glyph, not a broken encoding.

nanolander installs a patched font for you. It takes it from the [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) release rather than from Homebrew, APT, DNF or YUM, so macOS, Ubuntu and both Amazon Linux versions end up with byte-identical files. Only the destination differs:

| Platform | Installed into |
| --- | --- |
| macOS | `~/Library/Fonts` |
| Linux | `~/.local/share/fonts`, followed by `fc-cache -f` |

Only the monospaced faces are installed. The archive also ships proportional and variable-width cuts, which a terminal cannot use and which would bury the useful faces in every font picker on the machine. If any Nerd Font is already present, the script leaves your choice alone and reports `existing`.

Pick a different family with `NANOLANDER_NERD_FONT`, using any family name from the release:

```bash
NANOLANDER_NERD_FONT=Hack ./bin/nanolander --only nerd-font
```

### Then select it in your terminal

**Installing a font cannot change which font your terminal is set to** — that setting belongs to the terminal, and on a remote machine it belongs to the terminal on your laptop, not the box you are SSH'd into. Once the run finishes, choose **JetBrainsMono Nerd Font Mono** (or whichever family you installed):

| Terminal | Where |
| --- | --- |
| iTerm2 | Settings → Profiles → Text → Font |
| Terminal.app | Settings → Profiles → Text → Font → Change |
| GNOME Terminal | Preferences → your profile → Text → Custom font |
| VS Code | `"terminal.integrated.fontFamily": "JetBrainsMono Nerd Font Mono"` |

If you would rather not change the font, tell Starship to use plain text instead:

```bash
mkdir -p ~/.config
printf '[git_branch]\nsymbol = " "\n' >> ~/.config/starship.toml
```

---

## File previews

yazi previews images by drawing them, not by approximating them in text. **Installing it cannot make your terminal capable of that**, for the same reason installing a font cannot select it: the decision belongs to the terminal, and on a remote machine it belongs to the terminal on your own laptop rather than the box you are SSH'd into.

### Over SSH

The three protocols yazi can use are all escape sequences on stdout, so they do travel over SSH. Only one adapter cannot.

| Adapter | Works over SSH | Why |
| --- | --- | --- |
| Kitty graphics protocol | yes | an escape sequence carrying the image inline |
| iTerm2 inline images | yes | the same, base64 inside the sequence |
| Sixel | yes | the same |
| Überzug++ | **no** | it opens an overlay window and so needs a local display |

Three things get in the way in practice:

1. **`TERM_PROGRAM` is not forwarded.** yazi reads the environment to decide which adapter to use, and SSH does not pass that variable. Add it per host in `~/.ssh/config`:

   ```
   Host myhost
     SetEnv TERM_PROGRAM=iTerm.app
   ```

2. **tmux swallows the sequences** unless it is told to pass them through, which needs tmux 3.3 or newer:

   ```bash
   echo 'set -g allow-passthrough on' >> ~/.tmux.conf
   ```

3. **The backends have to be on the machine you are browsing**, not on your laptop. That is what the [File preview backends](#file-preview-backends) entries are for, and why nanolander installs them on the remote box along with yazi.

Ask yazi what it actually detected:

```bash
yazi --debug
```

On a slow link the image payloads are the expensive part; nothing else about yazi is chatty.

---

## Tests

```bash
./tests/run.sh              # every suite
./tests/run.sh nerd-font    # only the suites whose name contains this
```

They need no network, no root and no particular platform: GitHub releases are local fixtures served over `file://` with the API call stubbed, and anything that writes writes into a throwaway `HOME`. That covers the download, SHA-256 check, extraction and install path for real.

Four suites exist because of a way asset selection or a write can go wrong — an `arm64` host handed a `linux_arm` build, the last asset of every release silently dropped, a same-second backup collision that destroyed the only copy of an rc file, and keyword matching preferring FFmpeg's shared build and yazi's `gnu` build over the ones that actually run. Each has an assertion now, so a refactor cannot quietly reopen them.

What they cannot reach: macOS (Homebrew, and all of `iterm-tune`'s writing), Amazon Linux, the live GitHub API, and a real Neovim load. `tests/README.md` says so in full; CI repeats the same list rather than implying otherwise.

---

## Undoing a run

Installing changes how your shell looks and behaves — the prompt in particular, which comes from Starship. Both ways back are built in.

### Backups

The first time a run is about to write to `~/.zshrc`, `~/.bashrc` or `~/.zprofile`, the file is copied to:

```
~/.nanolander-backups/.zshrc.YYYYMMDD-HHMMSS
```

A run that changes nothing writes no backup, so re-running does not pile up copies. If the backup cannot be written, the script refuses to modify the file rather than changing it with no way back.

### Rolling the file back

```bash
./bin/nanolander --restore-shell
```

Restores the most recent backup of each shell config file. Your current version is kept under `~/.nanolander-backups/pre-restore/` first.

### Removing just what nanolander added

```bash
./bin/nanolander --uninstall
```

Removes the managed lines and the fenced alias block from your rc files, and deletes the tools recorded in `~/.local/share/nanolander/installed`. Only paths under `~/.local` are ever deleted; anything else in that list is refused and reported.

### By hand

Every line the script adds is appended whole and never edits an existing one, so removing them by hand is safe. To get only the old prompt back, delete the Starship line:

```bash
sed -i.bak '/eval "$(starship init /d' ~/.zshrc   # ~/.bashrc on Ubuntu
exec $SHELL -l
```

`--configure-git` and `--set-default-shell` are not covered by `--uninstall`, because both change state outside this project:

```bash
git config --global --unset core.pager
git config --global --unset interactive.diffFilter
git config --global --unset delta.navigate
git config --global --unset delta.line-numbers
git config --global --unset merge.conflictStyle

chsh -s /bin/bash   # or whichever shell you had before
```

---

## Logs and exit codes

### Logs

Every run writes a transcript identical to what appeared on screen:

```
~/nanolander-YYYYMMDD-HHMMSS.log
```

When an install fails, search the log by tool name to find the relevant section, for example `== Installing yq ==`.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Every tool installed and verified, including any filtered out |
| `1` | Environment preparation or a required step failed (unknown system, package index refresh failed) |
| `2` | One or more tools failed to install or could not be verified |
| `64` | Bad arguments |
| `130` | Interrupted by the user |

---

## Notes and troubleshooting

- **sudo password**: installing system packages on Linux may ask for your password. The script verifies sudo access up front.
- **Homebrew**: on macOS without Homebrew, the script downloads and runs the official installer.
- **GitHub API limits**: unauthenticated calls have a low quota, so installing many tools at once can hit a `403`. Set a token first:

  ```bash
  export GITHUB_TOKEN=ghp_xxx
  ./bin/nanolander
  ```

- **Docker tools**: `lazydocker` and `dive` need a working local Docker to be useful. On machines without it, use `--skip lazydocker,dive`.
- **Repository-only tools**: `tig`, `cscope`, `entr` and `ctags` have no official cross-platform binaries and can only come from a distribution package, and so do Poppler, ImageMagick and `file`, which every supported distribution carries. Amazon Linux 2023 does not include EPEL, so some of these may come out as `FAILED`; either exclude them with `--skip tig,cscope,entr` or enable EPEL yourself and run again.
- **Boxes instead of a picture**: yazi is installed and the backends are there, but the terminal cannot draw an image. See [File previews](#file-previews) — inside tmux it is usually the missing `allow-passthrough` line.
- **`.tar.xz` release assets** (FFmpeg, 7-Zip) need `xz` for `tar` to unpack them. A minimal image may not have it; the run says so rather than reporting an unexplained extraction failure. Install `xz` or `xz-utils` and run again.
- **Amazon Linux 2**: the repositories are older, so most modern tools are installed from a GitHub release into `~/.local/bin`. That is expected.
- **armv6 machines**: official release coverage is limited, and tools without a matching build are marked `FAILED`. Use `--only` to pick the ones you know work.
- **When an install fails**: look at the `FAILED` rows in the summary first, then the matching section of the log. Everything else that succeeded is unaffected and ready to use.
- **Re-running**: the script is safe to run repeatedly. Tools already present show as `existing`, and shell configuration is never added twice.
- **Boxes instead of icons**: the font is installed but your terminal is still set to something else. See [Terminal font](#terminal-font).
- **Neovide on a server**: Neovide is a GUI client and needs a desktop. On a headless box install it if you like, but there is nothing to display; `--skip neovide` keeps the summary tidy. On Linux it is only built for `x86_64`, and elsewhere it is reported `SKIPPED (platform)`.
- **Neovim configuration**: installing Neovim does not configure it. Run `./bin/nvim-land` for a report, then `--apply`. See [Neovim configuration](#neovim-configuration).
- **Changing your mind**: see [Undoing a run](#undoing-a-run). Shell config files are backed up before the first write of every run.

---

## Project structure

```
nanolander/
├── bin/
│   ├── nanolander      the main install script
│   ├── nvim-land       install the Neovim configuration
│   └── iterm-tune      iTerm2 performance tuning (macOS only)
├── share/
│   └── nvim/           the Neovim configuration bin/nvim-land installs
│       ├── init.vim
│       ├── lua/hikovim/{init,plugins,lsp,keys}.lua
│       └── lazy-lock.json   the pinned plugin set, written by --freeze
├── tests/              the suites, plus run.sh to run them all
├── docs/
│   └── index.html      the project page
├── README.md
└── LICENSE
```

`docs/` can be published directly as the project site through GitHub Pages.

## iTerm2 tuning

macOS users can also tune iTerm2's rendering settings. Look at the current state first, then apply once you are happy:

```bash
./bin/iterm-tune              # report only, changes nothing
./bin/iterm-tune --apply      # back up, then apply (quit iTerm2 first)
./bin/iterm-tune --restore    # restore the most recent backup
```

What it covers: GPU rendering is not disabled on battery, rendering favours throughput, transparency and blur are turned off, ligatures are turned off, and scrollback becomes bounded instead of unlimited. Trigger counts and background images are reported only, never modified.

## What changed in this release

### yazi and its preview backends (new, 47 → 54)

`yazi` joins the catalog as the file manager, together with the six things it hands a file to when it cannot render it itself: `file`, FFmpeg, Poppler, 7-Zip, ImageMagick and resvg. All seven install on every supported platform that has a build — see [File preview backends](#file-preview-backends) for what each one covers, and [File previews](#file-previews) for why installing them still cannot make your terminal draw an image.

Two mechanisms came with them, both in `github_install`:

- `github_asset_name` pins the exact release asset for the two projects where keyword matching picks the wrong file — yazi's `gnu` build, which will not run on Amazon Linux 2, and FFmpeg's `-gpl-shared` build, whose binary needs a `lib` directory the install discards. An upstream rename falls back to matching with a warning instead of failing.
- `github_extras` installs the second binary an archive carries when it is not optional: `ya` with yazi, `ffprobe` with FFmpeg.

`make_compat_links` gained two more links for the same reason it had the first two: the older p7zip packages call 7-Zip `7z`, and ImageMagick 6 has `convert` but no `magick`.

### Neovim configuration (new)

`bin/nvim-land` installs `share/nvim` into `~/.config/nvim`: `~/.vimrc` and `~/.vim` are sourced rather than copied, the two places where Neovim differs from vim are patched, and lazy.nvim brings in treesitter, LSP, aerial, gitsigns, lualine, oil and fzf-lua. Reports by default, backs up before writing, and `--restore` puts the previous tree back. See [Neovim configuration](#neovim-configuration).

Two tools joined the catalog for it: `neovide`, the GUI client, and the `tree-sitter` CLI that compiles parsers.

### New tools (19 → 47)

Monitoring and files: `bottom`, `dive`, `sd`, `tree`, `duf`, `yq`, `glow`, `xh`, `gping`, `hyperfine`, `watch`, `rsync`, `wget`, `unzip`

Everyday development: `git`, `tig`, `git-delta`, `difftastic`, `ctags`, `cscope`, `ShellCheck`, `shfmt`, `just`, `entr`, `direnv`

Install paths are now complete for all four operating systems and every CPU architecture: macOS goes through Homebrew, Linux prefers the repositories and falls back to the project's official GitHub release, with each project's file naming and archive layout confirmed.

### New options

`--list-tools`, `--only`, `--skip`, `--with-aliases`, `--configure-git`, with support for combining several options in one run (previously only a single argument was accepted).

### Other changes

- `github_install` now handles projects whose archive contents are named differently from the archive (yq) and projects that publish a bare executable (shfmt, direnv), and asset selection compares the full suffix first.
- direnv adds its shell hook automatically after installation.
- fzf key bindings and search source are now integrated.
- `command_works` gained the `unzip -v`, `cscope -V` and `entr` verification paths.
- The script itself passes ShellCheck cleanly.
- The summary gained the `SKIPPED` status and a skipped count; filtered tools do not affect the exit code.
- A package that installs cleanly without providing the command no longer ends the search. Homebrew's `tree-sitter` is the library and ships no binary; the next candidate, `tree-sitter-cli`, is now tried, and on Linux the GitHub release fallback is reachable from that case too.
- A `.zip` release asset pulls `unzip` forward when it is not installed yet, the way the font already did.
