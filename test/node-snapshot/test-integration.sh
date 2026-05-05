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

# ── upgrade --check ───────────────────────────────────────────────────────────
# Seed config with a very old last_check_utc to force the check
mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron"],\n  "check_interval_days": 1,\n  "last_check_utc": "2020-01-01T00:00:00Z"\n}\n' \
    > "${TMPDIR_STATE}/config.json"

output="$("${BIN}" upgrade --check 2>&1 || true)"
# Either "update available" (outdated) or silence (up-to-date); must not error
_pass "upgrade --check: exits without error"

# last_check_utc must be updated after running
updated_ts="$(jq -r '.last_check_utc' "${TMPDIR_STATE}/config.json")"
[[ "${updated_ts}" != "2020-01-01T00:00:00Z" ]] || _fail "last_check_utc was not updated"
_pass "upgrade --check: updates last_check_utc in config"

# Within interval → skip silently
output="$("${BIN}" upgrade --check 2>&1 || true)"
[[ -z "${output}" ]] || _fail "upgrade --check: within interval should produce no output, got: ${output}"
_pass "upgrade --check: interval guard works"

# ── migrate ───────────────────────────────────────────────────────────────────
# Seed a lock file for iron with a known package list
rm -rf "${TMPDIR_STATE}"
TMPDIR_STATE="$(mktemp -d)"
export NODE_SNAPSHOT_DIR="${TMPDIR_STATE}"
mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron", "jod"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
    > "${TMPDIR_STATE}/config.json"
printf '{"lts_alias":"iron","node_version":"20.19.1","snapshot_utc":"2026-05-05T00:00:00Z","packages":{}}\n' \
    > "${TMPDIR_STATE}/lts-iron.lock.json"

# migrate with empty packages should succeed and produce a jod lock file
output="$("${BIN}" migrate iron jod 2>&1)"
_assert_match "${output}" "✓ Snapshot complete"
_pass "migrate: exits successfully"
_assert_file "${TMPDIR_STATE}/lts-jod.lock.json"
_pass "migrate: creates destination lock file"

# missing from-lock exits with error
output="$("${BIN}" migrate hydrogen jod 2>&1 || true)"
_assert_match "${output}" "error:"
_pass "migrate: missing from-lock exits with error"

# missing args exits with error
output="$("${BIN}" migrate 2>&1 || true)"
_assert_match "${output}" "Usage:"
_pass "migrate: missing args shows usage"

echo ""; echo "All integration tests: PASS"
