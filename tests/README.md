# tests

```bash
./tests/run.sh              # everything
./tests/run.sh nerd-font    # only suites whose name contains this
```

Every suite is plain bash and ends with `<n> passed, <m> failed`. `run.sh`
adds them up and exits non-zero if anything failed.

## What they cover

| Suite | Covers |
| --- | --- |
| `test-asset-selection.sh` | release-asset matching and `--only` / `--skip` |
| `test-github-install.sh` | download, SHA-256, extraction, install, rc idempotency |
| `test-preview-backends.sh` | yazi and the preview backends: pinned asset names, extra binaries, platform skips, compat links |
| `test-nerd-font.sh` | family selection, monospaced-only rule, manifest |
| `test-shell-config.sh` | backups, `--restore-shell`, `--uninstall` |
| `test-shell-target.sh` | which rc file a run writes to, and why: login-shell detection, `--shell`, the `--set-default-shell` interaction, the foreign-file report |
| `test-uninstall.sh` | manifest path guard across both font directories |
| `test-nvim-land.sh` | `report` / `--apply` / `--restore` |
| `test-video-preview.sh` | what opening a video shows: ffprobe formatting, the nowrite guard, graceful degradation |
| `test-ide-remote.sh` | the nvim remote-open shell line, `--freeze`'s lockfile guard, and the tree that replaced oil in the explorer pane |
| `test-iterm-tune.sh` | the settings tables and Nerd Font face names |
| `test-vlc-default.sh` | the content-type table, and the LaunchServices parser against a recorded dump |
| `test-install-loop.sh` | `install_all_tools` reaches every catalog entry even when a tool drains stdin |
| `test-payload-pick.sh` | which file inside an archive gets installed, and whether a version query proves anything |

Ten of these exist because of a way asset selection, a write, or a run goes
wrong:

- an `arm64` host was handed a `linux_arm` build, so `select_asset` matches a
  full suffix before it falls back to substring containment
- the **last** asset of every release was dropped, because `tr` leaves no
  trailing newline on the final chunk and `read` discards it
- an install and a restore inside the same second produced the same backup
  filename, so the restore overwrote the only copy of the original rc file and
  then restored from it
- keyword matching prefers FFmpeg's `-gpl-shared` build, whose binary cannot run
  once the archive's `lib` directory is gone, and yazi's `gnu` build, which
  wants a newer glibc than Amazon Linux 2 has. Both are pinned by name in
  `github_asset_name`, and `test-preview-backends.sh` asserts that matching
  still picks the wrong one — that assertion is the reason the pin exists.
- the shell config file was chosen from the distribution alone, so an Amazon
  Linux cloud desktop had every setting written into `~/.zshrc` while its login
  shell was `/usr/bin/logbash`. Nothing was ever read, and sourcing that file
  by hand printed a zsh syntax error per `eval` line. `resolve_shell_rc` picks
  from the login shell now, and `test-shell-target.sh` pins the `logbash` row
  specifically — matching on the exact name instead of the suffix reopens it.
- the whole run stopped after the first tool it installed. `install_all_tools`
  fed the catalog in on stdin, and dnf reads stdin to ask about importing a
  repository GPG key, so that one install swallowed every remaining catalog
  line. The loop ended, and the summary said the run succeeded because each
  tool it had reached did pass. Six runs on one Amazon Linux 2023 box landed
  seven of the fifty-four tools, one more each time. The catalog goes in on
  descriptor 3 now, and `test-install-loop.sh` stubs a tool that drains stdin
  exactly as dnf does.
- a bash-completion script was installed as `~/.local/bin/fastfetch` and passed
  verification. The release tarball holds two files named `fastfetch` —
  `usr/bin/fastfetch` and one under `usr/share/bash-completion` — and
  `find_payload` took whichever `find` listed first, which is readdir order and
  so differs by machine. `command_works` then ran it: sourcing a completion
  script exits 0 in silence, and exit status was the whole test. `find_payload`
  prefers an executable now and `command_works` requires the version query to
  print something; `test-payload-pick.sh` covers both halves, because either
  one alone still lets a broken install through.
- the nvim wrapper used `--remote-wait`, which Neovim does not implement at all
  — it answers `E5600` — so the terminal pane got an error instead of a file
- `pending_count` counted `lazy-lock.json`, so `--freeze` refused to run in the
  one situation it exists for and no plugin could ever be added

- `join` in the video preview walked its parts with `ipairs` over a table that
  had holes in it. ffprobe leaves gaps — a file with a codec but no resolution
  gives `(nil, 'theora', nil)` — and `ipairs` stops at the first `nil`, so the
  line came out empty and a sparsely described file lost it entirely. It takes
  varargs counted with `select('#')` now, and `test-video-preview.sh` asserts
  the sparse case specifically; the full-metadata case passed throughout.

Each has an assertion here now. Keep them.

## Constraints

- **No network.** GitHub releases are local fixtures served over `file://`,
  with `github_api` overridden to return the release JSON. That exercises the
  real download, digest-check, extract and install path.
