#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/brew-snapshot"
TMPDIR_STATE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_STATE}"' EXIT
export BREW_SNAPSHOT_DIR="${TMPDIR_STATE}"

_pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
_fail() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }
_assert_match() { [[ "$1" == *"$2"* ]] || _fail "Expected '$2' in output: $1"; }

# ── dispatcher ───────────────────────────────────────────────────────────────
output="$("${BIN}" help)"
_assert_match "${output}" "Usage: brew-snapshot"
_pass "help"

output="$("${BIN}" --help)"
_assert_match "${output}" "Usage: brew-snapshot"
_pass "--help"

output="$("${BIN}" --version)"
_assert_match "${output}" "brew-snapshot"
_pass "--version"

output="$("${BIN}" bogus 2>&1 || true)"
_assert_match "${output}" "unknown command"
_pass "unknown command exits 1"

# ── status ───────────────────────────────────────────────────────────────────
rm -rf "${TMPDIR_STATE}"
output="$("${BIN}" status)"
_assert_match "${output}" "No snapshot found"
_pass "status: no state dir → guidance message"

mkdir -p "${TMPDIR_STATE}"
printf "2024-01-01T00:00:00Z\n" > "${TMPDIR_STATE}/last_snapshot_utc"
printf 'brew "git"\nbrew "curl"\n' > "${TMPDIR_STATE}/Brewfile"
printf "homebrew/cask\n" > "${TMPDIR_STATE}/Brewfile.taps"

output="$("${BIN}" status)"
_assert_match "${output}" "2024-01-01T00:00:00Z"
_assert_match "${output}" "Formulae:"
_assert_match "${output}" "Taps:"
_pass "status: mock state → shows snapshot info"

# ── restore ──────────────────────────────────────────────────────────────────
rm -f "${TMPDIR_STATE}/Brewfile"
output="$("${BIN}" restore 2>&1 || true)"
_assert_match "${output}" "No Brewfile found"
_pass "restore: no Brewfile → exits with error"

printf "" > "${TMPDIR_STATE}/Brewfile"
output="$("${BIN}" restore 2>&1)"
_assert_match "${output}" "Installing from"
_pass "restore: Brewfile present → dispatches to brew bundle"

echo ""; echo "All unit tests: PASS"
