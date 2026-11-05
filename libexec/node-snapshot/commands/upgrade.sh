#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh"
    # Drop nvm's PATH entry so `nvm use` prepends its bin. Otherwise nvm swaps
    # the entry in place, behind any earlier node (e.g. a ~/.local/bin/node symlink).
    nvm deactivate >/dev/null 2>&1 || true
else
    echo "error: nvm not found at ${NVM_DIR}/nvm.sh" >&2
    echo "Install nvm: https://github.com/nvm-sh/nvm" >&2
    exit 1
fi

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_ensure_config() {
    mkdir -p "${STATE_DIR}"
    if [[ ! -f "${STATE_DIR}/config.json" ]]; then
        printf '{\n  "tracked": ["iron", "jod", "krypton"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
            > "${STATE_DIR}/config.json"
    fi
}

_update_last_check() {
    local tmp now
    tmp="$(mktemp)"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    jq --arg now "${now}" '.last_check_utc = $now' \
        "${STATE_DIR}/config.json" > "${tmp}"
    mv "${tmp}" "${STATE_DIR}/config.json"
}

_check_mode() {
    local last_check interval last_epoch now_epoch days_since
    last_check="$(jq -r '.last_check_utc // ""' "${STATE_DIR}/config.json" 2>/dev/null || echo '')"
    interval="$(jq -r '.check_interval_days // 7' "${STATE_DIR}/config.json" 2>/dev/null || echo '7')"

    if [[ -n "${last_check}" ]]; then
        # The trailing Z is a literal to date -j, so name the zone or it parses local time.
        last_epoch="$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_check}" "+%s" 2>/dev/null || echo '0')"
        now_epoch="$(date -u "+%s")"
        days_since=$(( (now_epoch - last_epoch) / 86400 ))
        if [[ "${days_since}" -lt "${interval}" ]]; then
            exit 0
        fi
    fi

    local reached=false
    while IFS= read -r lts_alias; do
        local remote_latest local_version
        remote_latest="$(nvm ls-remote "lts/${lts_alias}" --no-colors 2>/dev/null \
            | grep -o 'v[0-9.]*' | tail -1 || echo '')"
        [[ -n "${remote_latest}" ]] && reached=true
        local_version="$(nvm ls "lts/${lts_alias}" --no-colors 2>/dev/null \
            | grep -v 'N/A' | grep -o 'v[0-9.]*' | head -1 || echo '')"

        if [[ -n "${remote_latest}" ]] && [[ "${remote_latest}" != "${local_version}" ]]; then
            echo "[node-snapshot] lts/${lts_alias} update available: ${local_version:-not installed} → ${remote_latest}"
            echo "  Run: node-snapshot upgrade ${lts_alias}"
        fi
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)

    # Offline, every lookup is empty; recording the check would skip the next interval.
    if ${reached}; then
        _update_last_check
    fi
}

_upgrade_alias() {
    local lts_alias="$1"
    local lock_file="${STATE_DIR}/lts-${lts_alias}.lock.json"
    local old_node_version=""

    if [[ -f "${lock_file}" ]]; then
        old_node_version="$(jq -r '.node_version // ""' "${lock_file}" 2>/dev/null || echo '')"
    fi
    # On a Mac restored from the lock the locked version is not installed; its packages then
    # come from the lock even when nvm installs that same version below.
    local old_node_installed=false
    if [[ -n "${old_node_version}" && -d "${NVM_DIR}/versions/node/v${old_node_version}" ]]; then
        old_node_installed=true
    fi

    # Resolve the target version before installing so the reinstall flag is only
    # added on an actual version bump — nvm exits non-zero when asked to
    # reinstall packages from the same version it is installing.
    local target_version
    target_version="$(nvm version-remote "lts/${lts_alias}" 2>/dev/null | tr -d 'v' || echo '')"

    # Carry global packages forward at install time. Without
    # --reinstall-packages-from, the new Node version is installed with an empty
    # global set; a snapshot taken in that window would overwrite the lock with
    # an empty package list (see snapshot.sh — live state always wins).
    # nvm refuses to install at all when the reinstall source is not installed, as on a new
    # Mac restored from the lock; migrate.sh below then restores the packages from the lock.
    if [[ -n "${old_node_version}" ]] && [[ -n "${target_version}" ]] \
        && [[ "${old_node_version}" != "${target_version}" ]] \
        && ${old_node_installed}; then
        echo "→ nvm install lts/${lts_alias} --latest-npm --reinstall-packages-from=${old_node_version}"
        nvm install "lts/${lts_alias}" --latest-npm --reinstall-packages-from="${old_node_version}"
    else
        echo "→ nvm install lts/${lts_alias} --latest-npm"
        nvm install "lts/${lts_alias}" --latest-npm
    fi
    nvm use "lts/${lts_alias}" >/dev/null 2>&1
    local new_node_version
    new_node_version="$(node -v | tr -d 'v')"

    local needs_migration=false
    if [[ -n "${old_node_version}" ]] \
        && [[ "${old_node_version}" != "${new_node_version}" || "${old_node_installed}" == false ]]; then
        needs_migration=true
    elif [[ -f "${lock_file}" ]] && jq -e '(.packages // {}) | length > 0' "${lock_file}" >/dev/null; then
        # An existing installation can still be bare. Restore its lock before
        # snapshotting, while keeping non-empty live globals authoritative.
        local npm_json npm_status=0
        npm_json="$(npm list -g --depth=0 --json 2>/dev/null)" || npm_status=$?
        if [[ "${npm_status}" -ne 0 ]] \
            && ! jq -e '(.dependencies | type) == "object"' <<< "${npm_json}" >/dev/null 2>&1; then
            echo "✗ lts/${lts_alias}: npm list -g failed (exit ${npm_status}) without a package list" >&2
            return 1
        fi
        if jq -e '.dependencies // {} | del(.npm, .corepack) | length == 0' <<< "${npm_json}" >/dev/null; then
            needs_migration=true
        fi
    fi

    if ${needs_migration}; then
        echo "→ migrating packages (${old_node_version} → ${new_node_version})"
        "${_self_dir}/migrate.sh" "${lts_alias}" "${lts_alias}"
        # migrate.sh runs snapshot internally
    else
        "${_self_dir}/snapshot.sh" "${lts_alias}"
    fi
}

_ensure_config

CHECK=false
ALIAS=""
for arg in "$@"; do
    case "${arg}" in
        --check) CHECK=true  ;;
        *)       ALIAS="${arg}" ;;
    esac
done

if ${CHECK}; then
    _check_mode
    exit 0
fi

if [[ -n "${ALIAS}" ]]; then
    _upgrade_alias "${ALIAS}"
else
    aliases=()
    while IFS= read -r lts_alias; do
        [[ -n "${lts_alias}" ]] && aliases+=("${lts_alias}")
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)
    # Each alias runs in its own process: set -e still stops that alias at its first failure,
    # the next aliases still run, and nvm or npm cannot read the alias list from stdin.
    failed=0
    for lts_alias in ${aliases[@]+"${aliases[@]}"}; do
        "${BASH_SOURCE[0]}" "${lts_alias}" </dev/null || {
            echo "⚠ lts/${lts_alias}: upgrade failed" >&2
            failed=1
        }
    done
    exit "${failed}"
fi
