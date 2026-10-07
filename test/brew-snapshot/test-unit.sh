#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/brew-snapshot"
TMPDIR_STATE="$(mktemp -d)"
TMPDIR_OPTIONS="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_STATE}" "${TMPDIR_OPTIONS}"' EXIT
export BREW_SNAPSHOT_DIR="${TMPDIR_STATE}"
export HOMEBREW_NO_AUTO_UPDATE=1

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

output="$("${BIN}" -h)"
_assert_match "${output}" "Usage: brew-snapshot"
_pass "-h"

output="$("${BIN}" -V)"
_assert_match "${output}" "brew-snapshot"
_pass "-V"

# Copy the real dispatcher with blocked command scripts to keep setup tests safe.
mkdir -p "${TMPDIR_OPTIONS}/bin" "${TMPDIR_OPTIONS}/libexec/brew-snapshot/commands"
cp "${BIN}" "${TMPDIR_OPTIONS}/bin/brew-snapshot"
export BREW_SNAPSHOT_TEST_CALLS="${TMPDIR_OPTIONS}/calls"
for subcommand in snapshot restore status setup; do
  cat > "${TMPDIR_OPTIONS}/libexec/brew-snapshot/commands/${subcommand}.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "${BREW_SNAPSHOT_TEST_CALLS}"
echo "Unexpected command dispatch" >&2
exit 97
SH
  chmod +x "${TMPDIR_OPTIONS}/libexec/brew-snapshot/commands/${subcommand}.sh"
done

# Prove the dispatch detector sees a normal command before trusting empty logs.
: > "${BREW_SNAPSHOT_TEST_CALLS}"
command_exit=0
output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" snapshot 2>&1)" || command_exit=$?
[[ "${command_exit}" -eq 97 && -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "Dispatch detector did not block snapshot"
_assert_match "${output}" "Unexpected command dispatch"

: > "${BREW_SNAPSHOT_TEST_CALLS}"
command_exit=0
output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" snapshot --greedy 2>&1)" || command_exit=$?
[[ "${command_exit}" -eq 97 ]] || _fail "snapshot --greedy: was not dispatched"
command_calls="$(cat "${BREW_SNAPSHOT_TEST_CALLS}")"
_assert_match "${command_calls}" "snapshot.sh --greedy"
_pass "snapshot --greedy: preserves the supported option"

for subcommand in snapshot restore status setup; do
  for option in --help -h --version -V; do
    : > "${BREW_SNAPSHOT_TEST_CALLS}"
    command_exit=0
    output="$(BREW_SNAPSHOT_DIR="${TMPDIR_OPTIONS}/state" "${TMPDIR_OPTIONS}/bin/brew-snapshot" "${subcommand}" "${option}" 2>&1)" || command_exit=$?
    [[ "${command_exit}" -eq 0 ]] || _fail "${subcommand} ${option}: expected exit 0, got ${command_exit}: ${output}"
    [[ ! -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "${subcommand} ${option}: dispatched a command"
    [[ ! -e "${TMPDIR_OPTIONS}/state" ]] || _fail "${subcommand} ${option}: created state"
    case "${option}" in
      --help|-h) _assert_match "${output}" "Usage: brew-snapshot" ;;
      --version|-V) [[ "${output}" =~ ^brew-snapshot\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || _fail "Invalid version output: ${output}" ;;
      *) _fail "Unexpected informational option: ${option}" ;;
    esac
    _pass "${subcommand} ${option}: exits without dispatch or state changes"
  done
done

: > "${BREW_SNAPSHOT_TEST_CALLS}"
output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" snapshot --greedy --help 2>&1)"
_assert_match "${output}" "Usage: brew-snapshot"
[[ ! -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "snapshot --greedy --help: dispatched a command"
_pass "snapshot --greedy --help: exits before dispatch"

for subcommand in snapshot restore status setup; do
  : > "${BREW_SNAPSHOT_TEST_CALLS}"
  command_exit=0
  output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" "${subcommand}" --unknown 2>&1)" || command_exit=$?
  [[ "${command_exit}" -eq 1 ]] || _fail "${subcommand} --unknown: expected exit 1, got ${command_exit}"
  [[ ! -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "${subcommand} --unknown: dispatched a command"
  _assert_match "${output}" "unknown option"
  _pass "${subcommand}: rejects unknown options before dispatch"
done

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
