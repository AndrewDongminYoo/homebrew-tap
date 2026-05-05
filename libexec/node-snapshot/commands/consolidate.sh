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

# Emit "pkg_name=version" lines for user-installed packages in a node_modules directory.
# Reads directly from disk — no nvm activation needed. Handles @scope/pkg layout.
_scan_modules_dir() {
    local modules_dir="$1"
    [[ -d "${modules_dir}" ]] || return 0

    for entry in "${modules_dir}"/*/; do
        [[ -d "${entry}" ]] || continue
        local name
        name="$(basename "${entry}")"

        if [[ "${name}" == @* ]]; then
            for scoped_entry in "${entry}"*/; do
                [[ -d "${scoped_entry}" ]] || continue
                local scoped_name
                scoped_name="${name}/$(basename "${scoped_entry}")"
                local pkg_json="${scoped_entry}package.json"
                [[ -f "${pkg_json}" ]] || continue
                local ver
                ver="$(jq -r '.version // ""' "${pkg_json}" 2>/dev/null || true)"
                [[ -n "${ver}" ]] && printf '%s=%s\n' "${scoped_name}" "${ver}"
            done
            continue
        fi

        [[ "${name}" == "npm" ]]      && continue
        [[ "${name}" == "corepack" ]] && continue
        [[ "${name}" == .* ]]         && continue

        local pkg_json="${entry}package.json"
        [[ -f "${pkg_json}" ]] || continue
        local ver
        ver="$(jq -r '.version // ""' "${pkg_json}" 2>/dev/null || true)"
        [[ -n "${ver}" ]] && printf '%s=%s\n' "${name}" "${ver}"
    done
}

_consolidate_alias() {
    local lts_alias="$1"
    local alias_file="${NVM_DIR}/alias/lts/${lts_alias}"

    if [[ ! -f "${alias_file}" ]]; then
        echo "⚠ lts/${lts_alias}: alias not found in nvm" >&2
        return 1
    fi

    local latest_ver major
    latest_ver="$(tr -d 'v' < "${alias_file}")"  # e.g. "20.20.2"
    major="${latest_ver%%.*}"                      # e.g. "20"

    echo "→ lts/${lts_alias}: consolidating v${major}.x.x → v${latest_ver}"

    # Collect all installed patch directories for this major, oldest → newest
    local -a patch_dirs=()
    while IFS= read -r d; do
        [[ -d "${d}" ]] && patch_dirs+=("${d}")
    done < <(find "${NVM_DIR}/versions/node" -maxdepth 1 -name "v${major}.*" -type d 2>/dev/null | sort -V)

    if [[ ${#patch_dirs[@]} -eq 0 ]]; then
        echo "  ⚠ no v${major}.x.x installs found" >&2
        return 1
    fi

    local version_list
    version_list="$(for d in "${patch_dirs[@]}"; do basename "${d}"; done | tr '\n' ' ')"
    echo "  scanning: ${version_list}"

    # Merge packages across all patches. Process oldest→newest so that
    # a newer patch's version of a package overrides an older one.
    local merged_json
    merged_json="$(
        for patch_dir in "${patch_dirs[@]}"; do
            _scan_modules_dir "${patch_dir}/lib/node_modules"
        done | jq -Rs '
            split("\n")
            | map(select(length > 0))
            | map(split("="))
            | map(select(length >= 2))
            | map({key: .[0], value: (.[1:] | join("="))})
            | from_entries
        '
    )"

    local total
    total="$(printf '%s' "${merged_json}" | jq 'length')"

    if [[ "${total}" -eq 0 ]]; then
        echo "  no user-installed packages found across v${major}.x.x"
        "${_self_dir}/snapshot.sh" "${lts_alias}"
        return 0
    fi

    echo "  ${total} unique package(s) found"

    nvm use "lts/${lts_alias}" >/dev/null 2>&1
    local target_modules="${NVM_DIR}/versions/node/v${latest_ver}/lib/node_modules"

    local installed=0 skipped=0
    while IFS="=" read -r pkg want_ver; do
        [[ -z "${pkg}" ]] && continue

        local current_ver=""
        local pkg_json="${target_modules}/${pkg}/package.json"
        if [[ -f "${pkg_json}" ]]; then
            current_ver="$(jq -r '.version // ""' "${pkg_json}" 2>/dev/null || true)"
        fi

        if [[ "${current_ver}" == "${want_ver}" ]]; then
            echo "  ✓ ${pkg}@${want_ver}"
            skipped=$(( skipped + 1 ))
        else
            echo "  npm install -g ${pkg}@${want_ver}"
            npm install -g "${pkg}@${want_ver}"
            installed=$(( installed + 1 ))
        fi
    done < <(printf '%s' "${merged_json}" | jq -r 'to_entries[] | "\(.key)=\(.value)"')

    echo "  installed: ${installed}, already present: ${skipped}"
    "${_self_dir}/snapshot.sh" "${lts_alias}"
}

_ensure_config

alias_arg="${1:-}"
if [[ -n "${alias_arg}" ]]; then
    _consolidate_alias "${alias_arg}"
else
    while IFS= read -r lts_alias; do
        # shellcheck disable=SC2310
        ( _consolidate_alias "${lts_alias}" ) || \
            echo "⚠ lts/${lts_alias}: consolidate failed" >&2
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json" 2>/dev/null || true)
fi

echo ""
echo "✓ Consolidate complete"
