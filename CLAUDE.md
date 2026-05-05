# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A Homebrew tap providing two CLI tools distributed as shell scripts:

- **`brew-snapshot`** — snapshot and restore Homebrew environments
- **`node-snapshot`** — manage nvm LTS versions and global npm packages

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

Each formula rewrites the `LIBEXEC_DIR` literal in its entry-point binary at install time to use the Homebrew prefix. If the LIBEXEC_DIR detection logic in a `bin/` script changes, update the corresponding `inreplace` regex in the formula.

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

Pushing a semver tag (e.g. `v0.4.0`) triggers `.github/workflows/homebrew-releaser.yml`, which:

1. Creates the GitHub release with auto-generated notes
2. **Automatically** updates `url`, `sha256`, and `version` in `Formula/brew-snapshot.rb`

`Formula/node-snapshot.rb` is **not** updated by the workflow — update `url`, `sha256`, and `version` there manually before tagging, or push a follow-up commit.
