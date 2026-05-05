#!/usr/bin/env bash
# Requires Homebrew installed.
# Run manually: bash test/brew-snapshot/test-integration.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/brew-snapshot"
TMPDIR_STATE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_STATE}"' EXIT
export BREW_SNAPSHOT_DIR="${TMPDIR_STATE}"

_pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
_fail() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }
_assert_match() { [[ "$1" == *"$2"* ]] || _fail "Expected '$2' in: $1"; }
_assert_file()  { [[ -f "$1" ]] || _fail "File not found: $1"; }

# Pre-condition: brew must be available
command -v brew >/dev/null 2>&1 || { echo "error: brew not found — skipping integration tests"; exit 0; }

# ── restore: empty Brewfile ───────────────────────────────────────────────────
mkdir -p "${TMPDIR_STATE}"
printf "" > "${TMPDIR_STATE}/Brewfile"
output="$("${BIN}" restore 2>&1)"
_assert_match "${output}" "Installing from"
_pass "restore: empty Brewfile → brew bundle runs without error"

# ── restore: missing Brewfile ─────────────────────────────────────────────────
rm -f "${TMPDIR_STATE}/Brewfile"
output="$("${BIN}" restore 2>&1 || true)"
_assert_match "${output}" "No Brewfile found"
_pass "restore: missing Brewfile → error message"

echo ""; echo "All integration tests: PASS"
