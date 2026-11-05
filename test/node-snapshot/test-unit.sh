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

command -v zsh >/dev/null 2>&1 || _fail "init: zsh is required for the init scenarios"
if ! zsh -f "${SCRIPT_DIR}/test-init.zsh" > "${TMPDIR_STATE}/init-scenarios.log" 2>&1; then
    cat "${TMPDIR_STATE}/init-scenarios.log"
    _fail "init: zsh scenarios"
fi
_pass "init: zsh scenarios (version switch, prompts, package managers)"

# ── local package restoration (isolated nvm/npm) ──────────────────────────────
fixture="${TMPDIR_OPTIONS}/local-packages"
mkdir -p "${fixture}/nvm/versions/node/v20.1.0/lib/node_modules/@local" \
    "${fixture}/nvm/versions/node/v20.2.0/lib/node_modules" \
    "${fixture}/nvm/alias/lts" "${fixture}/local package" "${fixture}/state"
printf '{"name":"@local/agent","version":"0.2.0"}\n' > "${fixture}/local package/package.json"
ln -s "${fixture}/local package" "${fixture}/nvm/versions/node/v20.1.0/lib/node_modules/@local/agent"
printf 'v20.2.0\n' > "${fixture}/nvm/alias/lts/iron"
cat > "${fixture}/nvm/nvm.sh" <<'SH'
nvm() {
    case "$1" in
        use) export MOCK_VERSION=20.2.0 ;;
        version|version-remote) echo v20.2.0 ;;
        install|uninstall) return 0 ;;
        *) return 91 ;;
    esac
}
node() { echo "v${MOCK_VERSION:-20.1.0}"; }
npm() {
    local modules="${NVM_DIR}/versions/node/v${MOCK_VERSION:-20.1.0}/lib/node_modules"
    case "$1" in
        root) echo "${modules}" ;;
        list)
            if [[ -L "${modules}/@local/agent" ]]; then
                printf '{"dependencies":{"@local/agent":{"version":"0.2.0","resolved":"file:relative/path"},"registry-pkg":{"version":"1.2.3"},"npm":{"version":"10.0.0"}}}\n'
            else
                printf '{"dependencies":{"registry-pkg":{"version":"1.2.3"}}}\n'
            fi
            ;;
        install)
            printf '%s\n' "$3" >> "${NVM_DIR}/calls"
            case "$3" in
                "file:${NVM_DIR}/../local package")
                    mkdir -p "${modules}/@local"
                    ln -sfn "${NVM_DIR}/../local package" "${modules}/@local/agent"
                    ;;
                "file:"*)
                    [[ "$3" == "file:$(cd "${NVM_DIR}/../local package" && pwd -P)" ]] || return 92
                    mkdir -p "${modules}/@local"
                    ln -sfn "${3#file:}" "${modules}/@local/agent"
                    ;;
                registry-pkg@1.2.3) ;;
                *) echo "Unexpected registry install: $3" >&2; return 93 ;;
            esac
            ;;
        *) return 94 ;;
    esac
}
SH
local_source="file:$(cd "${fixture}/local package" && pwd -P)"
seed_legacy_lock() {
    printf '{"node_version":"20.1.0","packages":{"@local/agent":"0.2.0","registry-pkg":"1.2.3"}}\n' > "${fixture}/state/lts-iron.lock.json"
    : > "${fixture}/nvm/calls"
}
seed_legacy_lock
output="$(NVM_DIR="${fixture}/nvm" NODE_SNAPSHOT_DIR="${fixture}/state" "${BIN}" upgrade iron 2>&1)" || _fail "upgrade must recover a local path from a legacy lock: ${output}"
install_calls="$(< "${fixture}/nvm/calls")"
[[ "${install_calls}" == "${local_source}"$'\nregistry-pkg@1.2.3' ]] || _fail "upgrade must use the local path and pinned registry version"
jq -e --arg source "${local_source}" '.packages["@local/agent"] == $source and .packages["registry-pkg"] == "1.2.3" and (.packages | has("npm") | not)' "${fixture}/state/lts-iron.lock.json" >/dev/null || _fail "snapshot must preserve local source and exclude npm"
_pass "upgrade: legacy local package path recovered and preserved in snapshot"

