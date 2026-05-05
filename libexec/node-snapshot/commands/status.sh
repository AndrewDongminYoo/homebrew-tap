#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

if [[ ! -f "${STATE_DIR}/config.json" ]]; then
    echo "No snapshot found. Run 'node-snapshot snapshot' first."
    exit 0
fi

# nvm is optional here — status degrades gracefully without it
NVM_AVAILABLE=false
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh"
    NVM_AVAILABLE=true
fi

last_check="$(jq -r '.last_check_utc // "(never)"' "${STATE_DIR}/config.json" 2>/dev/null || echo '(never)')"

echo "Node Snapshot — State directory: ${STATE_DIR}"
echo "Last check:   ${last_check}"
echo ""
printf "%-12s %-14s %-16s %s\n" "Alias" "Installed" "Lock version" "Status"
printf "%-12s %-14s %-16s %s\n" "-----" "---------" "------------" "------"

while IFS= read -r alias; do
    lock_file="${STATE_DIR}/lts-${alias}.lock.json"

    installed="-"
    if ${NVM_AVAILABLE}; then
        installed="$(nvm ls "lts/${alias}" --no-colors 2>/dev/null \
            | grep -v 'N/A' | grep -o 'v[0-9.]*' | head -1 || echo '-')"
    fi

    lock_version="(none)"
    status="– not snapshotted"
    if [[ -f "${lock_file}" ]]; then
        raw="$(jq -r '.node_version // ""' "${lock_file}" 2>/dev/null || echo '')"
        if [[ -n "${raw}" ]]; then
            lock_version="v${raw}"
            if ${NVM_AVAILABLE} && [[ "${installed}" != "-" ]]; then
                if [[ "${installed}" == "${lock_version}" ]]; then
                    status="✓ up-to-date"
                else
                    status="⚠ outdated"
                fi
            else
                status="✓ snapshotted"
            fi
        fi
    fi

    printf "%-12s %-14s %-16s %s\n" "${alias}" "${installed}" "${lock_version}" "${status}"
done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)
