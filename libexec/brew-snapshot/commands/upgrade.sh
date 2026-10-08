#!/usr/bin/env bash
set -euo pipefail

_commands_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEDY=false
for arg in "$@"; do
  [[ "${arg}" == "--greedy" ]] && GREEDY=true
done

echo "→ brew update"
brew update

if ${GREEDY}; then
  echo "→ brew upgrade --greedy"
  brew upgrade --greedy
else
  echo "→ brew upgrade"
  brew upgrade
fi

exec "${_commands_dir}/snapshot.sh"
