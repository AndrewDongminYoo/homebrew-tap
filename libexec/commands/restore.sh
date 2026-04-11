#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-${HOME}/.local/share/brew-snapshot}"
BREWFILE="${STATE_DIR}/Brewfile"

if [[ ! -f "${BREWFILE}" ]]; then
  echo "Error: No Brewfile found at ${BREWFILE}" >&2
  echo "Run 'brew-snapshot snapshot' first." >&2
  exit 1
fi

echo "→ Installing from ${BREWFILE}"
brew bundle --file="${BREWFILE}"

echo ""
echo "✓ Restore complete."
echo ""
echo "To check version differences against the last snapshot:"
echo "  jq '.formulae[] | {name, version: .installed[0].version}' ${STATE_DIR}/Brewfile.lock"
