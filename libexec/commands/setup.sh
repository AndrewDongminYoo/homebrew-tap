#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-${HOME}/.local/share/brew-snapshot}"

# Find plist template: from share/ relative to this script
_commands_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_share_dir="${_commands_dir}/../../share"

PLIST_TEMPLATE="${_share_dir}/brew-snapshot.plist.template"

if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  echo "Error: plist template not found at ${PLIST_TEMPLATE}" >&2
  exit 1
fi

PLIST_DEST="${HOME}/Library/LaunchAgents/com.${USER}.brew-snapshot.plist"
BREW_SNAPSHOT_BIN="$(command -v brew-snapshot || echo "${_commands_dir}/../../bin/brew-snapshot")"

mkdir -p "${HOME}/Library/LaunchAgents"

sed \
  -e "s|__USER__|${USER}|g" \
  -e "s|__STATE_DIR__|${STATE_DIR}|g" \
  -e "s|__BIN__|${BREW_SNAPSHOT_BIN}|g" \
  "${PLIST_TEMPLATE}" > "${PLIST_DEST}"

launchctl unload "${PLIST_DEST}" 2>/dev/null || true
launchctl load "${PLIST_DEST}"

echo "✓ LaunchAgent registered: ${PLIST_DEST}"
echo "  brew-snapshot snapshot will run automatically on next login."
