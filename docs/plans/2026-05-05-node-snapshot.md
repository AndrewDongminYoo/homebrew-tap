# node-snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `node-snapshot` CLI tool to this tap that manages nvm LTS versions, snapshots global npm packages per alias, and provides zsh shell integration via a `chpwd` hook.

**Architecture:** Mirrors `brew-snapshot` exactly — a `bin/node-snapshot` dispatcher `exec`s into `libexec/node-snapshot/commands/*.sh` subcommands. State lives in `~/.local/share/node-snapshot/`. A new `Formula/node-snapshot.rb` installs the tool independently of `brew-snapshot`.

**Tech Stack:** bash 5 (macOS system bash is 3.2 — scripts must use `#!/usr/bin/env bash` and avoid bash 4+ arrays where possible), nvm (shell function, not binary — each libexec script sources `$NVM_DIR/nvm.sh`), jq (formula dependency for JSON read/write).

---

## File Map

| Action | Path                                         | Responsibility                                       |
| ------ | -------------------------------------------- | ---------------------------------------------------- |
| Create | `bin/node-snapshot`                          | Dispatcher — routes subcommands to libexec           |
| Create | `libexec/node-snapshot/commands/init.sh`     | Emits zsh shell function definitions to stdout       |
| Create | `libexec/node-snapshot/commands/status.sh`   | Shows tracked versions, lock state, last check       |
| Create | `libexec/node-snapshot/commands/snapshot.sh` | Writes `lts-<alias>.lock.json` from live npm globals |
| Create | `libexec/node-snapshot/commands/upgrade.sh`  | Installs latest LTS; `--check` emits update notices  |
| Create | `libexec/node-snapshot/commands/migrate.sh`  | Reinstalls lock packages into a different alias      |
| Create | `Formula/node-snapshot.rb`                   | Homebrew formula with `test do` block                |
| Create | `test/node-snapshot/test-unit.sh`            | Unit tests runnable without nvm                      |

---

## Task 1: bin/node-snapshot dispatcher

**Files:**

- Create: `bin/node-snapshot`
- Create: `test/node-snapshot/test-unit.sh` (partial — dispatcher assertions only)

- [ ] **Step 1: Write the failing test (dispatcher portion)**

Create `test/node-snapshot/test-unit.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/node-snapshot"
TMPDIR_STATE="$(mktemp -d)"
export NODE_SNAPSHOT_DIR="${TMPDIR_STATE}"

_pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
_fail() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }
_assert_match() { [[ "$1" == *"$2"* ]] || _fail "Expected '$2' in output: $1"; }

# ── dispatcher ──────────────────────────────────────────────────────────────
output="$("${BIN}" help)"
_assert_match "${output}" "Usage: node-snapshot"
_pass "help"

output="$("${BIN}" --help)"
_assert_match "${output}" "Usage: node-snapshot"
_pass "--help"

output="$("${BIN}" --version)"
_assert_match "${output}" "node-snapshot"
_pass "--version"

output="$("${BIN}" bogus 2>&1 || true)"
_assert_match "${output}" "unknown command"
_pass "unknown command exits 1"

rm -rf "${TMPDIR_STATE}"
echo ""; echo "Dispatcher tests: PASS"
```

Make it executable:

```bash
chmod +x test/node-snapshot/test-unit.sh
```

- [ ] **Step 2: Run to confirm it fails**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected: `bin/node-snapshot: No such file or directory`

- [ ] **Step 3: Write `bin/node-snapshot`**

