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
44 tools and the same shell behaviour.

| Platform | Package manager | Shell config target |
| --- | --- | --- |
| macOS | Homebrew | `~/.zshrc` (+ `~/.zprofile`) |
| Ubuntu | APT | `~/.bashrc` |
| Amazon Linux 2 / older | YUM | `~/.zshrc` |
| Amazon Linux 2023 | DNF | `~/.zshrc` |

Architectures: `x86_64`, `arm64` (full), `armv7` (most), `armv6` (partial).

Terminal-specific helper scripts live alongside the main script. Today that is
`bin/iterm-tune` for iTerm2 on macOS; **more terminals are expected**, so treat
that file as the template rather than a one-off.

---

## Repository Structure

```
/
├── CLAUDE.md              ← this file (agent memory)
├── README.md              ← the specification, in English; keep it true
├── LICENSE                ← MIT
├── bin/
│   ├── nanolander         ← the main installer (bash 3.2, ~1330 lines)
│   └── iterm-tune         ← iTerm2 performance tuning, macOS only
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
- **Idempotent.** Re-running must not duplicate a shell rc line or reinstall
  what is already there. Shell config is written with whole-line comparison
  (`grep -Fqx`).
- **The log is the screen.** `~/nanolander-YYYYMMDD-HHMMSS.log` is a
  byte-for-byte copy of stdout, which is why the output helpers emit plain text
  with no ANSI colour. `grep '== Installing yq =='` on the log must keep working.
- **Never log a secret.** `GITHUB_TOKEN` may be set; report only that it exists.
- **Exit codes are API**: `0` all good · `1` environment prep failed · `2` some
  tools failed · `64` bad arguments · `130` interrupted.

---

## bin/nanolander architecture

Flow: detect environment → sudo check → Homebrew (macOS) → refresh package
index → per tool: filter, skip if present, package manager, GitHub release,
verify → shell config → summary.

| Function | Responsibility |
| --- | --- |
| `detect_environment` | `uname -s` + `/etc/os-release` → package manager, rc file; `uname -m` → arch keyword set |
| `wants_tool` / `list_contains` | `--only` / `--skip`, case- and whitespace-insensitive, command name or display name |
| `print_tool_catalog` | `--list-tools`, reads `TOOL_CATALOG` |
| `setup_homebrew` | macOS only; installs Homebrew non-interactively if missing. Fatal on failure |
| `package_available` / `package_installed` / `install_package` | one interface over brew / apt / dnf / yum |
| `try_package_candidates` | walks `pkg_candidates` in order (`fd` vs `fd-find`, `tlrc` vs `tldr`, `procps-ng` vs `procps`) |
| `github_install` | latest release → pick asset → verify SHA-256 → extract → install to `~/.local/bin` |
| `select_asset` | **full suffix match first, substring second** — this is what stops `linux_arm` matching an `arm64` host |
| `parse_assets` | flattens the release JSON without jq; pairs each URL with its own digest |
| `find_payload` | exact basename, then prefix — catches `yq_linux_amd64`, `shfmt_v3.10.0_linux_amd64`, `direnv.linux-amd64` |
| `install_neovim_tree` | Neovim needs its runtime dir: `~/.local/opt/nvim-github` + symlink |
| `make_compat_links` | Debian/Ubuntu ship `fdfind` / `batcat`; link them to `fd` / `bat` |
| `command_works` | runs a real version query. Exceptions: `tmux -V`, `unzip -v`, `cscope -V`, `entr` by PATH presence |
| `configure_shell` | PATH, zoxide, starship, direnv, fzf keys + `FZF_DEFAULT_COMMAND`, optional alias block |

`NANOLANDER_LIB=1 . ./bin/nanolander` sources the functions without running
anything. Use it to test internals.

### Adding a tool

Three places, in this order:

1. `TOOL_CATALOG` — `command|display name|category|purpose`
2. `pkg_candidates` — distro package names to try, most specific first
3. `github_repo` — `owner/repo`, or omit it if the project ships no
   cross-platform binaries (`tig`, `cscope`, `entr`, `ctags` are repository-only)

Then update the tool count and the tables in `README.md` **and
`docs/index.html`**.

### Adding a terminal helper

Follow `bin/iterm-tune`:

- **Report by default.** Writing requires an explicit `--apply`.
- **Back up before writing**, into `~/.nanolander-backups/`, and provide
  `--restore`.
- **Refuse to write while the terminal is running** — it will overwrite the
  file with its in-memory state on quit.
- Keep the "what to change" as a `key|type|desired|label` table so it can be
  unit-tested without the target OS.
- Report the user's own content (triggers, background images); never modify it.

---

## Testing

Before any push:

```bash
shellcheck -S style bin/nanolander bin/iterm-tune   # must be silent
bash -n bin/nanolander && bash -n bin/iterm-tune
./bin/nanolander --list-tools                       # tool count sane
./bin/nanolander --only tree                        # exercises a real install
./bin/nanolander --only tree                        # run twice: idempotency
```

`github_install` can be exercised offline by overriding `github_api` to emit a
fixture and pointing asset URLs at `file://` paths — that covers download,
SHA-256 verification (including a deliberate mismatch), extraction and install
without touching the network.

**What CI cannot cover:** the macOS path (Homebrew, `ensure_brew_tool`, all of
`iterm-tune`) and Amazon Linux. Those need a real machine. Say so plainly when
reporting instead of implying they were tested.

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
