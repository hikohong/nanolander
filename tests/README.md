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
- **No root, no package installs.** Anything that writes writes into a
  throwaway `HOME` from `temp_home`.
- **Any platform.** The suites run on Linux and macOS alike.

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