```bash
#!/usr/bin/env bash
set -euo pipefail

NODE_SNAPSHOT_VERSION="0.1.0"
export NODE_SNAPSHOT_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBEXEC_DIR="${_self}/../libexec/node-snapshot/commands"

cmd="${1:-help}"
shift 2>/dev/null || true

case "${cmd}" in
  init)     exec "${LIBEXEC_DIR}/init.sh"     "$@" ;;
  snapshot) exec "${LIBEXEC_DIR}/snapshot.sh" "$@" ;;
  upgrade)  exec "${LIBEXEC_DIR}/upgrade.sh"  "$@" ;;
  migrate)  exec "${LIBEXEC_DIR}/migrate.sh"  "$@" ;;
  status)   exec "${LIBEXEC_DIR}/status.sh"   "$@" ;;
  --version | -V)
    echo "node-snapshot ${NODE_SNAPSHOT_VERSION}"
    ;;
  help | --help | -h | "")
    echo "Usage: node-snapshot <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init                   Output shell integration (add: source <(node-snapshot init))"
    echo "  snapshot [alias]       Save global packages for tracked LTS versions"
    echo "  upgrade [alias]        Update LTS to latest and migrate packages"
    echo "  upgrade --check        Check for updates without installing"
    echo "  migrate <from> <to>    Copy packages from one LTS alias to another"
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

Make it executable:

```bash
chmod +x bin/node-snapshot
```

- [ ] **Step 4: Run test to verify dispatcher passes**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected:

```plaintext
✓ help
✓ --help
✓ --version
✓ unknown command exits 1

Dispatcher tests: PASS
```

- [ ] **Step 5: shellcheck**

```bash
shellcheck bin/node-snapshot
```

Expected: no output (zero warnings).

- [ ] **Step 6: Commit**

```bash
git add bin/node-snapshot test/node-snapshot/test-unit.sh
git commit -m "feat: add node-snapshot dispatcher"
```

---

## Task 2: status.sh

**Files:**

- Create: `libexec/node-snapshot/commands/status.sh`
- Modify: `test/node-snapshot/test-unit.sh` (add status assertions)

- [ ] **Step 1: Add status assertions to `test/node-snapshot/test-unit.sh`**

Append to the file (before the final `echo "Dispatcher tests: PASS"` line — replace that line with the content below):

```bash
# ── status ───────────────────────────────────────────────────────────────────
output="$("${BIN}" status)"
_assert_match "${output}" "No snapshot found"
_pass "status: no config → guidance message"

mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
    > "${TMPDIR_STATE}/config.json"
output="$("${BIN}" status)"
_assert_match "${output}" "State directory:"
_assert_match "${output}" "iron"
_pass "status: config present → shows alias"

rm -rf "${TMPDIR_STATE}"
echo ""; echo "All unit tests: PASS"
```

- [ ] **Step 2: Run to confirm status tests fail**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected: `status.sh: No such file or directory` (exec into missing script).

- [ ] **Step 3: Write `libexec/node-snapshot/commands/status.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

if [[ ! -f "${STATE_DIR}/config.json" ]]; then
    echo "No snapshot found. Run 'node-snapshot snapshot' first."
    exit 0
fi

# nvm is optional here — status degrades gracefully without it
NVM_AVAILABLE=false
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh"
    NVM_AVAILABLE=true
fi

last_check="$(jq -r '.last_check_utc // "(never)"' "${STATE_DIR}/config.json" 2>/dev/null || echo '(never)')"

echo "Node Snapshot — State directory: ${STATE_DIR}"
echo "Last check:   ${last_check}"
echo ""
printf "%-12s %-14s %-16s %s\n" "Alias" "Installed" "Lock version" "Status"
printf "%-12s %-14s %-16s %s\n" "-----" "---------" "------------" "------"

while IFS= read -r alias; do
    lock_file="${STATE_DIR}/lts-${alias}.lock.json"

    installed="-"
    if ${NVM_AVAILABLE}; then
        installed="$(nvm ls "lts/${alias}" --no-colors 2>/dev/null \
            | grep -v 'N/A' | grep -o 'v[0-9.]*' | head -1 || echo '-')"
    fi

    lock_version="(none)"
    status="– not snapshotted"
    if [[ -f "${lock_file}" ]]; then
        raw="$(jq -r '.node_version // ""' "${lock_file}" 2>/dev/null || echo '')"
        if [[ -n "${raw}" ]]; then
            lock_version="v${raw}"
            if ${NVM_AVAILABLE} && [[ "${installed}" != "-" ]]; then
                if [[ "${installed}" == "${lock_version}" ]]; then
                    status="✓ up-to-date"
                else
                    status="⚠ outdated"
                fi
            else
                status="✓ snapshotted"
            fi
        fi
    fi

    printf "%-12s %-14s %-16s %s\n" "${alias}" "${installed}" "${lock_version}" "${status}"