: > "${fixture}/nvm/calls"
output="$(NVM_DIR="${fixture}/nvm" NODE_SNAPSHOT_DIR="${fixture}/state" "${BIN}" migrate iron iron 2>&1)" || _fail "migrate must restore a file source: ${output}"
first_install_call="$(head -1 "${fixture}/nvm/calls")"
[[ "${first_install_call}" == "${local_source}" ]] || _fail "file source was sent to the registry"
_pass "migrate: file source with spaces restored"

rm "${fixture}/nvm/versions/node/v20.2.0/lib/node_modules/@local/agent"
: > "${fixture}/nvm/calls"
output="$(NVM_DIR="${fixture}/nvm" NODE_SNAPSHOT_DIR="${fixture}/state" "${BIN}" consolidate iron 2>&1)" || _fail "consolidate must preserve local sources: ${output}"
install_calls="$(< "${fixture}/nvm/calls")"
[[ "${install_calls}" == "${local_source}" ]] || _fail "consolidate did not install the local source"
_pass "consolidate: scoped local link restored from older patch"

# With one patch per major there is nothing to uninstall, and that is not a failure.
single="${TMPDIR_OPTIONS}/single-patch"
mkdir -p "${single}/nvm/versions/node/v20.2.0/lib/node_modules" "${single}/nvm/alias/lts" "${single}/state"
cp "${fixture}/nvm/nvm.sh" "${single}/nvm/nvm.sh"
printf 'v20.2.0\n' > "${single}/nvm/alias/lts/iron"
printf '{"tracked":["iron"],"check_interval_days":7,"last_check_utc":""}\n' > "${single}/state/config.json"
output="$(NVM_DIR="${single}/nvm" NODE_SNAPSHOT_DIR="${single}/state" "${BIN}" consolidate iron 2>&1)" || _fail "consolidate iron with one patch must exit 0: ${output}"
output="$(NVM_DIR="${single}/nvm" NODE_SNAPSHOT_DIR="${single}/state" "${BIN}" consolidate 2>&1)" || _fail "consolidate with one patch must exit 0: ${output}"
[[ "${output}" != *"consolidate failed"* ]] || _fail "consolidate with one patch reported a failure: ${output}"
_pass "consolidate: one patch per major succeeds with nothing to remove"

