#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

# Source nvm — required because libexec scripts run in a fresh bash process
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh"
else
    echo "error: nvm not found at ${NVM_DIR}/nvm.sh" >&2
    echo "Install nvm: https://github.com/nvm-sh/nvm" >&2
    exit 1
fi

_ensure_config() {
    mkdir -p "${STATE_DIR}"
    if [[ ! -f "${STATE_DIR}/config.json" ]]; then
        printf '{\n  "tracked": ["iron", "jod", "krypton"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
            > "${STATE_DIR}/config.json"
    fi
}

_snapshot_alias() {
    local lts_alias="$1"
    echo "→ nvm use lts/${lts_alias}"
    nvm use "lts/${lts_alias}" >/dev/null 2>&1

    local packages_json node_version now lock_file
    packages_json="$(npm list -g --depth=0 --json 2>/dev/null \
        | jq '.dependencies // {} | del(.npm) | del(.corepack) | to_entries | map({key: .key, value: .value.version}) | from_entries')"
    node_version="$(node -v | tr -d 'v')"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    lock_file="${STATE_DIR}/lts-${lts_alias}.lock.json"

    jq -n \
        --arg lts_alias   "${lts_alias}" \
        --arg node_version "${node_version}" \
        --arg snapshot_utc "${now}" \
        --argjson packages  "${packages_json}" \
        '{lts_alias: $lts_alias, node_version: $node_version, snapshot_utc: $snapshot_utc, packages: $packages}' \
        > "${lock_file}"

    echo "✓ lts/${lts_alias} (${node_version}) → ${lock_file}"
}

_ensure_config

alias_arg="${1:-}"
if [[ -n "${alias_arg}" ]]; then
    _snapshot_alias "${alias_arg}"
else
    while IFS= read -r lts_alias; do
        ( _snapshot_alias "${lts_alias}" ) || \
            echo "⚠ lts/${lts_alias}: snapshot failed (alias not installed?)" >&2
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)
fi

date -u +"%Y-%m-%dT%H:%M:%SZ" > "${STATE_DIR}/last_snapshot_utc"
echo ""
echo "✓ Snapshot complete → ${STATE_DIR}"