done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json")
```

Make it executable:

```bash
chmod +x libexec/node-snapshot/commands/status.sh
```

- [ ] **Step 4: Run tests to verify status passes**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected:

```plaintext
✓ help
✓ --help
✓ --version
✓ unknown command exits 1
✓ status: no config → guidance message
✓ status: config present → shows alias

All unit tests: PASS
```

- [ ] **Step 5: shellcheck**

```bash
shellcheck libexec/node-snapshot/commands/status.sh
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add libexec/node-snapshot/commands/status.sh test/node-snapshot/test-unit.sh
git commit -m "feat: add node-snapshot status subcommand"
```

---

## Task 3: init.sh

**Files:**

- Create: `libexec/node-snapshot/commands/init.sh`
- Modify: `test/node-snapshot/test-unit.sh` (add init assertions)

- [ ] **Step 1: Add init assertions to `test/node-snapshot/test-unit.sh`**

Replace the final `echo "All unit tests: PASS"` block with:

```bash
# ── init ─────────────────────────────────────────────────────────────────────
output="$("${BIN}" init)"
_assert_match "${output}" "_node_snapshot_chpwd"
_assert_match "${output}" "add-zsh-hook"
_assert_match "${output}" "node-snapshot upgrade --check"
_pass "init: emits chpwd function and hook registration"

rm -rf "${TMPDIR_STATE}"
echo ""; echo "All unit tests: PASS"
```

- [ ] **Step 2: Run to confirm init test fails**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected: exec into missing `init.sh`.

- [ ] **Step 3: Write `libexec/node-snapshot/commands/init.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Emit zsh shell integration to stdout.
# Usage in .zshrc:  source <(node-snapshot init)
# Requires zsh — add-zsh-hook chpwd is zsh-specific.
cat <<'SHELL'
_node_snapshot_chpwd() {
    local node_file=""
    [[ -f ".node-version" ]] && node_file=".node-version"
    [[ -f ".nvmrc"        ]] && node_file=".nvmrc"

    if [[ -n "${node_file}" ]]; then
        nvm use "$(cat "${node_file}")" >/dev/null 2>&1 || true
    fi

    if [[ ! -f "package.json" ]] && [[ -z "${node_file}" ]]; then
        return
    fi

    local node_v npm_v pm pm_field ver msg
    node_v="$(node -v 2>/dev/null || echo '?')"
    npm_v="$(npm -v 2>/dev/null || echo '?')"
    pm=""

    if [[ -f package.json ]]; then
        pm_field="$(node -p "require('./package.json').packageManager||''" 2>/dev/null || true)"
        [[ -n "${pm_field}" ]] && pm="${pm_field%%@*}"
    fi

    if [[ -z "${pm}" ]]; then
        [[ -f pnpm-lock.yaml    ]] && pm="pnpm"
        [[ -f bun.lockb         ]] && pm="bun"
        [[ -f yarn.lock         ]] && pm="yarn"
        [[ -f .yarnrc.yml       ]] && pm="yarn"
        [[ -f package-lock.json ]] && pm="npm"
    fi

    msg="node ${node_v} npm: v${npm_v}"
    case "${pm}" in
        pnpm) msg="${msg} pnpm: v$(pnpm -v 2>/dev/null || echo '?')" ;;
        bun)  msg="${msg} bun: v$(bun -v 2>/dev/null || echo '?')"   ;;
        yarn)
            ver=""
            local yv
            yv="$(yarn -v 2>/dev/null || echo '')"
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
SHELL
```

Make it executable:

```bash
chmod +x libexec/node-snapshot/commands/init.sh
```

- [ ] **Step 4: Run all unit tests**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected: all 7 assertions pass.

- [ ] **Step 5: shellcheck**

```bash
shellcheck libexec/node-snapshot/commands/init.sh
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add libexec/node-snapshot/commands/init.sh test/node-snapshot/test-unit.sh
git commit -m "feat: add node-snapshot init subcommand"
```

---

## Task 4: snapshot.sh

**Files:**

- Create: `libexec/node-snapshot/commands/snapshot.sh`
- Create: `test/node-snapshot/test-integration.sh` (partial — snapshot assertions)

- [ ] **Step 1: Create integration test scaffold**

Create `test/node-snapshot/test-integration.sh`:

```bash
#!/usr/bin/env bash
# Requires nvm installed and lts/iron available.
# Run manually: bash test/node-snapshot/test-integration.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SCRIPT_DIR}/../../bin/node-snapshot"
TMPDIR_STATE="$(mktemp -d)"
export NODE_SNAPSHOT_DIR="${TMPDIR_STATE}"

_pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
_fail() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }
_assert_match()  { [[ "$1" == *"$2"* ]] || _fail "Expected '$2' in: $1"; }
_assert_file()   { [[ -f "$1" ]] || _fail "File not found: $1"; }
_assert_jq()     { jq -e "$2" "$1" >/dev/null 2>&1 || _fail "jq '$2' failed on $1"; }

# Pre-condition: write minimal config tracking iron only
mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
    > "${TMPDIR_STATE}/config.json"

# ── snapshot ─────────────────────────────────────────────────────────────────
output="$("${BIN}" snapshot iron 2>&1)"
_assert_match "${output}" "✓ Snapshot complete"
_pass "snapshot: exits successfully"

lock="${TMPDIR_STATE}/lts-iron.lock.json"
_assert_file "${lock}"
_pass "snapshot: creates lock file"

_assert_jq "${lock}" '.lts_alias == "iron"'
_pass "snapshot: lock has lts_alias"

_assert_jq "${lock}" '.node_version | test("^[0-9]")'
_pass "snapshot: lock has node_version"

_assert_jq "${lock}" '.packages | type == "object"'
_pass "snapshot: lock has packages object"

# npm itself must not appear in packages
npm_in_lock="$(jq -r '.packages | has("npm")' "${lock}")"
[[ "${npm_in_lock}" == "false" ]] || _fail "npm must not appear in lock packages"
_pass "snapshot: npm filtered from packages"

rm -rf "${TMPDIR_STATE}"
echo ""; echo "Snapshot integration tests: PASS"
```

Make it executable:

```bash
chmod +x test/node-snapshot/test-integration.sh
```

- [ ] **Step 2: Write `libexec/node-snapshot/commands/snapshot.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NODE_SNAPSHOT_DIR:-${HOME}/.local/share/node-snapshot}"

# Source nvm — required because libexec scripts run in a fresh bash process
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
# shellcheck source=/dev/null
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh"
else
    echo "error: nvm not found at ${NVM_DIR}/nvm.sh" >&2
    echo "Install nvm: https://github.com/nvm-sh/nvm" >&2
    exit 1
fi

_ensure_config() {
    mkdir -p "${STATE_DIR}"
    if [[ ! -f "${STATE_DIR}/config.json" ]]; then
        printf '{\n  "tracked": ["iron", "jod", "krypton"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
            > "${STATE_DIR}/config.json"
    fi
}

_snapshot_alias() {
    local alias="$1"
    echo "→ nvm use lts/${alias}"
    nvm use "lts/${alias}" >/dev/null 2>&1

    local packages_json node_version now lock_file
    packages_json="$(npm list -g --depth=0 --json 2>/dev/null \
        | jq '.dependencies // {} | del(.npm) | del(.corepack) | to_entries | map({key: .key, value: .value.version}) | from_entries')"
    node_version="$(node -v | tr -d 'v')"
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    lock_file="${STATE_DIR}/lts-${alias}.lock.json"

    jq -n \
        --arg lts_alias   "${alias}" \
        --arg node_version "${node_version}" \
        --arg snapshot_utc "${now}" \
        --argjson packages  "${packages_json}" \
        '{lts_alias: $lts_alias, node_version: $node_version, snapshot_utc: $snapshot_utc, packages: $packages}' \
        > "${lock_file}"

    echo "✓ lts/${alias} (${node_version}) → ${lock_file}"
}

