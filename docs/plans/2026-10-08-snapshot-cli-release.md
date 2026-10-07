# Snapshot CLI Release Plan

## Direction and Ownership

The operator approved common CLI handling, current-state-only snapshot semantics, a new release, and local installation after merge.
The root agent owns all edits, verification, staging, commits, and publication in the existing workspace.

## Execution

1. Reuse the completed CLI implementation and regression tests in both entry points and unit suites.
2. Repair embedded version installation in both formulas and strengthen their version assertions.
3. Verify both real installation methods in temporary prefixes, both unit suites, ShellCheck, Trunk, and the complete diff.
4. Commit CLI behavior and packaging fixes separately, then push and open one PR against `main`.
5. Observe current-head CI and hosted review, repair confirmed findings within the approved scope, and request operator merge.
6. Verify the merge, create `v0.6.0` on the merged commit, and observe the shared release workflow.
7. Verify both published formulas and checksums, install both tools locally, and check installed versions and command behavior.

## Acceptance Evidence

- Regression tests failed before the CLI changes because help dispatched commands and snapshot called update.
- Informational options must never dispatch a subcommand or create state.
- Real snapshot tests must record only metadata Homebrew calls.
- Upgrade tests must check update, upgrade, and snapshot order, including failure preservation.
- Installation fixtures must compare executable `--version` output with the formula version.
- Local installation must report `0.6.0` for both formulae and both CLIs.

## Boundaries

Merge remains with the operator.
Branch cleanup and memory recording were not requested.
The local install stage resumes after remote merge verification.
