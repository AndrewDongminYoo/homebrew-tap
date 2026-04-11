# brew-snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/Development/01_personal/brew-snapshot`에 Homebrew tap으로 배포 가능한 `brew-snapshot` CLI 툴을 구현한다.

**Architecture:** `bin/brew-snapshot` 진입점이 서브커맨드를 `libexec/commands/` 아래 개별 스크립트로 dispatch한다. 상태 파일은 `~/.local/share/brew-snapshot/`(또는 `$BREW_SNAPSHOT_DIR`)에 저장되며, 툴 소스와 분리된 순수 데이터 폴더로 운영된다.

**Tech Stack:** Bash, Homebrew Bundle, launchd

---

## File Map

| 파일                                 | 역할                            |
| ------------------------------------ | ------------------------------- |
| `bin/brew-snapshot`                  | 진입점, 서브커맨드 dispatch     |
| `libexec/commands/snapshot.sh`       | snapshot 서브커맨드             |
| `libexec/commands/restore.sh`        | restore 서브커맨드              |
| `libexec/commands/status.sh`         | status 서브커맨드               |
| `libexec/commands/setup.sh`          | setup 서브커맨드 (launchd 등록) |
| `share/brew-snapshot.plist.template` | launchd plist 템플릿            |
| `Formula/brew-snapshot.rb`           | Homebrew formula                |
| `README.md`                          | 사용자 문서                     |
| `CLAUDE.md`                          | Claude Code 안내                |

---

## Task 1: 레포 초기화

**Files:**

- Create: `~/Development/01_personal/brew-snapshot/` (git repo)

- [ ] **Step 1: 디렉토리 생성 및 git 초기화**

```bash
mkdir -p ~/Development/01_personal/brew-snapshot
cd ~/Development/01_personal/brew-snapshot
git init
mkdir -p bin libexec/commands share Formula
```

- [ ] **Step 2: .gitignore 작성**

`~/Development/01_personal/brew-snapshot/.gitignore`:

```plaintext
.DS_Store
*.log
```

- [ ] **Step 3: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add .gitignore
git commit -m "chore: initialize brew-snapshot repository"
```

Expected: `[main (root-commit) xxxxxxx] chore: initialize brew-snapshot repository`

---

## Task 2: 진입점 `bin/brew-snapshot`

**Files:**

- Create: `bin/brew-snapshot`

- [ ] **Step 1: 파일 작성**

`bin/brew-snapshot`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BREW_SNAPSHOT_VERSION="0.1.0"
export BREW_SNAPSHOT_DIR="${BREW_SNAPSHOT_DIR:-$HOME/.local/share/brew-snapshot}"

# libexec 위치: Homebrew 설치 시 $(brew --prefix)/libexec/brew-snapshot/commands
# 로컬 개발 시 이 스크립트 기준 ../libexec/commands
_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBEXEC_DIR="$_self/../libexec/commands"

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
  snapshot) exec "$LIBEXEC_DIR/snapshot.sh" "$@" ;;
  restore)  exec "$LIBEXEC_DIR/restore.sh"  "$@" ;;
  status)   exec "$LIBEXEC_DIR/status.sh"   "$@" ;;
  setup)    exec "$LIBEXEC_DIR/setup.sh"    "$@" ;;
  --version|-V)
    echo "brew-snapshot $BREW_SNAPSHOT_VERSION"
    ;;
  help|--help|-h|"")
    echo "Usage: brew-snapshot <command> [options]"
    echo ""
    echo "Commands:"
    echo "  snapshot [--greedy]  Update Homebrew and save current state"
    echo "  restore              Reinstall packages from Brewfile"
    echo "  status               Show last snapshot time and package counts"
    echo "  setup                Register launchd agent for automatic snapshots"
    echo "  help                 Show this help"
    echo ""
    echo "State directory: \${BREW_SNAPSHOT_DIR:-~/.local/share/brew-snapshot}"
    ;;
  *)
    echo "brew-snapshot: unknown command '$cmd'" >&2
    echo "Run 'brew-snapshot help' for usage." >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x ~/Development/01_personal/brew-snapshot/bin/brew-snapshot
```