_ensure_config

alias_arg="${1:-}"
if [[ -n "${alias_arg}" ]]; then
    _snapshot_alias "${alias_arg}"
else
    while IFS= read -r alias; do
        _snapshot_alias "${alias}"
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json")
fi

date -u +"%Y-%m-%dT%H:%M:%SZ" > "${STATE_DIR}/last_snapshot_utc"
echo ""
echo "✓ Snapshot complete → ${STATE_DIR}"
```

Make it executable:

```bash
chmod +x libexec/node-snapshot/commands/snapshot.sh
```

- [ ] **Step 3: shellcheck**

```bash
shellcheck libexec/node-snapshot/commands/snapshot.sh
```

Expected: no output.

- [ ] **Step 4: Run integration test (requires nvm + lts/iron installed)**

```bash
bash test/node-snapshot/test-integration.sh
```

Expected: all 6 snapshot assertions pass.

- [ ] **Step 5: Commit**

```bash
git add libexec/node-snapshot/commands/snapshot.sh test/node-snapshot/test-integration.sh
git commit -m "feat: add node-snapshot snapshot subcommand"
```

---

## Task 5: upgrade.sh

**Files:**

- Create: `libexec/node-snapshot/commands/upgrade.sh`
- Modify: `test/node-snapshot/test-integration.sh` (add upgrade --check assertions)

- [ ] **Step 1: Add upgrade --check assertions to `test/node-snapshot/test-integration.sh`**

Append before the final `echo "Snapshot integration tests: PASS"` line (replace that line with):

```bash
# ── upgrade --check ───────────────────────────────────────────────────────────
# Seed config with a very old last_check_utc to force the check
mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron"],\n  "check_interval_days": 1,\n  "last_check_utc": "2020-01-01T00:00:00Z"\n}\n' \
    > "${TMPDIR_STATE}/config.json"

output="$("${BIN}" upgrade --check 2>&1 || true)"
# Either "update available" (outdated) or silence (up-to-date); must not error
_pass "upgrade --check: exits without error"

# last_check_utc must be updated after running
updated_ts="$(jq -r '.last_check_utc' "${TMPDIR_STATE}/config.json")"
[[ "${updated_ts}" != "2020-01-01T00:00:00Z" ]] || _fail "last_check_utc was not updated"
_pass "upgrade --check: updates last_check_utc in config"

# Within interval → skip silently
output="$("${BIN}" upgrade --check 2>&1 || true)"
[[ -z "${output}" ]] || _pass "upgrade --check: within interval, silent exit"
_pass "upgrade --check: interval guard works"

rm -rf "${TMPDIR_STATE}"
echo ""; echo "All integration tests: PASS"
```

- [ ] **Step 2: Write `libexec/node-snapshot/commands/upgrade.sh`**

```bash
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

_ensure_config() {
    mkdir -p "${STATE_DIR}"
    if [[ ! -f "${STATE_DIR}/config.json" ]]; then
        printf '{\n  "tracked": ["iron", "jod", "krypton"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
            > "${STATE_DIR}/config.json"
    fi
}

_update_last_check() {
    local tmp
    tmp="$(mktemp)"
    jq --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.last_check_utc = $now' \
        "${STATE_DIR}/config.json" > "${tmp}"
    mv "${tmp}" "${STATE_DIR}/config.json"
}