# consolidate uninstalls older patches, so every failure before that point must keep them.
# The mock records installs and uninstalls; its npm install reads stdin like a lifecycle script.
make_consolidate_fixture() {
    local dir="$1" alias_version="$2"
    rm -rf "${dir}"
    mkdir -p "${dir}/nvm/versions/node/v20.1.0/lib/node_modules/pkg-a" \
        "${dir}/nvm/versions/node/v20.1.0/lib/node_modules/pkg-b" \
        "${dir}/nvm/versions/node/v20.2.0/lib/node_modules" "${dir}/nvm/alias/lts" "${dir}/state"
    printf '{"name":"pkg-a","version":"1.0.0"}\n' > "${dir}/nvm/versions/node/v20.1.0/lib/node_modules/pkg-a/package.json"
    printf '{"name":"pkg-b","version":"1.0.0"}\n' > "${dir}/nvm/versions/node/v20.1.0/lib/node_modules/pkg-b/package.json"
    printf '%s\n' "${alias_version}" > "${dir}/nvm/alias/lts/iron"
    printf '{"tracked":["iron"],"check_interval_days":7,"last_check_utc":""}\n' > "${dir}/state/config.json"
    : > "${dir}/nvm/calls"
    cat > "${dir}/nvm/nvm.sh" <<'SH'
_mock_resolve() {
    local v="$1"
    [[ "${v}" == lts/* ]] && v="$(< "${NVM_DIR}/alias/lts/${v#lts/}")"
    [[ -d "${NVM_DIR}/versions/node/${v}" ]] && echo "${v}" || echo N/A
}
nvm() {
    case "$1" in
        deactivate) return 0 ;;
        use)
            local v; v="$(_mock_resolve "$2")"
            [[ "${v}" != N/A ]] || return 3
            export MOCK_VERSION="${v#v}" ;;
        version) _mock_resolve "$2" ;;
        uninstall) echo "uninstall $2" >> "${NVM_DIR}/calls" ;;
        *) return 91 ;;
    esac
}
node() { echo "v${MOCK_VERSION:-0}"; }
npm() {
    local modules="${NVM_DIR}/versions/node/v${MOCK_VERSION:-0}/lib/node_modules"
    case "$1" in
        root) echo "${modules}" ;;
        list) echo '{"dependencies":{}}' ;;
        install)
            cat > /dev/null
            echo "install $3" >> "${NVM_DIR}/calls"
            [[ "$3" != "${MOCK_FAIL_SPEC:-}" ]] || return 1
            mkdir -p "${modules}/${3%@*}"
            printf '{"version":"%s"}\n' "${3##*@}" > "${modules}/${3%@*}/package.json" ;;
        *) return 94 ;;
    esac
}
SH
}
cfix="${TMPDIR_OPTIONS}/consolidate-safety"

make_consolidate_fixture "${cfix}" v20.2.0
output="$(NVM_DIR="${cfix}/nvm" NODE_SNAPSHOT_DIR="${cfix}/state" "${BIN}" consolidate 2>&1)" || _fail "consolidate must succeed: ${output}"
calls="$(< "${cfix}/nvm/calls")"
[[ "${calls}" == *"install pkg-a@1.0.0"* && "${calls}" == *"install pkg-b@1.0.0"* && "${calls}" == *"uninstall v20.1.0"* ]] \
    || _fail "an install that reads stdin must not swallow the remaining packages: ${calls}"
_pass "consolidate: npm install gets no package list on stdin"

make_consolidate_fixture "${cfix}" v20.2.0
output="$(MOCK_FAIL_SPEC=pkg-a@1.0.0 NVM_DIR="${cfix}/nvm" NODE_SNAPSHOT_DIR="${cfix}/state" "${BIN}" consolidate 2>&1)" || true
calls="$(< "${cfix}/nvm/calls")"
[[ "${calls}" != *uninstall* && "${output}" == *"consolidate failed"* ]] \
    || _fail "a failed npm install must keep the older patches: ${calls} / ${output}"
_pass "consolidate: failed npm install keeps the older patches"

make_consolidate_fixture "${cfix}" v20.3.0
output="$(NVM_DIR="${cfix}/nvm" NODE_SNAPSHOT_DIR="${cfix}/state" "${BIN}" consolidate 2>&1)" || true
calls="$(< "${cfix}/nvm/calls")"
[[ -z "${calls}" && "${output}" == *"v20.3.0, which is not installed"* ]] \
    || _fail "an LTS alias ahead of the installs must stop consolidate before any change: ${calls} / ${output}"
_pass "consolidate: LTS alias pointing at an uninstalled release changes nothing"

ln -sfn "${fixture}/missing source" "${fixture}/nvm/versions/node/v20.1.0/lib/node_modules/@local/agent"
seed_legacy_lock
output="$(NVM_DIR="${fixture}/nvm" NODE_SNAPSHOT_DIR="${fixture}/state" "${BIN}" migrate iron iron 2>&1)" || _fail "migrate must skip a broken source link: ${output}"
install_calls="$(< "${fixture}/nvm/calls")"
[[ "${install_calls}" == "${local_source}"$'\nregistry-pkg@1.2.3' ]] || _fail "migrate must recover the local path from the destination link"
_pass "migrate: broken source link falls back to destination link"

printf '{"node_version":"20.1.0","packages":{"registry-pkg":"1.2.3","@local/agent":"file:/nonexistent/node-snapshot-local-package"}}\n' > "${fixture}/state/lts-iron.lock.json"
: > "${fixture}/nvm/calls"
command_exit=0
output="$(NVM_DIR="${fixture}/nvm" NODE_SNAPSHOT_DIR="${fixture}/state" "${BIN}" migrate iron iron 2>&1)" || command_exit=$?
[[ "${command_exit}" -ne 0 && ! -s "${fixture}/nvm/calls" ]] || _fail "missing local source must fail before npm install"
_assert_match "${output}" "local package source not found"
_pass "migrate: missing local source fails without registry fallback"

# ── PATH shadowing (real executables, nvm-style in-place PATH swap) ───────────
fixture="${TMPDIR_OPTIONS}/path-shadow"
mkdir -p "${fixture}/shadow" "${fixture}/nvm/versions/node/v20.2.0/bin" "${fixture}/state"
cat > "${fixture}/shadow/node" <<'SH'
#!/bin/sh
echo v24.20.0
SH
cat > "${fixture}/shadow/npm" <<'SH'
#!/bin/sh
case "$1" in
    root) echo "$(dirname "$0")/lib/node_modules" ;;
    list) echo '{"dependencies":{"shadow-pkg":{"version":"9.9.9"}}}' ;;
esac
SH
cat > "${fixture}/nvm/versions/node/v20.2.0/bin/node" <<'SH'
#!/bin/sh
echo v20.2.0
SH
cat > "${fixture}/nvm/versions/node/v20.2.0/bin/npm" <<'SH'
#!/bin/sh
case "$1" in
    root) echo "$(cd "$(dirname "$0")/.." && pwd)/lib/node_modules" ;;
    list) echo '{"dependencies":{"real-pkg":{"version":"1.0.0"}}}' ;;
esac
SH
chmod +x "${fixture}/shadow/node" "${fixture}/shadow/npm" \
    "${fixture}/nvm/versions/node/v20.2.0/bin/node" "${fixture}/nvm/versions/node/v20.2.0/bin/npm"
cat > "${fixture}/nvm/nvm.sh" <<'SH'
nvm() {
    local entry="${NVM_DIR}/versions/node/[^/:]*/bin"
    local bin="${NVM_DIR}/versions/node/v20.2.0/bin"
    case "$1" in
        deactivate) PATH="$(sed -e "s#${entry}:##g" <<< "${PATH}")" ;;
        use)
            # Like nvm_change_path: swap an existing nvm entry in place, else prepend.
            if grep -q "${entry}" <<< "${PATH}"; then
                PATH="$(sed -e "s#${entry}#${bin}#" <<< "${PATH}")"
            else
                PATH="${bin}:${PATH}"
            fi
            ;;
        version) echo v20.2.0 ;;
        *) return 91 ;;
    esac
}
SH
output="$(PATH="${fixture}/shadow:${fixture}/nvm/versions/node/v20.1.0/bin:${PATH}" \
    NVM_DIR="${fixture}/nvm" NODE_SNAPSHOT_DIR="${fixture}/state" "${BIN}" snapshot iron 2>&1)" \
    || _fail "snapshot must use nvm's node despite a shadowing node earlier in PATH: ${output}"
