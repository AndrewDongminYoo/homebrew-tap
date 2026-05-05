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

echo "→ nvm use lts/${to}"
nvm use "lts/${to}" >/dev/null 2>&1

echo "→ Installing packages from lts/${from} lock into lts/${to}"
while IFS="=" read -r pkg version; do
    [[ -z "${pkg}" ]] && continue
    echo "  npm install -g ${pkg}@${version}"
    npm install -g "${pkg}@${version}"
done < <(jq -r '.packages | to_entries[] | "\(.key)=\(.value)"' "${lock_file}")

"${_self_dir}/snapshot.sh" "${to}"
