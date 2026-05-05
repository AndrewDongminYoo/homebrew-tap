#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/node-snapshot"
TMPDIR_STATE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_STATE}"' EXIT
export NODE_SNAPSHOT_DIR="${TMPDIR_STATE}"

_pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
_fail() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }
_assert_match() { [[ "$1" == *"$2"* ]] || _fail "Expected '$2' in output: $1"; }

# ── dispatcher ──────────────────────────────────────────────────────────────
output="$("${BIN}" help)"
_assert_match "${output}" "Usage: node-snapshot"
_pass "help"

output="$("${BIN}" --help)"
_assert_match "${output}" "Usage: node-snapshot"
_pass "--help"

output="$("${BIN}" --version)"
_assert_match "${output}" "node-snapshot"
_pass "--version"

output="$("${BIN}" bogus 2>&1 || true)"
_assert_match "${output}" "unknown command"
_pass "unknown command exits 1"

output="$("${BIN}" help)"
_assert_match "${output}" "consolidate"
_pass "help: consolidate command listed"

# ── status ───────────────────────────────────────────────────────────────────
output="$("${BIN}" status)"
_assert_match "${output}" "No snapshot found"
_pass "status: no config → guidance message"

mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
    > "${TMPDIR_STATE}/config.json"
output="$("${BIN}" status)"
_assert_match "${output}" "State directory:"
_assert_match "${output}" "iron"
_pass "status: config present → shows alias"

# ── init ─────────────────────────────────────────────────────────────────────
output="$("${BIN}" init)"
_assert_match "${output}" "_node_snapshot_chpwd"
_assert_match "${output}" "add-zsh-hook"
_assert_match "${output}" "node-snapshot upgrade --check"
_pass "init: emits chpwd function and hook registration"

echo ""; echo "All unit tests: PASS"