- [ ] **Step 3: 동작 확인**

```bash
~/Development/01_personal/brew-snapshot/bin/brew-snapshot help
```

Expected:

```plaintext
Usage: brew-snapshot <command> [options]

Commands:
  snapshot [--greedy]  Update Homebrew and save current state
  ...
```

- [ ] **Step 4: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add bin/brew-snapshot
git commit -m "feat: add entry point with subcommand dispatch"
```

---

## Task 3: `snapshot` 서브커맨드

**Files:**

- Create: `libexec/commands/snapshot.sh`

- [ ] **Step 1: 파일 작성**

`libexec/commands/snapshot.sh`:

```bash
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
```

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x ~/Development/01_personal/brew-snapshot/libexec/commands/snapshot.sh
```

- [ ] **Step 3: 동작 확인 (dry run — 실제 upgrade 없이 경로만 확인)**

```bash
BREW_SNAPSHOT_DIR=/tmp/brew-snapshot-test \
  ~/Development/01_personal/brew-snapshot/bin/brew-snapshot snapshot
```

Expected: `~/.local/share/brew-snapshot/` 또는 `/tmp/brew-snapshot-test/` 아래 `Brewfile`, `Brewfile.lock`, `Brewfile.deps`, `Brewfile.taps`, `Brewfile.refs`, `last_snapshot_utc` 생성 확인

```bash
ls /tmp/brew-snapshot-test/
```

Expected:

```plaintext
Brewfile  Brewfile.deps  Brewfile.lock  Brewfile.refs  Brewfile.taps  last_snapshot_utc
```

- [ ] **Step 4: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add libexec/commands/snapshot.sh
git commit -m "feat: implement snapshot subcommand"
```

---

## Task 4: `restore` 서브커맨드

**Files:**

- Create: `libexec/commands/restore.sh`

- [ ] **Step 1: 파일 작성**

`libexec/commands/restore.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-$HOME/.local/share/brew-snapshot}"
BREWFILE="$STATE_DIR/Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
  echo "Error: No Brewfile found at $BREWFILE" >&2
  echo "Run 'brew-snapshot snapshot' first." >&2
  exit 1
fi

echo "→ Installing from $BREWFILE"
brew bundle --file="$BREWFILE"

echo ""
echo "✓ Restore complete."
echo ""
echo "To check version differences against the last snapshot:"
echo "  jq '.formulae[] | {name, version: .installed[0].version}' $STATE_DIR/Brewfile.lock"
```

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x ~/Development/01_personal/brew-snapshot/libexec/commands/restore.sh
```

- [ ] **Step 3: 에러 경로 확인**

```bash
BREW_SNAPSHOT_DIR=/tmp/nonexistent-dir \
  ~/Development/01_personal/brew-snapshot/bin/brew-snapshot restore
```

Expected:

```plaintext
Error: No Brewfile found at /tmp/nonexistent-dir/Brewfile
Run 'brew-snapshot snapshot' first.
```

Exit code: 1

- [ ] **Step 4: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add libexec/commands/restore.sh
git commit -m "feat: implement restore subcommand"
```

---

## Task 5: `status` 서브커맨드

**Files:**

- Create: `libexec/commands/status.sh`

- [ ] **Step 1: 파일 작성**

`libexec/commands/status.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-$HOME/.local/share/brew-snapshot}"

if [[ ! -d "$STATE_DIR" ]]; then
  echo "No snapshot found. Run 'brew-snapshot snapshot' first."
  exit 0
fi

echo "State directory: $STATE_DIR"
echo ""

if [[ -f "$STATE_DIR/last_snapshot_utc" ]]; then
  echo "Last snapshot:  $(cat "$STATE_DIR/last_snapshot_utc")"
