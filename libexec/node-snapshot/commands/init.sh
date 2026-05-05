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
