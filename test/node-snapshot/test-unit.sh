#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/node-snapshot"
TMPDIR_STATE="$(mktemp -d)"
TMPDIR_OPTIONS="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_STATE}" "${TMPDIR_OPTIONS}"' EXIT
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

output="$("${BIN}" -h)"
_assert_match "${output}" "Usage: node-snapshot"
_pass "-h"

output="$("${BIN}" -V)"
_assert_match "${output}" "node-snapshot"
_pass "-V"

# Use the real dispatcher with blocked scripts so tests never invoke nvm or npm.
mkdir -p "${TMPDIR_OPTIONS}/bin" "${TMPDIR_OPTIONS}/libexec/node-snapshot/commands"
cp "${BIN}" "${TMPDIR_OPTIONS}/bin/node-snapshot"
export NODE_SNAPSHOT_TEST_CALLS="${TMPDIR_OPTIONS}/calls"
for subcommand in init snapshot upgrade migrate consolidate status; do
  cat > "${TMPDIR_OPTIONS}/libexec/node-snapshot/commands/${subcommand}.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "${NODE_SNAPSHOT_TEST_CALLS}"
echo "Unexpected command dispatch" >&2
exit 97
SH
  chmod +x "${TMPDIR_OPTIONS}/libexec/node-snapshot/commands/${subcommand}.sh"
done

: > "${NODE_SNAPSHOT_TEST_CALLS}"
command_exit=0
output="$("${TMPDIR_OPTIONS}/bin/node-snapshot" snapshot 2>&1)" || command_exit=$?
[[ "${command_exit}" -eq 97 && -s "${NODE_SNAPSHOT_TEST_CALLS}" ]] || _fail "Dispatch detector did not block snapshot"
_assert_match "${output}" "Unexpected command dispatch"

for subcommand in init snapshot upgrade migrate consolidate status; do
  for option in --help -h --version -V; do
    : > "${NODE_SNAPSHOT_TEST_CALLS}"
    command_exit=0
    output="$(NODE_SNAPSHOT_DIR="${TMPDIR_OPTIONS}/state" "${TMPDIR_OPTIONS}/bin/node-snapshot" "${subcommand}" "${option}" 2>&1)" || command_exit=$?
    [[ "${command_exit}" -eq 0 ]] || _fail "${subcommand} ${option}: expected exit 0, got ${command_exit}: ${output}"
    [[ ! -s "${NODE_SNAPSHOT_TEST_CALLS}" ]] || _fail "${subcommand} ${option}: dispatched a command"
    [[ ! -e "${TMPDIR_OPTIONS}/state" ]] || _fail "${subcommand} ${option}: created state"
    case "${option}" in
      --help|-h) _assert_match "${output}" "Usage: node-snapshot" ;;
      --version|-V) [[ "${output}" =~ ^node-snapshot\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || _fail "Invalid version output: ${output}" ;;
      *) _fail "Unexpected informational option: ${option}" ;;
    esac
    _pass "${subcommand} ${option}: exits without dispatch or state changes"
  done
done

for subcommand in init snapshot upgrade migrate consolidate status; do
  : > "${NODE_SNAPSHOT_TEST_CALLS}"
  command_exit=0
  output="$("${TMPDIR_OPTIONS}/bin/node-snapshot" "${subcommand}" --unknown 2>&1)" || command_exit=$?
  [[ "${command_exit}" -eq 1 ]] || _fail "${subcommand} --unknown: expected exit 1, got ${command_exit}"
  [[ ! -s "${NODE_SNAPSHOT_TEST_CALLS}" ]] || _fail "${subcommand} --unknown: dispatched a command"
  _assert_match "${output}" "unknown option"
  _pass "${subcommand}: rejects unknown options before dispatch"
done

for invocation in 'snapshot --force iron' 'snapshot iron --force' 'upgrade --check' 'upgrade iron' 'migrate iron jod' 'consolidate jod'; do
  read -r -a command_args <<< "${invocation}"
  : > "${NODE_SNAPSHOT_TEST_CALLS}"
  command_exit=0
  output="$("${TMPDIR_OPTIONS}/bin/node-snapshot" "${command_args[@]}" 2>&1)" || command_exit=$?
  [[ "${command_exit}" -eq 97 ]] || _fail "${invocation}: was not dispatched"
  command_calls="$(cat "${NODE_SNAPSHOT_TEST_CALLS}")"
  _assert_match "${command_calls}" "${command_args[0]}.sh ${invocation#* }"
  _pass "${invocation}: preserves supported arguments"
done

: > "${NODE_SNAPSHOT_TEST_CALLS}"
output="$("${TMPDIR_OPTIONS}/bin/node-snapshot" snapshot --force iron --help 2>&1)"
_assert_match "${output}" "Usage: node-snapshot"
[[ ! -s "${NODE_SNAPSHOT_TEST_CALLS}" ]] || _fail "snapshot --force iron --help: dispatched a command"
_pass "snapshot --force iron --help: exits before dispatch"

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
init_output="${TMPDIR_STATE}/init.zsh"
"${BIN}" init > "${init_output}" &
init_pid=$!
init_attempt=0
while kill -0 "${init_pid}" 2>/dev/null && [[ "${init_attempt}" -lt 20 ]]; do
    sleep 0.1
    init_attempt=$((init_attempt + 1))
done

if kill -0 "${init_pid}" 2>/dev/null; then
    kill "${init_pid}" 2>/dev/null || true
    wait "${init_pid}" 2>/dev/null || true
    _fail "init: does not exit promptly"
fi

if ! wait "${init_pid}"; then
    _fail "init: exits non-zero"
fi

output="$(< "${init_output}")"
_assert_match "${output}" "_node_snapshot_chpwd"
_assert_match "${output}" "add-zsh-hook"
_assert_match "${output}" "node-snapshot upgrade --check"
_pass "init: emits chpwd function and hook registration promptly"

echo ""; echo "All unit tests: PASS"