else
  echo "Last snapshot:  (none)"
fi

echo ""

formula_count=0
cask_count=0
tap_count=0

if [[ -f "$STATE_DIR/Brewfile" ]]; then
  formula_count=$(grep -c "^brew "  "$STATE_DIR/Brewfile" 2>/dev/null || echo 0)
  cask_count=$(grep -c    "^cask "  "$STATE_DIR/Brewfile" 2>/dev/null || echo 0)
fi

if [[ -f "$STATE_DIR/Brewfile.taps" ]]; then
  tap_count=$(wc -l < "$STATE_DIR/Brewfile.taps")
fi

echo "Formulae:       $formula_count"
echo "Casks:          $cask_count"
echo "Taps:           $tap_count"
```

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x ~/Development/01_personal/brew-snapshot/libexec/commands/status.sh
```

- [ ] **Step 3: 동작 확인 (Task 3에서 만든 테스트 디렉토리 사용)**

```bash
BREW_SNAPSHOT_DIR=/tmp/brew-snapshot-test \
  ~/Development/01_personal/brew-snapshot/bin/brew-snapshot status
```

Expected (값은 환경마다 다름):

```plaintext
State directory: /tmp/brew-snapshot-test

Last snapshot:  2026-04-10T...Z

Formulae:       37
Casks:          6
Taps:           4
```

- [ ] **Step 4: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add libexec/commands/status.sh
git commit -m "feat: implement status subcommand"
```

---

## Task 6: `setup` 서브커맨드 + plist 템플릿

**Files:**

- Create: `share/brew-snapshot.plist.template`
- Create: `libexec/commands/setup.sh`

- [ ] **Step 1: plist 템플릿 작성**

`share/brew-snapshot.plist.template`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.__USER__.brew-snapshot</string>
    <key>ProgramArguments</key>
    <array>
      <string>__BIN__</string>
      <string>snapshot</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>__STATE_DIR__/snapshot.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>__STATE_DIR__/snapshot.stderr.log</string>
  </dict>
</plist>
```

- [ ] **Step 2: setup.sh 작성**

`libexec/commands/setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BREW_SNAPSHOT_DIR:-$HOME/.local/share/brew-snapshot}"

# Homebrew 설치 경로에서 템플릿 찾기; 로컬 개발 시 소스 기준 fallback
_commands_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_share_dir="$_commands_dir/../../share"

PLIST_TEMPLATE="$_share_dir/brew-snapshot.plist.template"

if [[ ! -f "$PLIST_TEMPLATE" ]]; then
  echo "Error: plist template not found at $PLIST_TEMPLATE" >&2
  exit 1
fi

PLIST_DEST="$HOME/Library/LaunchAgents/com.$USER.brew-snapshot.plist"
BREW_SNAPSHOT_BIN="$(command -v brew-snapshot || echo "$_commands_dir/../../bin/brew-snapshot")"

mkdir -p "$HOME/Library/LaunchAgents"

sed \
  -e "s|__USER__|$USER|g" \
  -e "s|__STATE_DIR__|$STATE_DIR|g" \
  -e "s|__BIN__|$BREW_SNAPSHOT_BIN|g" \
  "$PLIST_TEMPLATE" > "$PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

echo "✓ LaunchAgent registered: $PLIST_DEST"
echo "  brew-snapshot snapshot will run automatically on next login."
```

- [ ] **Step 3: 실행 권한 부여**

```bash
chmod +x ~/Development/01_personal/brew-snapshot/libexec/commands/setup.sh
```

- [ ] **Step 4: plist 생성 확인 (launchctl load는 선택)**

```bash
BREW_SNAPSHOT_DIR=/tmp/brew-snapshot-test \
  ~/Development/01_personal/brew-snapshot/bin/brew-snapshot setup
```

Expected:

```plaintext
✓ LaunchAgent registered: ~/Library/LaunchAgents/com.<username>.brew-snapshot.plist
```

