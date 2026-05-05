#!/usr/bin/env bash
# Requires nvm installed and lts/iron available.
# Run manually: bash test/node-snapshot/test-integration.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/node-snapshot"
TMPDIR_STATE="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_STATE}"' EXIT
export NODE_SNAPSHOT_DIR="${TMPDIR_STATE}"

_pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
_fail() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }
_assert_match()  { [[ "$1" == *"$2"* ]] || _fail "Expected '$2' in: $1"; }
_assert_file()   { [[ -f "$1" ]] || _fail "File not found: $1"; }
_assert_jq()     { jq -e "$2" "$1" >/dev/null 2>&1 || _fail "jq '$2' failed on $1"; }

# Pre-condition: write minimal config tracking iron only
mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
    > "${TMPDIR_STATE}/config.json"

# ── snapshot ─────────────────────────────────────────────────────────────────
output="$("${BIN}" snapshot iron 2>&1)"
_assert_match "${output}" "✓ Snapshot complete"
_pass "snapshot: exits successfully"

lock="${TMPDIR_STATE}/lts-iron.lock.json"
_assert_file "${lock}"
_pass "snapshot: creates lock file"

_assert_jq "${lock}" '.lts_alias == "iron"'
_pass "snapshot: lock has lts_alias"

_assert_jq "${lock}" '.node_version | test("^[0-9]")'
_pass "snapshot: lock has node_version"

_assert_jq "${lock}" '.packages | type == "object"'
_pass "snapshot: lock has packages object"

# npm itself must not appear in packages
npm_in_lock="$(jq -r '.packages | has("npm")' "${lock}")"
[[ "${npm_in_lock}" == "false" ]] || _fail "npm must not appear in lock packages"
_pass "snapshot: npm filtered from packages"

# corepack must not appear in packages
corepack_in_lock="$(jq -r '.packages | has("corepack")' "${lock}")"
[[ "${corepack_in_lock}" == "false" ]] || _fail "corepack must not appear in lock packages"
_pass "snapshot: corepack filtered from packages"

echo ""; echo "Snapshot integration tests: PASS"
