#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh"
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
        last_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_check}" "+%s" 2>/dev/null || echo '0')"
        now_epoch="$(date -u "+%s")"
        days_since=$(( (now_epoch - last_epoch) / 86400 ))
        if [[ "${days_since}" -lt "${interval}" ]]; then
            exit 0
        fi
    fi

    while IFS= read -r lts_alias; do
        local remote_latest local_version
        remote_latest="$(nvm ls-remote "lts/${lts_alias}" --no-colors 2>/dev/null \
            | grep -o 'v[0-9.]*' | tail -1 || echo '')"
        local_version="$(nvm ls "lts/${lts_alias}" --no-colors 2>/dev/null \
            | grep -v 'N/A' | grep -o 'v[0-9.]*' | head -1 || echo '')"

        if [[ -n "${remote_latest}" ]] && [[ "${remote_latest}" != "${local_version}" ]]; then
            echo "[node-snapshot] lts/${lts_alias} update available: ${local_version:-not installed} → ${remote_latest}"
            echo "  Run: node-snapshot upgrade ${lts_alias}"
        fi
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)

    _update_last_check
}

_upgrade_alias() {
    local lts_alias="$1"
    local lock_file="${STATE_DIR}/lts-${lts_alias}.lock.json"
    local old_node_version=""

    if [[ -f "${lock_file}" ]]; then
        old_node_version="$(jq -r '.node_version // ""' "${lock_file}" 2>/dev/null || echo '')"
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
    if [[ -n "${old_node_version}" ]] && [[ -n "${target_version}" ]] \
        && [[ "${old_node_version}" != "${target_version}" ]]; then
        echo "→ nvm install lts/${lts_alias} --latest-npm --reinstall-packages-from=${old_node_version}"
        nvm install "lts/${lts_alias}" --latest-npm --reinstall-packages-from="${old_node_version}"
    else
        echo "→ nvm install lts/${lts_alias} --latest-npm"
        nvm install "lts/${lts_alias}" --latest-npm
    fi
    nvm use "lts/${lts_alias}" >/dev/null 2>&1
    local new_node_version
    new_node_version="$(node -v | tr -d 'v')"

    if [[ -n "${old_node_version}" ]] && [[ "${old_node_version}" != "${new_node_version}" ]]; then
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
    while IFS= read -r lts_alias; do
        _upgrade_alias "${lts_alias}"
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)
fi