생성된 plist 확인:

```bash
cat ~/Library/LaunchAgents/com.$USER.brew-snapshot.plist
```

Expected: `__USER__`, `__STATE_DIR__`, `__BIN__` 자리표시자가 실제 값으로 치환되어 있음.

- [ ] **Step 5: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add share/brew-snapshot.plist.template libexec/commands/setup.sh
git commit -m "feat: implement setup subcommand with launchd registration"
```

---

## Task 7: Homebrew Formula

**Files:**

- Create: `Formula/brew-snapshot.rb`

- [ ] **Step 1: formula 작성**

`Formula/brew-snapshot.rb`:

```ruby
class BrewSnapshot < Formula
  desc "Snapshot and restore your Homebrew environment"
  homepage "https://github.com/AndrewDongminYoo/homebrew-brew-snapshot"
  # url과 sha256은 GitHub release 태그 생성 후 채운다
  # url "https://github.com/AndrewDongminYoo/homebrew-brew-snapshot/archive/refs/tags/v0.1.0.tar.gz"
  # sha256 "..."
  version "0.1.0"
  license "MIT"

  def install
    bin.install "bin/brew-snapshot"
    (libexec/"commands").install Dir["libexec/commands/*"]
    (share/"brew-snapshot").install "share/brew-snapshot.plist.template"

    # bin/brew-snapshot 내 LIBEXEC_DIR 경로를 Homebrew 설치 경로로 고정
    inreplace bin/"brew-snapshot",
      %r{_self/\.\./libexec/commands},
      "#{libexec}/commands"
  end

  def caveats
    <<~EOS
      Run setup to enable automatic snapshots on login:
        brew-snapshot setup

      Default state directory: ~/.local/share/brew-snapshot/
      Override:  export BREW_SNAPSHOT_DIR=/your/path
    EOS
  end

  test do
    output = shell_output("#{bin}/brew-snapshot help")
    assert_match "Usage: brew-snapshot", output
  end
end
```

- [ ] **Step 2: formula 로컬 테스트 (tap 없이 직접)**

```bash
cd ~/Development/01_personal/brew-snapshot
brew install --build-from-source Formula/brew-snapshot.rb
brew-snapshot help
```

Expected: help 텍스트 출력, exit 0

- [ ] **Step 3: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add Formula/brew-snapshot.rb
git commit -m "feat: add Homebrew formula"
```

---

## Task 8: README.md + CLAUDE.md

**Files:**

- Create: `README.md`
- Create: `CLAUDE.md`

- [ ] **Step 1: README.md 작성**

`README.md`:

````markdown
# brew-snapshot

Snapshot and restore your Homebrew environment.

## Install

```bash
brew tap AndrewDongminYoo/brew-snapshot
brew install brew-snapshot
brew-snapshot setup
```
````

## Usage

```bash
brew-snapshot snapshot           # save current Homebrew state
brew-snapshot snapshot --greedy  # also upgrade casks
brew-snapshot restore            # reinstall from Brewfile on a new Mac
brew-snapshot status             # show last snapshot info
brew-snapshot setup              # register launchd agent for login automation
```

## State Files

Stored in `~/.local/share/brew-snapshot/` (override: `$BREW_SNAPSHOT_DIR`):

| File                | Contents                           |
| ------------------- | ---------------------------------- |
| `Brewfile`          | Reinstall manifest (`brew bundle`) |
| `Brewfile.lock`     | Full version history JSON          |
| `Brewfile.deps`     | Dependency tree                    |
| `Brewfile.taps`     | Active taps                        |
| `Brewfile.refs`     | Tap git commit hashes              |
| `last_snapshot_utc` | Last snapshot timestamp            |

## Restore on a New Mac

```bash
brew-snapshot restore
```

For version-critical packages (e.g. `postgresql@17`), check `Brewfile.lock` for the
previous version and use a versioned formula or `brew extract` if needed.

## What This Tool Does Not Do

