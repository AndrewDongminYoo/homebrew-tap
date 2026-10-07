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

# Exercise real state collection with a fake Homebrew boundary.
mkdir -p "${TMPDIR_OPTIONS}/mock-bin"
cat > "${TMPDIR_OPTIONS}/mock-bin/brew" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BREW_SNAPSHOT_TEST_CALLS}"
case "$1" in
  update) exit "${BREW_SNAPSHOT_TEST_UPDATE_EXIT:-0}" ;;
  upgrade) exit "${BREW_SNAPSHOT_TEST_UPGRADE_EXIT:-0}" ;;
  bundle)
    for arg in "$@"; do
      case "${arg}" in
        --file=*) printf 'brew "git"\n' > "${arg#--file=}" ;;
        *) ;;
      esac
    done
    ;;
  info) printf '{"formulae":[],"casks":[]}\n' ;;
  deps|tap) ;;
  *) echo "Unexpected Homebrew command: $*" >&2; exit 98 ;;
esac
SH
chmod +x "${TMPDIR_OPTIONS}/mock-bin/brew"
export BREW_SNAPSHOT_TEST_CALLS="${TMPDIR_OPTIONS}/brew-calls"
(
  export PATH="${TMPDIR_OPTIONS}/mock-bin:/usr/bin:/bin"
  export BREW_SNAPSHOT_DIR="${TMPDIR_OPTIONS}/snapshot-state"
  : > "${BREW_SNAPSHOT_TEST_CALLS}"
  output="$("${BIN}" snapshot 2>&1)"
  first_call="$(head -n 1 "${BREW_SNAPSHOT_TEST_CALLS}")"
  [[ "${first_call}" == "bundle dump --file=${BREW_SNAPSHOT_DIR}/Brewfile --force" ]] || _fail "snapshot must start with state collection, got: ${first_call}"
  call_count="$(wc -l < "${BREW_SNAPSHOT_TEST_CALLS}")"
  [[ "${call_count}" -eq 4 ]] || _fail "snapshot invoked unexpected Homebrew commands"
  [[ -f "${BREW_SNAPSHOT_DIR}/last_snapshot_utc" ]] || _fail "snapshot did not finish saving state"
  _pass "snapshot: saves state without update or upgrade"

  for option in '' --greedy; do
    : > "${BREW_SNAPSHOT_TEST_CALLS}"
    command_args=(upgrade)
    [[ -n "${option}" ]] && command_args+=("${option}")
    output="$("${BIN}" "${command_args[@]}" 2>&1)" || _fail "upgrade ${option}: ${output}"
    expected_upgrade="upgrade${option:+ ${option}}"
    update_call="$(sed -n '1p' "${BREW_SNAPSHOT_TEST_CALLS}")"
    upgrade_call="$(sed -n '2p' "${BREW_SNAPSHOT_TEST_CALLS}")"
    call_count="$(wc -l < "${BREW_SNAPSHOT_TEST_CALLS}")"
    [[ "${update_call}" == update ]] || _fail "upgrade must update first"
    [[ "${upgrade_call}" == "${expected_upgrade}" ]] || _fail "upgrade did not preserve ${option}"
    [[ "${call_count}" -eq 6 ]] || _fail "upgrade did not save state after upgrading"
    _assert_match "${output}" "Snapshot complete"
    _pass "upgrade ${option}: updates, upgrades, then saves state"
  done

  for failed_step in update upgrade; do
    : > "${BREW_SNAPSHOT_TEST_CALLS}"
    printf 'old manifest\n' > "${BREW_SNAPSHOT_DIR}/Brewfile"
    command_exit=0
    if [[ "${failed_step}" == update ]]; then
      output="$(BREW_SNAPSHOT_TEST_UPDATE_EXIT=17 "${BIN}" upgrade 2>&1)" || command_exit=$?
      expected_calls=1
    else
      output="$(BREW_SNAPSHOT_TEST_UPGRADE_EXIT=17 "${BIN}" upgrade --greedy 2>&1)" || command_exit=$?
      expected_calls=2
    fi
    [[ "${command_exit}" -eq 17 ]] || _fail "${failed_step} failure: expected exit 17, got ${command_exit}"
    call_count="$(wc -l < "${BREW_SNAPSHOT_TEST_CALLS}")"
    saved_manifest="$(cat "${BREW_SNAPSHOT_DIR}/Brewfile")"
    [[ "${call_count}" -eq "${expected_calls}" ]] || _fail "${failed_step} failure: saved state after failure"
    [[ "${saved_manifest}" == 'old manifest' ]] || _fail "${failed_step} failure: replaced the previous snapshot"
    _pass "upgrade: ${failed_step} failure preserves the previous snapshot"
  done
)

# Copy the real dispatcher with blocked command scripts to keep setup tests safe.
mkdir -p "${TMPDIR_OPTIONS}/bin" "${TMPDIR_OPTIONS}/libexec/brew-snapshot/commands"
cp "${BIN}" "${TMPDIR_OPTIONS}/bin/brew-snapshot"
export BREW_SNAPSHOT_TEST_CALLS="${TMPDIR_OPTIONS}/calls"
for subcommand in snapshot upgrade restore status setup; do
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
output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" upgrade --greedy 2>&1)" || command_exit=$?
[[ "${command_exit}" -eq 97 ]] || _fail "upgrade --greedy: was not dispatched"
command_calls="$(cat "${BREW_SNAPSHOT_TEST_CALLS}")"
_assert_match "${command_calls}" "upgrade.sh --greedy"
_pass "upgrade --greedy: preserves the supported option"

for subcommand in snapshot upgrade restore status setup; do
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
output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" upgrade --greedy --help 2>&1)"
_assert_match "${output}" "Usage: brew-snapshot"
[[ ! -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "upgrade --greedy --help: dispatched a command"
_pass "upgrade --greedy --help: exits before dispatch"

for subcommand in snapshot upgrade restore status setup; do
  : > "${BREW_SNAPSHOT_TEST_CALLS}"
  command_exit=0
  output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" "${subcommand}" --unknown 2>&1)" || command_exit=$?
  [[ "${command_exit}" -eq 1 ]] || _fail "${subcommand} --unknown: expected exit 1, got ${command_exit}"
  [[ ! -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "${subcommand} --unknown: dispatched a command"
  _assert_match "${output}" "unknown option"
  _pass "${subcommand}: rejects unknown options before dispatch"
done

: > "${BREW_SNAPSHOT_TEST_CALLS}"
command_exit=0
output="$("${TMPDIR_OPTIONS}/bin/brew-snapshot" snapshot --greedy 2>&1)" || command_exit=$?
[[ "${command_exit}" -eq 1 && ! -s "${BREW_SNAPSHOT_TEST_CALLS}" ]] || _fail "snapshot --greedy: must reject the upgrade option without dispatch"
_pass "snapshot --greedy: rejects the upgrade option"

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
