#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-${HOME}/.local/share/brew-snapshot}"

if [[ ! -d "${STATE_DIR}" ]]; then
  echo "No snapshot found. Run 'brew-snapshot snapshot' first."
  exit 0
fi

echo "State directory: ${STATE_DIR}"
echo ""

if [[ -f "${STATE_DIR}/last_snapshot_utc" ]]; then
  echo "Last snapshot:  $(cat "${STATE_DIR}/last_snapshot_utc")"
else
  echo "Last snapshot:  (none)"
fi

echo ""

formula_count=0
cask_count=0
tap_count=0

if [[ -f "${STATE_DIR}/Brewfile" ]]; then
  formula_count=$(grep -c "^brew "  "${STATE_DIR}/Brewfile" 2>/dev/null || echo 0)
  cask_count=$(grep -c    "^cask "  "${STATE_DIR}/Brewfile" 2>/dev/null || echo 0)
fi

if [[ -f "${STATE_DIR}/Brewfile.taps" ]]; then
  tap_count=$(wc -l < "${STATE_DIR}/Brewfile.taps" | tr -d ' ')
fi

echo "Formulae:       ${formula_count}"
echo "Casks:          ${cask_count}"
echo "Taps:           ${tap_count}"
