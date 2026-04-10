#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-$HOME/.local/share/brew-snapshot}"
mkdir -p "$STATE_DIR"

GREEDY=false
for arg in "$@"; do
  [[ "$arg" == "--greedy" ]] && GREEDY=true
done

echo "→ brew update"
brew update

if $GREEDY; then
  echo "→ brew upgrade --greedy"
  brew upgrade --greedy
else
  echo "→ brew upgrade"
  brew upgrade
fi

echo "→ Brewfile"
brew bundle dump --file="$STATE_DIR/Brewfile" --force

echo "→ Brewfile.lock"
brew info --json=v2 --installed > "$STATE_DIR/Brewfile.lock"

echo "→ Brewfile.deps"
brew deps --tree --installed > "$STATE_DIR/Brewfile.deps"

echo "→ Brewfile.taps"
brew tap > "$STATE_DIR/Brewfile.taps"

echo "→ Brewfile.refs"
: > "$STATE_DIR/Brewfile.refs"
while IFS= read -r tap; do
  repo="$(brew --repository "$tap" 2>/dev/null || true)"
  if [[ -n "$repo" && -d "$repo/.git" ]]; then
    printf "%s %s\n" "$tap" "$(git -C "$repo" rev-parse HEAD)" >> "$STATE_DIR/Brewfile.refs"
  fi
done < "$STATE_DIR/Brewfile.taps"

echo "→ last_snapshot_utc"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_DIR/last_snapshot_utc"

echo ""
echo "✓ Snapshot complete → $STATE_DIR"
