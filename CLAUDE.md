# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A Homebrew tap.
`README.md` lists every formula the tap serves; this file covers only the ones whose source lives here.

The snapshot formulae package shell scripts built in this repository:

- **`brew-snapshot`** — snapshot and restore Homebrew environments
- **`node-snapshot`** — manage nvm LTS versions and global npm packages

`Formula/imgen.rb`, `Formula/maintainer.rb`, and `Formula/histfix.rb` are packaging-only.
`imgen` and `maintainer` point at prebuilt Apple Silicon binaries released from their own upstream repositories.
`histfix` installs a zsh plugin and Python script from its upstream source archive.
Nothing under `bin/`, `libexec/`, or `test/` belongs to these packaging-only formulae.

## Common Commands

```bash
# Lint all scripts (zero warnings required before committing)
shellcheck bin/brew-snapshot bin/node-snapshot libexec/brew-snapshot/commands/*.sh libexec/node-snapshot/commands/*.sh

# Run unit tests
bash test/brew-snapshot/test-unit.sh
bash test/node-snapshot/test-unit.sh

# Run integration tests (require brew / nvm installed)
bash test/brew-snapshot/test-integration.sh
bash test/node-snapshot/test-integration.sh

# Run with Trunk (covers shellcheck, markdownlint, yamllint, actionlint)
trunk check
trunk fmt
```

## Architecture

Both tools share the same dispatch pattern: `bin/<tool>` reads `$1` and `exec`s into the corresponding subcommand script.

### brew-snapshot

- Dispatcher: `bin/brew-snapshot` → `libexec/brew-snapshot/commands/<cmd>.sh`
- State env var: `$BREW_SNAPSHOT_DIR` (default `~/.local/share/brew-snapshot/`)
- Formula: `Formula/brew-snapshot.rb`

### node-snapshot

- Dispatcher: `bin/node-snapshot` → `libexec/node-snapshot/commands/<cmd>.sh`
- State env var: `$NODE_SNAPSHOT_DIR` (default `~/.local/share/node-snapshot/`)
- Config file: `$NODE_SNAPSHOT_DIR/config.json` — JSON with `tracked`, `check_interval_days`, `last_check_utc`
- Formula: `Formula/node-snapshot.rb` (depends on `jq`)

### Formula `inreplace`

Both snapshot formulae rewrite the `LIBEXEC_DIR` literal in their entry-point scripts at install time to use the Homebrew prefix.
If the LIBEXEC_DIR detection logic in a `bin/` script changes, update the corresponding `inreplace` regex in the formula.

## Adding a Subcommand

**To brew-snapshot:**

1. Create `libexec/brew-snapshot/commands/<name>.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`
2. Add a `<name>)` case to `bin/brew-snapshot`
3. Add a help line in `bin/brew-snapshot`
4. Add a test case in `test/brew-snapshot/test-unit.sh`

**To node-snapshot:**

1. Create `libexec/node-snapshot/commands/<name>.sh`
2. Add a `<name>)` case to `bin/node-snapshot`
3. Add a help line in `bin/node-snapshot`
4. Add a test case in `test/node-snapshot/test-unit.sh`

## Release Process

Pushing a semver tag (e.g. `v0.5.0`) triggers `.github/workflows/homebrew-releaser.yml`, which:

1. Skips the release unless the pushed tag is strictly higher than the latest GitHub release (`check-semver` job)
2. Creates the GitHub release with auto-generated notes
3. **Automatically** updates `url`, `sha256`, and `version` in **both** `Formula/brew-snapshot.rb` and `Formula/node-snapshot.rb`, and bumps the `BREW_SNAPSHOT_VERSION` / `NODE_SNAPSHOT_VERSION` constants in `bin/brew-snapshot` / `bin/node-snapshot` to match, then commits and pushes the bump to `main`

Both formulas share one tarball URL and `sha256` (the repo archive), so the workflow keeps the formulas and the `bin/` `--version` output in lockstep: no manual version edits are needed before tagging.

`Formula/imgen.rb`, `Formula/maintainer.rb`, and `Formula/histfix.rb` are outside this workflow.
Their versions track releases in their own upstream repositories, so each bump is a hand-written commit editing `url`, `sha256`, and any explicit `version` in that one file.

## Offline Secret Reader

Run `python3 -B .trunk/configs/tests/test_trufflehog_to_sarif.py` for the separate standard-library tooling regressions.
CI runs this exact file independently of the existing application checks.
The configured filesystem scanner uses `--no-verification --no-update`; its local SARIF reader retains decoded findings without exposing secret values.
Run `trunk check --all --no-fix --jobs=2` for the full configured quality scan.
Other scanners may use advisory or tool metadata services; the filesystem flags do not make the entire Trunk run network-free.
