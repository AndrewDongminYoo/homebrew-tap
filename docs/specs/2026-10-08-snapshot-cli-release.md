# Snapshot CLI Release

## Problem

Subcommand help and version options can execute commands instead of returning information.
The two snapshot tools also use different semantics for `snapshot`: Homebrew upgrades packages first, while Node records current state.
The release workflow updates embedded versions after tagging, so tagged scripts can report an older version than their installed formula.

## Approved Behavior

- Both tools accept `--help`, `-h`, `--version`, and `-V` at the root and on every subcommand without dispatching a command.
- Unknown command options fail before execution.
- `snapshot` records current installed state without updating or upgrading packages.
- `brew-snapshot upgrade [--greedy]` updates Homebrew, upgrades packages, then saves a snapshot.
- A failed Homebrew update or upgrade preserves the previous snapshot and returns the failure status.
- Existing Node aliases, `--force`, and `--check` remain supported.
- Formula installation sets each embedded CLI version to its formula version.

## Release

Publish `v0.6.0` after the PR merges, using the existing shared tag workflow.
Install both released tools locally and verify their reported versions and informational options.
The operator retains the merge decision.

## Verification

Run both unit suites, ShellCheck, Trunk, and a temporary installation fixture that executes both real formula installation methods.
Verify hosted checks and current-head reviews before requesting merge.
After release, inspect the tag workflow, formula URL and checksum updates, and installed CLI behavior.

## Scope Limits

Exact package-version restoration, automatic local tap patch restoration, and atomic metadata snapshot publication remain outside this change.
No new dependencies are required.