- **No root, no package installs.** The suites that drive `./bin/nanolander`
  end to end put no-op `apt-get`, `brew`, `dnf`, `yum` and `sudo` on PATH via
  `stub_tools`. Without that the run refreshes the package index for real:
  network, a sudo prompt, and minutes of CI time for a step none of these
  assertions are about. Everything past that point is the real code.

  One exception, on macOS only: `setup_homebrew` evaluates `brew shellenv`
  from the absolute path, which puts Homebrew's own bin directory ahead of the
  stubs, so the `brew update` that follows is the real one. It costs about
  twenty seconds and its failure is non-fatal, so it is left alone rather than
  worked around.
- **Nothing platform-specific is assumed.** The rc file a run writes depends on
  the *runner's own login shell*, so it is not something a suite can infer.
  `test-shell-config.sh` passes `--shell bash` and asserts against `.bashrc`;
  `test-shell-target.sh` fakes `current_login_shell` instead of using the real
  one. Both readings of this went wrong before: hard-coding `.bashrc` made the
  first suite assert against a file macOS never writes, and inferring it from
  `uname` was still wrong for a Linux box whose owner logs into zsh.
- **Nothing outside a throwaway `HOME`.** `temp_home` sets `TEST_HOME` and
  exports `HOME`; it does not print the path, because `H=$(temp_home)` would
  run the export in a subshell and leave the suite writing into the real home
  directory.
- **`HOME` alone is not isolation.** `temp_home` also points
  `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME`
  into it. `bin/nvim-land` targets `${XDG_CONFIG_HOME:-$HOME/.config}/nvim`
  and `bin/nanolander` puts its manifest and Linux fonts under
  `${XDG_DATA_HOME:-$HOME/.local/share}`, so on any machine that sets those —
  GitHub's Linux runners do — the suites wrote into the real configuration
  directory and asserted against an empty one. They passed locally and failed
  in CI, which is what CI is for.
- **No suite writes into the repository.** `test-nvim-land.sh` has to add and
  remove a `lazy-lock.json` to check that one changes `--apply` from `sync` to
  `restore`, so it copies the checkout — `bin/nvim-land` plus `share/nvim` —
  into the throwaway `HOME` and works on that. It used to write into
  `share/nvim` itself and delete the file on the way out, which took the
  lockfile the repository ships with it: `./tests/run.sh` quietly unpinned the
  plugin set, and the next `--apply` took each project's head.
- **A run with a tool missing has to survive `brew shellenv`.** `path_without`
  drops whole directories, so removing `nvim` from a Homebrew PATH also removes
  `brew` — and `setup_homebrew` puts `/opt/homebrew/bin` straight back, `nvim`
  included. `test-companions.sh` calls `install_nvim_config` through
  `NANOLANDER_LIB=1` instead of driving the whole script, which is the only way
  that branch is reachable on a Mac.
- **Any platform.** The suites run on Linux and macOS alike, and CI runs both.
- **Fast.** The whole set is about ten seconds. Keep it that way: a suite that
  takes minutes stops being run.

`NANOLANDER_LIB=1`, `ITERM_TUNE_LIB=1`, `NVIM_LAND_LIB=1` and
`VLC_DEFAULT_LIB=1` source the scripts without running them; that is how the
internals are reachable.

## What is not covered, and cannot be here

- **macOS**: Homebrew, `ensure_brew_tool`, and all of `iterm-tune`'s
  PlistBuddy writing. Only its data tables are tested.
- **LaunchServices**: `vlc-default`'s writing needs `duti` and a real
  LaunchServices to write into, and reading a real preference file needs
  PlistBuddy. The parser is split from the PlistBuddy call so the awk half can
  be fed a recorded dump on any platform — the brace-depth rule is the part
  that breaks, since each handler carries a nested dictionary with an
  `LSHandlerRoleAll` of its own that is always `-`.
- **Amazon Linux 2 and 2023**: yum and dnf.
- **The live GitHub API**: asset names and archive layouts are asserted
  against fixtures shaped like the real ones, not against the real releases.
- **Neovide on Linux**: it installs headless but cannot run without a desktop.
- **A real Neovim load**: layers 1 and 2 need an actual `nvim`.
- **The video thumbnail itself**: extracting and drawing it needs ffmpeg and a
  terminal to draw into. `test-video-preview.sh` covers the formatting against a
  fixture of ffprobe's output instead, so it needs neither a video file nor
  ffmpeg — which is what makes it runnable on a CI runner at all.
- **yazi's image previews**: they need a terminal that speaks one of the
  graphics protocols. `yazi --debug` on a real terminal is the only check, and
  a headless runner cannot be one.
- **`.tar.xz` extraction**: the FFmpeg and 7-Zip fixtures are `.tar.gz`, because
  neither `xz` nor `zip` is guaranteed on a runner. The pinned names for those
  two are asserted as data instead.

Say so when reporting rather than implying these were tested.