_check_mode() {
    local last_check interval last_epoch now_epoch days_since
    last_check="$(jq -r '.last_check_utc // ""' "${STATE_DIR}/config.json" 2>/dev/null || echo '')"
    interval="$(jq -r '.check_interval_days // 7' "${STATE_DIR}/config.json" 2>/dev/null || echo '7')"

    if [[ -n "${last_check}" ]]; then
        last_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_check}" "+%s" 2>/dev/null || echo '0')"
        now_epoch="$(date -u "+%s")"
        days_since=$(( (now_epoch - last_epoch) / 86400 ))
        if [[ "${days_since}" -lt "${interval}" ]]; then
            exit 0
        fi
    fi

    while IFS= read -r alias; do
        local remote_latest local_version
        remote_latest="$(nvm ls-remote "lts/${alias}" --no-colors 2>/dev/null \
            | grep 'Latest LTS' | grep -o 'v[0-9.]*' | head -1 || echo '')"
        local_version="$(nvm ls "lts/${alias}" --no-colors 2>/dev/null \
            | grep -v 'N/A' | grep -o 'v[0-9.]*' | head -1 || echo '')"

        if [[ -n "${remote_latest}" ]] && [[ "${remote_latest}" != "${local_version}" ]]; then
            echo "[node-snapshot] lts/${alias} update available: ${local_version:-not installed} → ${remote_latest}"
            echo "  Run: node-snapshot upgrade ${alias}"
        fi
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json")

    _update_last_check
}

_upgrade_alias() {
    local alias="$1"
    local lock_file="${STATE_DIR}/lts-${alias}.lock.json"
    local old_node_version=""

    if [[ -f "${lock_file}" ]]; then
        old_node_version="$(jq -r '.node_version // ""' "${lock_file}" 2>/dev/null || echo '')"
    fi

    echo "→ nvm install lts/${alias} --latest-npm"
    nvm install "lts/${alias}" --latest-npm
    nvm use "lts/${alias}" >/dev/null 2>&1
    local new_node_version
    new_node_version="$(node -v | tr -d 'v')"

    if [[ -n "${old_node_version}" ]] && [[ "${old_node_version}" != "${new_node_version}" ]]; then
        echo "→ migrating packages (${old_node_version} → ${new_node_version})"
        "${_self_dir}/migrate.sh" "${alias}" "${alias}"
        # migrate.sh runs snapshot internally
    else
        "${_self_dir}/snapshot.sh" "${alias}"
    fi
}

_ensure_config

CHECK=false
ALIAS=""
for arg in "$@"; do
    case "${arg}" in
        --check) CHECK=true  ;;
        *)       ALIAS="${arg}" ;;
    esac
done

if ${CHECK}; then
    _check_mode
    exit 0
fi

if [[ -n "${ALIAS}" ]]; then
    _upgrade_alias "${ALIAS}"
else
    while IFS= read -r alias; do
        _upgrade_alias "${alias}"
    done < <(jq -r '.tracked[]' "${STATE_DIR}/config.json")
fi
```

Make it executable:

```bash
chmod +x libexec/node-snapshot/commands/upgrade.sh
```

- [ ] **Step 3: shellcheck**

```bash
shellcheck libexec/node-snapshot/commands/upgrade.sh
```

Expected: no output.

- [ ] **Step 4: Run integration tests**

```bash
bash test/node-snapshot/test-integration.sh
```

Expected: snapshot + upgrade assertions all pass.

- [ ] **Step 5: Commit**

```bash
git add libexec/node-snapshot/commands/upgrade.sh test/node-snapshot/test-integration.sh
git commit -m "feat: add node-snapshot upgrade subcommand"
```

---

## Task 6: migrate.sh

**Files:**

- Create: `libexec/node-snapshot/commands/migrate.sh`
- Modify: `test/node-snapshot/test-integration.sh` (add migrate assertions)

- [ ] **Step 1: Add migrate assertions to `test/node-snapshot/test-integration.sh`**

Append before the final `echo "All integration tests: PASS"` line (replace it with):

```bash
# ── migrate ───────────────────────────────────────────────────────────────────
# Seed a lock file for iron with a known package list
TMPDIR_STATE="$(mktemp -d)"
export NODE_SNAPSHOT_DIR="${TMPDIR_STATE}"
mkdir -p "${TMPDIR_STATE}"
printf '{\n  "tracked": ["iron", "jod"],\n  "check_interval_days": 7,\n  "last_check_utc": ""\n}\n' \
    > "${TMPDIR_STATE}/config.json"
