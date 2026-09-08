# nanolander

> Land on any machine with the whole kit.

One script that installs the same modern terminal toolchain on macOS, Ubuntu, Amazon Linux 2 and Amazon Linux 2023, then wires up the shell for you. It uses the distribution's package manager where the tool exists there, and falls back to the project's official GitHub release where it does not.

| Item | Detail |
| --- | --- |
| Main program | `bin/nanolander` |
| Companion tool | `bin/iterm-tune` (iTerm2 performance tuning, macOS) |
| Tools installed | 44 |
| Install source | Package manager first, official GitHub release when missing |
| Install location | The package manager's default path, or `~/.local/bin` |
| Log | `~/nanolander-YYYYMMDD-HHMMSS.log` |

---

## Contents

- [Supported platforms](#supported-platforms)
- [Getting started](#getting-started)
- [Command-line options](#command-line-options)
- [Tool overview](#tool-overview)
- [How the script works](#how-the-script-works)
- [Shell configuration changes](#shell-configuration-changes)
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
| `arm64` / `aarch64` | All tools |
| `armv7` | Most tools (`dive` has no official armv7 build) |
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
| **cscope** | `cscope` | Cross-reference browser for C and C++ symbols, callers and callees.<br>`cscope -Rbq` |
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
| **tmux** | `tmux` | Terminal multiplexer for persistent sessions and splits, so a dropped SSH connection doesn't kill your work.<br>`tmux new -s dev` |
| **Starship** | `starship` | Fast cross-shell prompt showing Git state, language versions and run times. Enabled automatically.<br>`starship preset nerd-font-symbols` |
| **zoxide** | `zoxide` | A `cd` that remembers where you go, so a fragment of a path is enough to jump there.<br>`z proj` (`z` comes from the shell integration) |

### Files and search

| Tool | Command | What it does, and an example |
| --- | --- | --- |
| **eza** | `eza` | Modern `ls` replacement with colours, icons, tree view and Git status.<br>`eza -lah --git` |
| **bat** | `bat` | `cat` with syntax highlighting and line numbers, and a decent reader in its own right.<br>`bat script.sh` |
| **fd** | `fd` | Fast, ergonomic `find` replacement that respects `.gitignore` by default.<br>`fd --extension py` |
| **ripgrep** | `rg` | Extremely fast recursive text search across large repositories.<br>`rg "TODO" --type py` |
| **sd** | `sd` | Find and replace with syntax that is much easier to remember than `sed -i`.<br>`sd 'old_name' 'new_name' src/*.py` |
| **fzf** | `fzf` | Fuzzy finder for any list. `Ctrl-R` searches shell history and `Ctrl-T` picks files, both wired up for you.<br>`nvim $(fzf)` |
| **tree** | `tree` | Print a directory hierarchy as an indented tree.<br>`tree -L 2` |

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

### `make_compat_links`

Debian and Ubuntu name the executables `fdfind` and `batcat`. This function creates `fd` and `bat` links in `~/.local/bin` so that usage stays the same on every platform.

### `command_works`

Confirms a tool really is usable: first that the command exists, then by actually running a version query. `tmux` uses `-V`, `unzip` uses `-v` and `cscope` uses `-V`; everything else uses `--version`. `entr` has no version flag, so being on the PATH is the test. Only a tool that passes is recorded as a success.

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
- **Repository-only tools**: `tig`, `cscope`, `entr` and `ctags` have no official cross-platform binaries and can only come from a distribution package. Amazon Linux 2023 does not include EPEL, so these may come out as `FAILED`; either exclude them with `--skip tig,cscope,entr` or enable EPEL yourself and run again.
- **Amazon Linux 2**: the repositories are older, so most modern tools are installed from a GitHub release into `~/.local/bin`. That is expected.
- **armv6 machines**: official release coverage is limited, and tools without a matching build are marked `FAILED`. Use `--only` to pick the ones you know work.
- **When an install fails**: look at the `FAILED` rows in the summary first, then the matching section of the log. Everything else that succeeded is unaffected and ready to use.
- **Re-running**: the script is safe to run repeatedly. Tools already present show as `existing`, and shell configuration is never added twice.
- **Changing your mind**: see [Undoing a run](#undoing-a-run). Shell config files are backed up before the first write of every run.

---

## Project structure

```
nanolander/
├── bin/
│   ├── nanolander      the main install script
│   └── iterm-tune      iTerm2 performance tuning (macOS only)
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

### New tools (19 → 44)

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
