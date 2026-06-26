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
    nvm use "lts/${lts_alias}" >/dev/null 2>&1

    local packages_json node_version now lock_file
    node_version="$(node -v | tr -d 'v')"
    echo "→ nvm use lts/${lts_alias} (v${node_version})"
    packages_json="$(npm list -g --depth=0 --json 2>/dev/null \
        | jq '.dependencies // {} | del(.npm) | del(.corepack) | to_entries | map({key: .key, value: .value.version}) | from_entries')"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    lock_file="${STATE_DIR}/lts-${lts_alias}.lock.json"

    # Live state is authoritative, but guard the lock against accidental loss.
    if [[ -f "${lock_file}" ]]; then
        local old_count new_count dropped
        old_count="$(jq '(.packages // {}) | length' "${lock_file}" 2>/dev/null || echo 0)"
        new_count="$(jq 'length' <<< "${packages_json}" 2>/dev/null || echo 0)"

        # Refuse a full wipe — empty live globals over a non-empty lock almost
        # always means snapshotting a freshly installed Node version before its
        # packages were migrated. Recording it would destroy the lock.
        if [[ "${new_count}" -eq 0 ]] && [[ "${old_count}" -gt 0 ]] && ! ${FORCE}; then
            echo "✗ lts/${lts_alias}: refusing to overwrite ${old_count} tracked package(s) with an empty snapshot." >&2
            echo "  Live globals for v${node_version} are empty — likely a freshly installed Node version." >&2
            echo "  Restore them:        node-snapshot migrate ${lts_alias} ${lts_alias}" >&2
            echo "  Record empty anyway: node-snapshot snapshot --force ${lts_alias}" >&2
            return 1
        fi

        # Warn on a partial drop but still record it (live is the source of truth).
        dropped="$(jq -nr \
            --slurpfile old "${lock_file}" \
            --argjson new "${packages_json}" \
            '(($old[0].packages // {}) | keys) - ($new | keys) | .[]' 2>/dev/null || true)"
        if [[ -n "${dropped}" ]]; then
            echo "⚠ lts/${lts_alias}: snapshot drops packages no longer installed globally:" >&2
            while IFS= read -r pkg; do
                [[ -n "${pkg}" ]] && echo "    - ${pkg}" >&2
            done <<< "${dropped}"
            echo "  If unexpected, recover the previous lock from git before committing." >&2
        fi
    fi

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

FORCE=false
alias_arg=""
for arg in "$@"; do
    case "${arg}" in
        --force) FORCE=true ;;
        *)       alias_arg="${arg}" ;;
    esac
done

if [[ -n "${alias_arg}" ]]; then
    _snapshot_alias "${alias_arg}"
else
    while IFS= read -r lts_alias; do
        # shellcheck disable=SC2310
        ( _snapshot_alias "${lts_alias}" ) || \
            echo "⚠ lts/${lts_alias}: snapshot failed (alias not installed?)" >&2
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)
fi

date -u +"%Y-%m-%dT%H:%M:%SZ" > "${STATE_DIR}/last_snapshot_utc"
echo ""
echo "✓ Snapshot complete → ${STATE_DIR}"