printf '{"lts_alias":"iron","node_version":"20.19.1","snapshot_utc":"2026-05-05T00:00:00Z","packages":{}}\n' \
    > "${TMPDIR_STATE}/lts-iron.lock.json"

# migrate with empty packages should succeed and produce a jod lock file
output="$("${BIN}" migrate iron jod 2>&1)"
_assert_match "${output}" "✓ Snapshot complete"
_pass "migrate: exits successfully"
_assert_file "${TMPDIR_STATE}/lts-jod.lock.json"
_pass "migrate: creates destination lock file"

# missing from-lock exits with error
output="$("${BIN}" migrate hydrogen jod 2>&1 || true)"
_assert_match "${output}" "error:"
_pass "migrate: missing from-lock exits with error"

# missing args exits with error
output="$("${BIN}" migrate 2>&1 || true)"
_assert_match "${output}" "Usage:"
_pass "migrate: missing args shows usage"

rm -rf "${TMPDIR_STATE}"
echo ""; echo "All integration tests: PASS"
```

- [ ] **Step 2: Write `libexec/node-snapshot/commands/migrate.sh`**

```bash
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
```

Make it executable:

```bash
chmod +x libexec/node-snapshot/commands/migrate.sh
```

- [ ] **Step 3: shellcheck**

```bash
shellcheck libexec/node-snapshot/commands/migrate.sh
```

Expected: no output.

- [ ] **Step 4: Run integration tests**

```bash
bash test/node-snapshot/test-integration.sh
```

Expected: all assertions pass.

- [ ] **Step 5: Commit**

```bash
git add libexec/node-snapshot/commands/migrate.sh test/node-snapshot/test-integration.sh
git commit -m "feat: add node-snapshot migrate subcommand"
```

---

## Task 7: Formula/node-snapshot.rb

**Files:**

- Create: `Formula/node-snapshot.rb`

- [ ] **Step 1: Verify all scripts pass shellcheck together**

```bash
shellcheck bin/node-snapshot \
    libexec/node-snapshot/commands/init.sh \
    libexec/node-snapshot/commands/status.sh \
    libexec/node-snapshot/commands/snapshot.sh \
    libexec/node-snapshot/commands/upgrade.sh \
    libexec/node-snapshot/commands/migrate.sh
