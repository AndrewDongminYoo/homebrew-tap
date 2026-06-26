# node-snapshot Design

**Date:** 2026-05-05
**Status:** Approved

## Summary

A new `node-snapshot` CLI tool, co-located in the `brew-snapshot` Homebrew tap repository, that manages nvm LTS Node.js versions and their global npm packages. It replaces the `nodecheck()` zsh function with a `chpwd`-hook-based shell integration and adds lifecycle management: version tracking, update notifications, package snapshotting, and cross-version migration.

---

## 1. Repository Structure

```plaintext
brew-snapshot/
├── bin/
│   ├── brew-snapshot              (existing)
│   └── node-snapshot              (new)
├── libexec/
│   ├── commands/                  (existing brew-snapshot subcommands)
│   └── node-snapshot/
│       └── commands/
│           ├── init.sh            ← outputs shell function definitions to stdout
│           ├── snapshot.sh        ← saves global packages per LTS alias to lock file
│           ├── upgrade.sh         ← installs latest LTS + migrates + re-snapshots
│           ├── migrate.sh         ← copies packages from one alias to another
│           ├── consolidate.sh     ← merges packages across all patch versions into latest
│           └── status.sh          ← shows tracked versions, lock state, last check
├── Formula/
│   ├── brew-snapshot.rb           (existing)
│   └── node-snapshot.rb           (new)
└── share/
    └── brew-snapshot.plist.template (existing)
```

The dispatcher pattern (`bin/ → libexec/.../commands/*.sh` via `exec`) is identical to `brew-snapshot`.

---

## 2. State Directory

Default: `~/.local/share/node-snapshot/`
Override: `export NODE_SNAPSHOT_DIR=/your/path`

```plaintext
~/.local/share/node-snapshot/
├── config.json
├── lts-iron.lock.json
├── lts-jod.lock.json
├── lts-krypton.lock.json
└── last_snapshot_utc
```

---

## 3. Config Schema

`config.json`:

```json
{
  "tracked": ["iron", "jod", "krypton"],
  "check_interval_days": 7,
  "last_check_utc": "2026-05-05T00:00:00Z"
}
```

- `tracked`: nvm LTS alias list. Default: `["iron", "jod", "krypton"]`.
- `check_interval_days`: Minimum days between remote version checks. Default: `7`.
- `last_check_utc`: ISO-8601 UTC timestamp written by `upgrade --check`.

Config is created with defaults on first run if absent.

---

## 4. Lock File Schema

`lts-<alias>.lock.json`:

```json
{
  "lts_alias": "iron",
  "node_version": "20.19.1",
  "snapshot_utc": "2026-05-05T00:00:00Z",
  "packages": {
    "typescript": "5.4.5",
    "eslint": "9.2.0",
    "pnpm": "9.1.0"
  }
}
```

