# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A Homebrew tap providing the `brew-snapshot` CLI tool. Distributes shell scripts
via `brew install`; no build system or tests beyond the formula `test do` block.

## Architecture

`bin/brew-snapshot` dispatches to `libexec/commands/*.sh` via `exec`. Each subcommand
script is self-contained and reads `$BREW_SNAPSHOT_DIR` for the state path.

The formula's `inreplace` step rewrites the LIBEXEC_DIR path at install time so the
dispatch works correctly from the Homebrew prefix.

## State Directory

`~/.local/share/brew-snapshot/` — plain data folder, never a git repo.
All files are regeneratable by running `brew-snapshot snapshot`.

## Adding a Subcommand

1. Create `libexec/commands/<name>.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`
2. Add a `<name>)` case to `bin/brew-snapshot`
3. Add a line to the help text in `bin/brew-snapshot`

## Formula Maintenance

`url` and `sha256` in `Formula/brew-snapshot.rb` are filled after each GitHub release tag.
The `inreplace` block must be updated if the LIBEXEC_DIR detection logic in `bin/brew-snapshot` changes.
