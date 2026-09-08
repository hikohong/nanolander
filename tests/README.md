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
| `test-nerd-font.sh` | family selection, monospaced-only rule, manifest |
| `test-shell-config.sh` | backups, `--restore-shell`, `--uninstall` |
| `test-uninstall.sh` | manifest path guard across both font directories |
| `test-nvim-land.sh` | `report` / `--apply` / `--restore` |
| `test-iterm-tune.sh` | the settings tables and Nerd Font face names |

Three of these exist because of bugs that shipped:

- an `arm64` host was handed a `linux_arm` build, so `select_asset` matches a
  full suffix before it falls back to substring containment
- the **last** asset of every release was dropped, because `tr` leaves no
  trailing newline on the final chunk and `read` discards it
- an install and a restore inside the same second produced the same backup
  filename, so the restore overwrote the only copy of the original rc file and
  then restored from it

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
- **One suite writes into the repository.** `test-nvim-land.sh` puts a
  `lazy-lock.json` in `share/nvim` to check that a lockfile changes `--apply`
  from `sync` to `restore`. A trap removes it however the suite ends, and it
  asserts there is no stale one to start from.
- **Any platform.** The suites run on Linux and macOS alike, and CI runs both.
- **Fast.** The whole set is about ten seconds. Keep it that way: a suite that
  takes minutes stops being run.

`NANOLANDER_LIB=1`, `ITERM_TUNE_LIB=1` and `NVIM_LAND_LIB=1` source the
scripts without running them; that is how the internals are reachable.

## What is not covered, and cannot be here

- **macOS**: Homebrew, `ensure_brew_tool`, and all of `iterm-tune`'s
  PlistBuddy writing. Only its data tables are tested.
- **Amazon Linux 2 and 2023**: yum and dnf.
- **The live GitHub API**: asset names and archive layouts are asserted
  against fixtures shaped like the real ones, not against the real releases.
- **Neovide on Linux**: it installs headless but cannot run without a desktop.
- **A real Neovim load**: layers 1 and 2 need an actual `nvim`.

Say so when reporting rather than implying these were tested.