Only user-installed top-level global packages are recorded (not npm's own bundled dependencies).

---

## 5. Shell Integration

> **Requirement:** zsh only. The `add-zsh-hook chpwd` mechanism is zsh-specific. bash users can install the CLI and use all subcommands, but auto-switching on `cd` is not available.

Add to `.zshrc`:

```shellscript
source <(node-snapshot init)
```

`init.sh` writes to stdout:

```shellscript
_node_snapshot_chpwd() {
    local node_file=""
    [[ -f ".node-version" ]] && node_file=".node-version"
    [[ -f ".nvmrc"        ]] && node_file=".nvmrc"

    if [[ -n "${node_file}" ]]; then
        nvm use "$(cat "${node_file}")" --silent
    fi

    if [[ ! -f "package.json" ]] && [[ -z "${node_file}" ]]; then
        return
    fi

    # print node version, npm version, and detected package manager
    local node_v npm_v pm pm_field ver msg
    node_v="$(node -v 2>/dev/null || echo '?')"
    npm_v="$(npm -v 2>/dev/null || echo '?')"
    pm=""

    if [[ -f package.json ]]; then
        pm_field="$(node -p "require('./package.json').packageManager||''" 2>/dev/null || true)"
        [[ -n "${pm_field}" ]] && pm="${pm_field%%@*}"
    fi

    if [[ -z "${pm}" ]]; then
        [[ -f pnpm-lock.yaml      ]] && pm="pnpm"
        [[ -f bun.lockb           ]] && pm="bun"
        [[ -f yarn.lock           ]] && pm="yarn"
        [[ -f .yarnrc.yml         ]] && pm="yarn"
        [[ -f package-lock.json   ]] && pm="npm"
    fi

    msg="node ${node_v} npm: v${npm_v}"
    case "${pm}" in
        pnpm) msg="${msg} pnpm: v$(pnpm -v 2>/dev/null || echo '?')" ;;
        bun)  msg="${msg} bun: v$(bun -v 2>/dev/null || echo '?')"   ;;
        yarn)
            local yv; yv="$(yarn -v 2>/dev/null || echo '')"
            case "${yv}" in
                2.*) ver="Berry2" ;; 3.*) ver="Berry3" ;; *) ver="Classic" ;;
            esac
            msg="${msg} yarn: v${yv} (${ver})"
            ;;
    esac
    printf '%s\n' "${msg}"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _node_snapshot_chpwd
_node_snapshot_chpwd

(node-snapshot upgrade --check 2>/dev/null &)
```

Key behaviors:

- `chpwd` hook fires on every `cd`, replacing the manual `nodecheck()` call.
- `upgrade --check` runs asynchronously in a subshell — no shell startup latency.

---

## 6. Runtime Requirements for libexec Scripts

`nvm` is a shell function, not a standalone binary. Every libexec script that calls `nvm` must source it explicitly at the top of the script:

```shellscript
# Source nvm — required because libexec scripts run in a fresh bash process
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
[[ -s "${NVM_DIR}/nvm.sh" ]] && \. "${NVM_DIR}/nvm.sh"
```

If `nvm.sh` is not found the script must exit with a clear error message rather than silently failing.

---

## 7. Subcommands

### `node-snapshot init`

Writes shell function definitions to stdout. No side effects.

### `node-snapshot snapshot [alias]`

For each tracked alias (or the specified one):

1. `nvm use lts/<alias>` (resolves to the newest installed version of that LTS line)
2. `npm list -g --depth=0 --json` → extract top-level packages
3. Filter out `npm` and `corepack` (bundled with Node, not user-installed)
4. Guard against accidental loss before writing the lock:
   - **Full wipe** (live set empty, existing lock non-empty): refuse and exit non-zero unless `--force`. Protects against snapshotting a freshly installed, not-yet-migrated Node version over a populated lock.
   - **Partial drop** (some packages removed): record it, but print a warning listing the dropped packages.
5. Write `lts-<alias>.lock.json`
6. Update `last_snapshot_utc`

### `node-snapshot upgrade [alias] [--check]`

`--check` mode (non-interactive, called from shell init):

1. Read `last_check_utc` from config. Skip if within `check_interval_days`.
2. For each tracked alias: `nvm ls-remote lts/<alias> --no-colors | tail -1` to get remote latest.
3. Compare with `nvm ls lts/<alias>` (locally installed).
4. Print notification for any outdated alias:
   ```plaintext
   [node-snapshot] lts/iron update available: 20.18.0 → 20.19.1
   Run: node-snapshot upgrade iron
   ```
5. Update `last_check_utc` in config.

Without `--check` (interactive):

1. Resolve the remote target via `nvm version-remote lts/<alias>`. On a version bump, run `nvm install lts/<alias> --latest-npm --reinstall-packages-from=<old version>` so the new version inherits the old globals. The flag is omitted when there is no bump, since nvm refuses to reinstall from the version it is installing.
2. If new version differs from lock file's `node_version`: run `migrate <old> <alias>`
3. Run `snapshot <alias>`

### `node-snapshot migrate <from> <to>`

1. Read `lts-<from>.lock.json` packages.
2. `nvm use lts/<to>`
3. `npm install -g <name>@<version>` for each package.
4. Run `snapshot <to>`

### `node-snapshot consolidate [alias]`

Solves the problem where successive patch-version installs (e.g. v22.21.1 → v22.22.0 → v22.22.2) accumulate packages only in the version where they were originally installed. The latest patch often ends up the most bare.

For each tracked alias (or the specified one):

1. Read `~/.nvm/alias/lts/<alias>` to determine the major (e.g. `20`) and the current target version.
2. Find all installed directories matching `~/.nvm/versions/node/v<major>.*` and sort them oldest → newest via `sort -V`.
3. For each patch version, scan `lib/node_modules/` directly from disk (no nvm activation). Handle `@scope/pkg` subdirectory layout. Exclude `npm` and `corepack`.
4. Merge the package list: when the same package appears in multiple patch versions, the newest patch version's version wins.
5. `nvm use lts/<alias>`, then `npm install -g <pkg>@<ver>` for any package not already present at the target version.
6. Run `snapshot <alias>` to update the lock file.

### `node-snapshot status`

Prints a table:

```plaintext
Node Snapshot — state: ~/.local/share/node-snapshot
Last check:   2026-05-04T10:00:00Z

Alias    Installed    Lock version   Status
iron     20.19.1      20.18.0        ⚠ outdated
jod      22.14.0      22.14.0        ✓ up-to-date
krypton  24.1.0       (none)         – not snapshotted
```

---

## 8. `bin/node-snapshot` Dispatcher

Mirrors `bin/brew-snapshot` exactly:

```shellscript
#!/usr/bin/env bash
set -euo pipefail

NODE_SNAPSHOT_VERSION="0.1.0"
export NODE_SNAPSHOT_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBEXEC_DIR="${_self}/../libexec/node-snapshot/commands"

cmd="${1:-help}"
shift 2>/dev/null || true

case "${cmd}" in
  init)        exec "${LIBEXEC_DIR}/init.sh"        "$@" ;;
  snapshot)    exec "${LIBEXEC_DIR}/snapshot.sh"    "$@" ;;
  upgrade)     exec "${LIBEXEC_DIR}/upgrade.sh"     "$@" ;;
  migrate)     exec "${LIBEXEC_DIR}/migrate.sh"     "$@" ;;
  consolidate) exec "${LIBEXEC_DIR}/consolidate.sh" "$@" ;;
  status)      exec "${LIBEXEC_DIR}/status.sh"      "$@" ;;
  --version|-V)
    echo "node-snapshot ${NODE_SNAPSHOT_VERSION}"
    ;;
  help|--help|-h|"")
    echo "Usage: node-snapshot <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init                   Output shell integration (add: source <(node-snapshot init))"
    echo "  snapshot [alias]       Save global packages for tracked LTS versions"
    echo "  upgrade [alias]        Update LTS to latest and migrate packages"
    echo "  upgrade --check        Check for updates without installing"
    echo "  migrate <from> <to>    Copy packages from one LTS alias to another"
    echo "  consolidate [alias]    Merge packages across all patch versions into the latest"
    echo "  status                 Show tracked versions and lock file state"
    echo ""
    echo "State directory: ${NODE_SNAPSHOT_DIR}"
    ;;
  *)
    echo "node-snapshot: unknown command '${cmd}'" >&2
    echo "Run 'node-snapshot help' for usage." >&2
    exit 1
    ;;
esac
```

---

## 9. `Formula/node-snapshot.rb`

```ruby
class NodeSnapshot < Formula
  desc "Manage nvm LTS versions and global npm packages with snapshots"
  homepage "https://github.com/AndrewDongminYoo/homebrew-tap"
  url "https://github.com/AndrewDongminYoo/homebrew-tap/archive/refs/tags/v0.4.0.tar.gz"
  sha256 ""   # filled after release tag
  version "0.4.0"
  license "MIT"

  head "https://github.com/AndrewDongminYoo/homebrew-tap.git", branch: "main"

  def install
    bin.install "bin/node-snapshot"
    (libexec/"node-snapshot"/"commands").install Dir["libexec/node-snapshot/commands/*"]

    inreplace bin/"node-snapshot",
      %r{\$\{_self\}/\.\./libexec/node-snapshot/commands},
      "#{opt_libexec}/node-snapshot/commands"
  end

  def caveats
    <<~EOS
      Add shell integration to your .zshrc:
        source <(node-snapshot init)

      Default state directory: ~/.local/share/node-snapshot/
      Override: export NODE_SNAPSHOT_DIR=/your/path
    EOS
  end

  test do
    assert_match "Usage: node-snapshot", shell_output("#{bin}/node-snapshot help")
    assert_match "Usage: node-snapshot", shell_output("#{bin}/node-snapshot --help")
    assert_match "node-snapshot",        shell_output("#{bin}/node-snapshot --version")
    assert_match "unknown command",      shell_output("#{bin}/node-snapshot bogus 2>&1", 1)

    ENV["NODE_SNAPSHOT_DIR"] = (testpath/"state").to_s
    assert_match "No snapshot found",    shell_output("#{bin}/node-snapshot status")
  end
end
```

---

## 10. Testing Strategy

| Layer              | What                                    | How                                                          |
| ------------------ | --------------------------------------- | ------------------------------------------------------------ |
| Formula test       | help / version / unknown / empty status | `brew test` — no nvm required                                |
| Shell integration  | `_node_snapshot_chpwd` defined          | `bash -c "$(node-snapshot init); type _node_snapshot_chpwd"` |
| snapshot / migrate | lock file written correctly             | integration test with real nvm                               |
| upgrade --check    | notification output                     | mock `nvm ls-remote` with a fixture file                     |

nvm-dependent tests are excluded from `formula test do` and live in a separate `test/integration/` script.

---

## 11. Out of Scope

- Automatic launchd scheduling (can be added later via a `setup` subcommand)
- `node-snapshot track` / `untrack` commands (config.json is edited manually or via future subcommand)
- Support for non-LTS Node versions