jq -e '.node_version == "20.2.0" and .packages == {"real-pkg": "1.0.0"}' "${fixture}/state/lts-iron.lock.json" >/dev/null \
    || _fail "snapshot recorded the shadowing node: $(< "${fixture}/state/lts-iron.lock.json")"
_pass "snapshot: nvm's node wins over a node earlier in PATH"

# ── upgrade and snapshot failure paths ───────────────────────────────────────
# The mock nvm installs into the fixture and, like nvm, refuses --reinstall-packages-from
# for a version that is not installed. MOCK_FAIL_INSTALL, MOCK_OFFLINE and MOCK_NPM_LIST_EXIT
# select the failure under test.
make_upgrade_fixture() {
    local dir="$1"
    rm -rf "${dir}"
    mkdir -p "${dir}/nvm/versions/node/v20.2.0/lib/node_modules" \
        "${dir}/nvm/versions/node/v22.1.0/lib/node_modules" "${dir}/nvm/alias/lts" "${dir}/state"
    printf 'v20.2.0\n' > "${dir}/nvm/alias/lts/iron"
    printf 'v22.1.0\n' > "${dir}/nvm/alias/lts/jod"
    printf '{"tracked":["iron","jod"],"check_interval_days":1,"last_check_utc":""}\n' > "${dir}/state/config.json"
    printf '{"node_version":"20.2.0","packages":{}}\n' > "${dir}/state/lts-iron.lock.json"
    printf '{"node_version":"22.1.0","packages":{}}\n' > "${dir}/state/lts-jod.lock.json"
    : > "${dir}/nvm/calls"
    cat > "${dir}/nvm/nvm.sh" <<'SH'
_mock_remote() { case "$1" in lts/iron) echo v20.3.0 ;; lts/jod) echo v22.2.0 ;; esac; }
_mock_resolve() {
    local v="$1"
    [[ "${v}" == lts/* ]] && v="$(< "${NVM_DIR}/alias/lts/${v#lts/}")"
    [[ -d "${NVM_DIR}/versions/node/${v}" ]] && echo "${v}" || echo N/A
}
nvm() {
    local v arg
    case "$1" in
        deactivate) return 0 ;;
        version-remote) _mock_remote "$2" ;;
        install)
            echo "$*" >> "${NVM_DIR}/calls"
            [[ "$2" != "${MOCK_FAIL_INSTALL:-}" ]] || return 1
            for arg in "$@"; do
                [[ "${arg}" != --reinstall-packages-from=* ]] && continue
                [[ -d "${NVM_DIR}/versions/node/v${arg#*=}" ]] || return 5
            done
            v="$(_mock_remote "$2")"
            mkdir -p "${NVM_DIR}/versions/node/${v}/lib/node_modules"
            echo "${v}" > "${NVM_DIR}/alias/lts/${2#lts/}" ;;
        use)
            v="$(_mock_resolve "$2")"
            [[ "${v}" != N/A ]] || return 3
            export MOCK_VERSION="${v#v}" ;;
        version) _mock_resolve "$2" ;;
        ls-remote)
            echo "ls-remote $2" >> "${NVM_DIR}/calls"
            [[ -z "${MOCK_OFFLINE:-}" ]] || return 3
            echo "       $(_mock_remote "$2")" ;;
        ls) _mock_resolve "$2" ;;
        *) return 91 ;;
    esac
}
node() { echo "v${MOCK_VERSION:-0}"; }
npm() {
    case "$1" in
        root) echo "${NVM_DIR}/versions/node/v${MOCK_VERSION:-0}/lib/node_modules" ;;
        list)
            if [[ -n "${MOCK_GLOBALS_FILE:-}" ]]; then
                cat "${MOCK_GLOBALS_FILE}"
            elif [[ -n "${MOCK_NPM_LIST_JSON:-}" ]]; then
                echo "${MOCK_NPM_LIST_JSON}"
            else
                echo '{"dependencies":{"pkg":{"version":"1.0.0"}}}'
            fi
            return "${MOCK_NPM_LIST_EXIT:-0}" ;;
        install)
            echo "npm $*" >> "${NVM_DIR}/calls"
            [[ -z "${MOCK_FAIL_NPM_INSTALL:-}" ]] || return 7
            if [[ -n "${MOCK_GLOBALS_FILE:-}" ]]; then
                jq --arg pkg "${3%@*}" --arg version "${3##*@}" \
                    '.dependencies[$pkg] = {version: $version}' "${MOCK_GLOBALS_FILE}" > "${MOCK_GLOBALS_FILE}.tmp"
                mv "${MOCK_GLOBALS_FILE}.tmp" "${MOCK_GLOBALS_FILE}"
            fi
            ;;
        *) return 94 ;;
    esac
}
SH
}
ufix="${TMPDIR_OPTIONS}/upgrade-paths"
unode() { NVM_DIR="${ufix}/nvm" NODE_SNAPSHOT_DIR="${ufix}/state" "${BIN}" "$@" 2>&1; }

make_upgrade_fixture "${ufix}"
printf '{"node_version":"20.0.9","packages":{}}\n' > "${ufix}/state/lts-iron.lock.json"
output="$(unode upgrade iron)" || _fail "upgrade must not pass an uninstalled version to --reinstall-packages-from: ${output}"
[[ "$(< "${ufix}/nvm/calls")" == "install lts/iron --latest-npm" ]] || _fail "unexpected install: $(< "${ufix}/nvm/calls")"
_pass "upgrade: a lock version that is not installed is restored from the lock"

# The lock names the newest release, which nvm installs, so old and new versions match.
make_upgrade_fixture "${ufix}"
printf '{"node_version":"20.3.0","packages":{"pkg-x":"1.0.0"}}\n' > "${ufix}/state/lts-iron.lock.json"
output="$(unode upgrade iron)" || _fail "upgrade must restore a lock whose version it just installed: ${output}"
[[ "$(< "${ufix}/nvm/calls")" == *"npm install -g pkg-x@1.0.0"* ]] || _fail "packages were not restored from the lock: $(< "${ufix}/nvm/calls")"
_pass "upgrade: a lock version installed by this upgrade is restored from the lock"

# An already-installed target may still have no user globals (e.g. after a restore).
make_upgrade_fixture "${ufix}"
mkdir -p "${ufix}/nvm/versions/node/v20.3.0/lib/node_modules"
printf '{"node_version":"20.3.0","packages":{"pkg-x":"1.0.0"}}\n' > "${ufix}/state/lts-iron.lock.json"
printf '{"dependencies":{"npm":{"version":"10.0.0"},"corepack":{"version":"0.30.0"}}}\n' > "${ufix}/globals.json"
output="$(MOCK_GLOBALS_FILE="${ufix}/globals.json" unode upgrade iron)" \
    || _fail "upgrade must restore empty globals on an already-installed lock version: ${output}"
jq -e '.dependencies["pkg-x"].version == "1.0.0"' "${ufix}/globals.json" >/dev/null \
    || _fail "upgrade did not restore the locked package"
jq -e '.node_version == "20.3.0" and .packages == {"pkg-x":"1.0.0"}' "${ufix}/state/lts-iron.lock.json" >/dev/null \
    || _fail "upgrade did not retain the restored package in the lock"
_pass "upgrade: already-installed lock version with empty globals is restored"

: > "${ufix}/nvm/calls"
output="$(MOCK_GLOBALS_FILE="${ufix}/globals.json" unode upgrade iron)" \
    || _fail "upgrade of populated globals must succeed: ${output}"
[[ "$(< "${ufix}/nvm/calls")" != *"npm install"* ]] || _fail "populated globals must not be reinstalled"
_pass "upgrade: repeat on populated globals does not reinstall packages"

printf '{"dependencies":{"live-pkg":{"version":"2.0.0"}}}\n' > "${ufix}/globals.json"
output="$(MOCK_GLOBALS_FILE="${ufix}/globals.json" unode upgrade iron)" \
    || _fail "upgrade must snapshot a non-empty live set: ${output}"
jq -e '.packages == {"live-pkg":"2.0.0"}' "${ufix}/state/lts-iron.lock.json" >/dev/null \
    || _fail "upgrade must keep the non-empty live set authoritative"
_pass "upgrade: non-empty live globals remain authoritative"

printf '{"dependencies":{}}\n' > "${ufix}/globals.json"
lock_before="$(< "${ufix}/state/lts-iron.lock.json")"
command_exit=0
output="$(MOCK_GLOBALS_FILE="${ufix}/globals.json" unode snapshot iron)" || command_exit=$?
[[ "${command_exit}" -ne 0 && "$(< "${ufix}/state/lts-iron.lock.json")" == "${lock_before}" ]] \
    || _fail "direct snapshot must still refuse an empty wipe: ${output}"
_pass "snapshot: empty wipe guard remains active"

: > "${ufix}/nvm/calls"
command_exit=0
output="$(MOCK_GLOBALS_FILE="${ufix}/globals.json" MOCK_FAIL_NPM_INSTALL=1 unode upgrade iron)" || command_exit=$?
[[ "${command_exit}" -ne 0 && "$(< "${ufix}/state/lts-iron.lock.json")" == "${lock_before}" ]] \
    || _fail "failed package restoration must preserve the lock: ${output}"
[[ "$(< "${ufix}/nvm/calls")" == *"npm install -g live-pkg@2.0.0"* ]] \
    || _fail "upgrade did not attempt restoration"
_pass "upgrade: failed same-version restoration preserves the lock"

: > "${ufix}/nvm/calls"
printf '{"error":{"code":"EFAIL"}}\n' > "${ufix}/globals.json"
command_exit=0
output="$(MOCK_GLOBALS_FILE="${ufix}/globals.json" MOCK_NPM_LIST_EXIT=1 unode upgrade iron)" || command_exit=$?
[[ "${command_exit}" -ne 0 && "$(< "${ufix}/state/lts-iron.lock.json")" == "${lock_before}" \
    && "$(< "${ufix}/nvm/calls")" != *"npm install"* ]] \
    || _fail "failed npm inspection must not trigger restoration or change the lock: ${output}"
_pass "upgrade: failed npm inspection preserves the lock without restoration"

make_upgrade_fixture "${ufix}"
command_exit=0
output="$(MOCK_FAIL_INSTALL=lts/iron unode upgrade)" || command_exit=$?
[[ "${command_exit}" -ne 0 && "${output}" == *"lts/iron: upgrade failed"* ]] || _fail "a failed alias must be reported: ${output}"
[[ "$(< "${ufix}/nvm/calls")" == *"install lts/jod"* ]] || _fail "a failed alias must not stop the next one: $(< "${ufix}/nvm/calls")"
_pass "upgrade: one failed alias does not stop the others"

make_upgrade_fixture "${ufix}"
output="$(MOCK_NPM_LIST_EXIT=1 unode snapshot iron)" || _fail "snapshot must accept npm list output with a non-zero status: ${output}"
jq -e '.packages == {"pkg": "1.0.0"}' "${ufix}/state/lts-iron.lock.json" >/dev/null || _fail "snapshot did not record the listed packages"
_pass "snapshot: npm list ELSPROBLEMS exit still records the packages"

make_upgrade_fixture "${ufix}"
rm "${ufix}/state/lts-iron.lock.json"
command_exit=0
output="$(MOCK_NPM_LIST_EXIT=1 MOCK_NPM_LIST_JSON='{"error":{"code":"EFAIL"}}' unode snapshot iron)" || command_exit=$?
[[ "${command_exit}" -ne 0 && ! -e "${ufix}/state/lts-iron.lock.json" ]] || _fail "a failed npm list must not be recorded as no packages: ${output}"
_pass "snapshot: a failed npm list without dependencies records nothing"

make_upgrade_fixture "${ufix}"
output="$(MOCK_OFFLINE=1 unode upgrade --check)" || _fail "upgrade --check failed offline: ${output}"
[[ "$(jq -r '.last_check_utc' "${ufix}/state/config.json")" == "" ]] || _fail "an offline check must not be recorded"
_pass "upgrade --check: an offline check is not recorded"

# 20 hours ago is under the one-day interval in UTC, but over it when parsed as KST.
make_upgrade_fixture "${ufix}"
recent="$(date -u -v-20H +"%Y-%m-%dT%H:%M:%SZ")"
jq --arg t "${recent}" '.last_check_utc = $t' "${ufix}/state/config.json" > "${ufix}/state/config.tmp"
mv "${ufix}/state/config.tmp" "${ufix}/state/config.json"
output="$(TZ=Asia/Seoul unode upgrade --check)" || _fail "upgrade --check failed: ${output}"
[[ "$(< "${ufix}/nvm/calls")" != *ls-remote* ]] || _fail "a check within the interval ran in a UTC+9 zone"
_pass "upgrade --check: the last check time is read as UTC"

echo ""; echo "All unit tests: PASS"