- Guarantee exact version reproduction for all packages
- Pin all formulae with `brew pin`
- Support non-macOS platforms

````

- [ ] **Step 2: CLAUDE.md 작성**

`CLAUDE.md`:

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A Homebrew tap providing the `brew-snapshot` CLI tool. Distributes shell scripts
via `brew install`; no build system or tests beyond the formula `test do` block.

## Architecture

`bin/brew-snapshot` dispatches to `libexec/commands/*.sh` via `exec`. Each subcommand
script is self-contained and reads `$BREW_SNAPSHOT_DIR` for the state path.

The formula's `inreplace` step rewrites the LIBEXEC_DIR path at install time so the
dispatch works correctly from the Homebrew prefix.

## State Directory

`~/.local/share/brew-snapshot/` — plain data folder, never a git repo.
All files are regeneratable by running `brew-snapshot snapshot`.

## Adding a Subcommand

1. Create `libexec/commands/<name>.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`
2. Add a `<name>)` case to `bin/brew-snapshot`
3. Add a line to the help text in `bin/brew-snapshot`

## Formula Maintenance

`url` and `sha256` in `Formula/brew-snapshot.rb` are filled after each GitHub release tag.
The `inreplace` block must be updated if the LIBEXEC_DIR detection logic in `bin/brew-snapshot` changes.
````

- [ ] **Step 3: 커밋**

```bash
cd ~/Development/01_personal/brew-snapshot
git add README.md CLAUDE.md
git commit -m "docs: add README and CLAUDE.md"
```

---

## Task 9: 기존 상태 파일 마이그레이션

기존 `~/.config/.my-brew/`의 스냅샷 데이터를 새 상태 디렉토리로 이전한다.

**Files:**

- Source: `~/.config/.my-brew/{Brewfile,Brewfile.lock,DEPS,TAPS,REFS}`
- Dest: `~/.local/share/brew-snapshot/`

- [ ] **Step 1: 새 상태 디렉토리 생성**

```bash
mkdir -p ~/.local/share/brew-snapshot
```

- [ ] **Step 2: 파일 복사 (이름 변경 포함)**

```bash
cp ~/.config/.my-brew/Brewfile       ~/.local/share/brew-snapshot/Brewfile
cp ~/.config/.my-brew/Brewfile.lock  ~/.local/share/brew-snapshot/Brewfile.lock
cp ~/.config/.my-brew/DEPS           ~/.local/share/brew-snapshot/Brewfile.deps
cp ~/.config/.my-brew/TAPS           ~/.local/share/brew-snapshot/Brewfile.taps
cp ~/.config/.my-brew/REFS           ~/.local/share/brew-snapshot/Brewfile.refs
```

- [ ] **Step 3: status로 마이그레이션 확인**

```bash
brew-snapshot status
```

Expected:

```plaintext
State directory: /Users/AndrewDongminYoo/.local/share/brew-snapshot

Last snapshot:  (none)

Formulae:       37
Casks:          6
Taps:           4
```

(`last_snapshot_utc`는 없어도 정상 — 다음 snapshot 실행 시 생성됨)

- [ ] **Step 4: 기존 snapshot.sh 제거 (선택)**

새 툴이 정상 동작하면 `~/.config/.my-brew/snapshot.sh`는 더 이상 필요 없다.
`init.md`, `README.md`, `CLAUDE.md`는 문서로 보존할 수 있다.

---

## Verification

모든 태스크 완료 후:

```bash
# 1) 진입점 동작 확인
brew-snapshot help
brew-snapshot --version

# 2) 상태 확인
brew-snapshot status

# 3) setup 확인
brew-snapshot setup
cat ~/Library/LaunchAgents/com.$USER.brew-snapshot.plist

# 4) snapshot 실행 (실제 upgrade 포함)
brew-snapshot snapshot
ls ~/.local/share/brew-snapshot/

# 5) formula 테스트
brew test brew-snapshot
```