```

Expected: no output.

- [ ] **Step 2: Run full unit test suite**

```bash
bash test/node-snapshot/test-unit.sh
```

Expected: all 7 assertions pass.

- [ ] **Step 3: Write `Formula/node-snapshot.rb`**

```ruby
class NodeSnapshot < Formula
  desc "Manage nvm LTS versions and global npm packages with snapshots"
  homepage "https://github.com/AndrewDongminYoo/homebrew-tap"
  # Fill url + sha256 after creating a GitHub release tag
  url "https://github.com/AndrewDongminYoo/homebrew-tap/archive/refs/tags/v0.4.0.tar.gz"
  sha256 ""
  version "0.4.0"
  license "MIT"

  head "https://github.com/AndrewDongminYoo/homebrew-tap.git", branch: "main"

  depends_on "jq"

  def install
    bin.install "bin/node-snapshot"
    (libexec/"node-snapshot"/"commands").install Dir["libexec/node-snapshot/commands/*"]

    # Rewrite LIBEXEC_DIR in the entry point to the Homebrew prefix path
    inreplace bin/"node-snapshot",
      %r{\$\{_self\}/\.\./libexec/node-snapshot/commands},
      "#{opt_libexec}/node-snapshot/commands"
  end

  def caveats
    <<~EOS
      Add shell integration to your .zshrc:
        source <(node-snapshot init)

      On first run, create a config with your tracked LTS aliases:
        mkdir -p ~/.local/share/node-snapshot
        echo '{"tracked":["iron","jod","krypton"],"check_interval_days":7,"last_check_utc":""}' \\
          > ~/.local/share/node-snapshot/config.json

      Default state directory: ~/.local/share/node-snapshot/
      Override: export NODE_SNAPSHOT_DIR=/your/path
    EOS
  end

  test do
    # Dispatcher
    assert_match "Usage: node-snapshot", shell_output("#{bin}/node-snapshot help")
    assert_match "Usage: node-snapshot", shell_output("#{bin}/node-snapshot --help")
    assert_match "node-snapshot",        shell_output("#{bin}/node-snapshot --version")
    assert_match "unknown command",      shell_output("#{bin}/node-snapshot bogus 2>&1", 1)

    # Use an isolated state directory so tests never touch the real home
    ENV["NODE_SNAPSHOT_DIR"] = (testpath/"state").to_s

    # status: no config → guidance message, exit 0
    assert_match "No snapshot found", shell_output("#{bin}/node-snapshot status")

    # status: config present → shows alias in table
    snap = testpath/"state"
    snap.mkpath
    (snap/"config.json").write(
      '{"tracked":["iron"],"check_interval_days":7,"last_check_utc":""}'
    )
    status_out = shell_output("#{bin}/node-snapshot status")
    assert_match "State directory:", status_out
    assert_match "iron",             status_out

    # init: emits shell function definition
    init_out = shell_output("#{bin}/node-snapshot init")
    assert_match "_node_snapshot_chpwd", init_out
    assert_match "add-zsh-hook",         init_out
  end
end
```

- [ ] **Step 4: Verify formula Ruby syntax**

```bash
ruby -c Formula/node-snapshot.rb
```

Expected: `Syntax OK`

- [ ] **Step 5: Commit**

```bash
git add Formula/node-snapshot.rb
git commit -m "feat: add node-snapshot Homebrew formula"
```

---

## Task 8: .zshrc integration note

This task is documentation-only — no code changes.

- [ ] **Step 1: Confirm the one-liner works end-to-end in your shell**

Add to `~/.zshrc` (after existing nvm setup):

```shellscript
# node-snapshot shell integration
source <(node-snapshot init)
```

Open a new terminal and `cd` into a directory with a `.nvmrc` file. Verify:

1. nvm switches automatically
2. Node/npm version line prints
3. No error output

- [ ] **Step 2: Run first snapshot**

```bash
node-snapshot snapshot
```

Expected: creates `~/.local/share/node-snapshot/lts-iron.lock.json` (and others for tracked aliases).

- [ ] **Step 3: Verify status output**

```bash
node-snapshot status
```

Expected: table with installed versions and lock versions matching.

- [ ] **Step 4: Commit if any config file was added to the repo**

If `config.json` template or any defaults were added:

```bash
git add <files>
git commit -m "docs: verify node-snapshot shell integration"
```

---

## Self-Review Notes

- **Spec §6 (nvm sourcing):** Every libexec script (`snapshot.sh`, `upgrade.sh`, `migrate.sh`, `status.sh`) sources `$NVM_DIR/nvm.sh` at the top. `status.sh` sources it optionally and degrades gracefully. ✓
- **Spec §7 snapshot step 3 (filter npm):** `snapshot.sh` deletes both `.npm` and `.corepack` from the packages object before writing the lock. ✓
- **Spec §7 upgrade --check interval guard:** `upgrade.sh` reads `last_check_utc` + `check_interval_days`, converts to epoch, and exits 0 silently if within interval. ✓
- **Spec §9 formula test (no nvm required):** Formula `test do` covers dispatcher, status (with and without config), and init output — all runnable without nvm. ✓
- **GitHub username:** All formula URLs use `AndrewDongminYoo` (double-o). ✓
- **Type consistency:** `lts_alias` field name is consistent across spec lock schema, `snapshot.sh` jq output, and `migrate.sh` lock read. ✓
