#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-${HOME}/.local/share/brew-snapshot}"

# Find plist template.
# Homebrew installs it under share/brew-snapshot/ (via `(share/"brew-snapshot").install`).
# When running from the source repo the file sits directly under share/.
_commands_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_share_dir="${_commands_dir}/../../../share"

PLIST_TEMPLATE="${_share_dir}/brew-snapshot/brew-snapshot.plist.template"
if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  PLIST_TEMPLATE="${_share_dir}/brew-snapshot.plist.template"
fi

if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  echo "Error: plist template not found at ${PLIST_TEMPLATE}" >&2
  exit 1
fi

PLIST_DEST="${HOME}/Library/LaunchAgents/com.${USER}.brew-snapshot.plist"
BREW_SNAPSHOT_BIN="$(command -v brew-snapshot || echo "${_commands_dir}/../../../bin/brew-snapshot")"

# launchd starts agents with PATH=/usr/bin:/bin:/usr/sbin:/sbin, which has no Homebrew,
# so record the directory that holds brew now. A relative PATH entry gives a relative
# result, and the agent starts in another directory, so make it absolute.
BREW_BIN="$(command -v brew || true)"
if [[ -z "${BREW_BIN}" ]]; then
  echo "Error: brew not found on PATH" >&2
  exit 1
fi
LAUNCHD_PATH="$(cd "$(dirname "${BREW_BIN}")" && pwd):/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "${HOME}/Library/LaunchAgents"

# plutil writes each value as a plist string, so a path may hold any character,
# including the & and | that a sed replacement would interpret.
cp "${PLIST_TEMPLATE}" "${PLIST_DEST}"
# launchd does not read the login shell's exports, so pass the state dir that the log paths use.
plutil -replace EnvironmentVariables.BREW_SNAPSHOT_DIR -string "${STATE_DIR}" "${PLIST_DEST}"
plutil -replace EnvironmentVariables.PATH -string "${LAUNCHD_PATH}" "${PLIST_DEST}"
plutil -replace Label -string "com.${USER}.brew-snapshot" "${PLIST_DEST}"
# -replace on an array index inserts before that element, so remove the placeholder first.
plutil -remove ProgramArguments.0 "${PLIST_DEST}"
plutil -insert ProgramArguments.0 -string "${BREW_SNAPSHOT_BIN}" "${PLIST_DEST}"
plutil -replace StandardErrorPath -string "${STATE_DIR}/snapshot.stderr.log" "${PLIST_DEST}"
plutil -replace StandardOutPath -string "${STATE_DIR}/snapshot.stdout.log" "${PLIST_DEST}"

launchctl unload "${PLIST_DEST}" 2>/dev/null || true
launchctl load "${PLIST_DEST}"

echo "✓ LaunchAgent registered: ${PLIST_DEST}"
echo "  brew-snapshot snapshot will run automatically on next login."
