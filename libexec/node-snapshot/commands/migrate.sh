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

from="${1:-}"
to="${2:-}"

if [[ -z "${from}" ]] || [[ -z "${to}" ]]; then
    echo "Usage: node-snapshot migrate <from> <to>" >&2
    echo "Example: node-snapshot migrate iron jod" >&2
    exit 1
fi

lock_file="${STATE_DIR}/lts-${from}.lock.json"
if [[ ! -f "${lock_file}" ]]; then
    echo "error: no lock file for lts/${from} at ${lock_file}" >&2
    echo "Run 'node-snapshot snapshot ${from}' first." >&2
    exit 1
fi

nvm use "lts/${to}" >/dev/null 2>&1
to_version="$(node -v | tr -d 'v')"
echo "→ nvm use lts/${to} (v${to_version})"

if [[ "${from}" == "${to}" ]]; then
    echo "→ Installing packages from lts/${to} lock into v${to_version}"
else
    echo "→ Installing packages from lts/${from} lock into lts/${to} (v${to_version})"
fi
source_version="$(jq -r '.node_version // ""' "${lock_file}")"
target_modules="$(npm root -g)"
# Resolve and validate every source first so a missing local package
# cannot leave the destination partially migrated.
install_specs=()
while IFS="=" read -r pkg version; do
    [[ -z "${pkg}" ]] && continue
    install_spec="${pkg}@${version}"
    if [[ "${version}" == file:* ]]; then
        install_spec="${version}"
    else
        # Recover local sources from legacy locks that recorded only a version.
        for modules_dir in "${NVM_DIR}/versions/node/v${source_version}/lib/node_modules" "${target_modules}"; do
            # Skip broken links so a valid destination link can still be used.
            if [[ -L "${modules_dir}/${pkg}" && -d "${modules_dir}/${pkg}" ]]; then
                source_path="$(cd "${modules_dir}/${pkg}" && pwd -P)"
                install_spec="file:${source_path}"
                break
            fi
        done
    fi
    if [[ "${install_spec}" == file:* ]] && [[ ! -f "${install_spec#file:}/package.json" ]]; then
        echo "error: local package source not found for ${pkg}: ${install_spec#file:}" >&2
        exit 1
    fi
    install_specs+=("${install_spec}")
done < <(jq -r '.packages | to_entries[] | "\(.key)=\(.value)"' "${lock_file}" || true)

for install_spec in ${install_specs[@]+"${install_specs[@]}"}; do
    echo "  npm install -g ${install_spec}"
    npm install -g "${install_spec}"
done

"${_self_dir}/snapshot.sh" "${to}"
