# node-snapshot zsh integration, loaded with: source <(node-snapshot init)
#
# On shell start and on every cd into a Node project, _node_snapshot_chpwd:
#   1. reads the required version from .nvmrc or .node-version and switches nvm to the
#      newest installed release of that major (22.23.2 -> the newest installed 22.x);
#   2. prints how that release compares with the required version, then offers to write the
#      installed release back when it is newer, or to install the required one when it is
#      older or the major is missing (node-snapshot upgrade <lts>, else nvm install);
#   3. prints the package manager and offers a frozen-lockfile install when the dependencies
#      are missing or older than the lockfile.
# Questions are asked only in an interactive shell with a terminal, and each one once per shell.
# `nvm use` costs about 300 ms, so it runs only when the active node must change; the package
# manager runs only when package.json declares no packageManager, and its version is cached.

typeset -gA _node_snapshot_asked _node_snapshot_pm_versions

# _node_snapshot_ask <key> <question>: returns 0 when the answer is y.
_node_snapshot_ask() {
    [[ -o interactive && -t 0 && -t 1 ]] || return 1
    [[ -n "${_node_snapshot_asked[$1]}" ]] && return 1
    _node_snapshot_asked[$1]=1
    local answer
    read -q "answer?📦 $2 [y/N] "
    print
    [[ "${answer}" == y ]]
}

# _node_snapshot_lts_alias <major>: prints the LTS codename nvm records for a major (22 -> jod).
_node_snapshot_lts_alias() {
    emulate -L zsh
    local f
    for f in "${NVM_DIR}"/alias/lts/*(N.); do
        [[ "${f:t}" == '*' ]] && continue
        [[ "$(<"${f}")" == v$1.* ]] && { print -r -- "${f:t}"; return 0; }
    done
    return 1
}

# _node_snapshot_newest <major>: prints the newest installed version of a major (22.23.4).
_node_snapshot_newest() {
    emulate -L zsh
    local -a dirs
    dirs=("${NVM_DIR}"/versions/node/v$1.*(N/nOn))
    (( ${#dirs} )) && print -r -- "${${dirs[1]:t}#v}"
}

# _node_snapshot_active: prints the active node version without starting node when it is nvm's.
_node_snapshot_active() {
    emulate -L zsh
    local node_path=${commands[node]}
    if [[ "${node_path}" == "${NVM_DIR}"/versions/node/v*/bin/node ]]; then
        node_path=${node_path#"${NVM_DIR}"/versions/node/v}
        print -r -- "${node_path%%/*}"
    elif [[ -n "${node_path}" ]]; then
        node_path=$(node -v 2>/dev/null)
        print -r -- "${node_path#v}"
    fi
}

# _node_snapshot_use <version>: switches nvm only when another node is active.
_node_snapshot_use() {
    [[ "$(_node_snapshot_active)" == "$1" ]] && return 0
    nvm use --silent "$1" >/dev/null 2>&1
}

# _node_snapshot_install <major> <wanted>: offers to install the required version, then switches.
_node_snapshot_install() {
    emulate -L zsh
    local lts newest
    lts=$(_node_snapshot_lts_alias "$1")
    if [[ -n "${lts}" ]]; then
        _node_snapshot_ask "${PWD}:install:${2}" "Run node-snapshot upgrade ${lts} (newest $1.x, keeps global packages)?" || return 0
        node-snapshot upgrade "${lts}" || return
    else
        _node_snapshot_ask "${PWD}:install:${2}" "Run nvm install $2?" || return 0
        nvm install "$2" || return
    fi
    newest=$(_node_snapshot_newest "$1")
    [[ -n "${newest}" ]] && _node_snapshot_use "${newest}"
    print -r -- "📦 node v$(_node_snapshot_active) is now active"
}

# _node_snapshot_node_check: steps 1 and 2.
_node_snapshot_node_check() {
    emulate -L zsh -o extendedglob
    local file want wanted major newest active prefix
    local -a lines words
    [[ -f .node-version ]] && file=.node-version
    [[ -f .nvmrc ]] && file=.nvmrc
    if [[ -n "${file}" ]]; then
        lines=(${(f)"$(<"${file}")"})
        lines=(${lines:#[[:space:]]#\#*})
        words=(${=lines[1]})
        want=${words[1]}
    fi

    if [[ -z "${want}" || -z "${NVM_DIR}" ]] || (( ! $+functions[nvm] )); then
        active=$(_node_snapshot_active)
        print -r -- "📦 node v${active:-?}"
        return 0
    fi

    wanted=${want#v}
    prefix=${want%%[0-9]*}
    if [[ "${wanted}" != <->* ]]; then
        # An alias such as lts/jod or node: let nvm resolve it.
        nvm use --silent "${want}" >/dev/null 2>&1 || print -u2 -r -- "📦 nvm could not switch to ${want} from ${file}"
        print -r -- "📦 node v$(_node_snapshot_active) for ${file} (${want})"
        return 0
    fi

    major=${wanted%%[^0-9]*}
    newest=$(_node_snapshot_newest "${major}")
    if [[ -z "${newest}" ]]; then
        print -r -- "📦 node ${want} required by ${file}, but no node ${major}.x is installed (active: v$(_node_snapshot_active))"
        _node_snapshot_install "${major}" "${wanted}"
        return 0
    fi
    _node_snapshot_use "${newest}"
    active=$(_node_snapshot_active)
    if [[ "${active}" != "${newest}" ]]; then
        # Comparing another major with the requirement would offer to overwrite it, so stop here.
        print -u2 -r -- "📦 nvm could not switch to node ${newest} for ${file} (${want}); active: v${active:-?}"
        return 0
    fi

    if [[ "${wanted}" != <->.<->.<-> || "${active}" == "${wanted}" ]]; then
        print -r -- "📦 node v${active} for ${file} (${want})"
        return 0
    fi
    autoload -Uz is-at-least
    if is-at-least "${wanted}" "${active}"; then
        print -r -- "📦 node v${active} is newer than ${file} (${want})"
        _node_snapshot_ask "${PWD}:save:${active}" "Write ${prefix}${active} to ${file}?" || return 0
        if [[ "${file}" == .nvmrc ]]; then
            nvm use --silent --save "${prefix}${active}" >/dev/null 2>&1
        else
            print -r -- "${prefix}${active}" > "${file}"
        fi
    else
        print -r -- "📦 node v${active} is older than ${file} (${want})"
        _node_snapshot_install "${major}" "${wanted}"
    fi
}

# _node_snapshot_deps_check: step 3.
_node_snapshot_deps_check() {
    emulate -L zsh
    [[ -f package.json ]] || return 0
    local pm declared version lockfile install_cmd target=node_modules stale=0
    if [[ "$(<package.json)" =~ '"packageManager"[[:space:]]*:[[:space:]]*"([^"@]+)@?([^"+]*)' ]]; then
        pm=${match[1]}
        declared=${match[2]}
    elif [[ -f pnpm-lock.yaml ]]; then
        pm=pnpm
    elif [[ -f bun.lock || -f bun.lockb ]]; then
        pm=bun
    elif [[ -f yarn.lock || -f .yarnrc.yml ]]; then
        pm=yarn
    else
        pm=npm
    fi
    # packageManager comes from the repository, so a value such as "./pwn" must never be run.
    case "${pm}" in
        pnpm | yarn | npm | bun) ;;
        *)
            print -r -- "📦 unsupported packageManager: ${pm}"
            return 0 ;;
    esac

    if [[ -n "${declared}" ]]; then
        # pnpm 9.7+, Yarn 2+ and Corepack run the declared release, so do not start the tool.
        version=${declared}
        print -r -- "📦 ${pm} ${version} (packageManager)"
    else
        if [[ -z "${_node_snapshot_pm_versions[${PWD}:${pm}]}" ]]; then
            # Corepack asks before downloading a release and waits on a terminal; with stderr
            # discarded that question is invisible, so give the tool no terminal to wait on.
            _node_snapshot_pm_versions[${PWD}:${pm}]=$(command "${pm}" --version </dev/null 2>/dev/null || print -r -- '-')
        fi
        version=${_node_snapshot_pm_versions[${PWD}:${pm}]}
        [[ "${version}" == - ]] && version=''
        print -r -- "📦 ${pm} ${version:-is not installed}"
    fi

    case "${pm}" in
        pnpm)
            lockfile=pnpm-lock.yaml install_cmd='pnpm install --frozen-lockfile' ;;
        bun)
            lockfile=bun.lock install_cmd='bun install --frozen-lockfile'
            [[ -f bun.lock ]] || lockfile=bun.lockb ;;
        yarn)
            lockfile=yarn.lock install_cmd='yarn install --immutable'
            [[ "${version}" == 1.* ]] && install_cmd='yarn install --frozen-lockfile'
            if [[ -f .pnp.cjs ]]; then
                target=.pnp.cjs
            elif [[ -f node_modules/.yarn-state.yml ]]; then
                target=node_modules/.yarn-state.yml
            elif [[ -f node_modules/.yarn-integrity ]]; then
                target=node_modules/.yarn-integrity
            fi ;;
        npm)
            lockfile=package-lock.json install_cmd='npm ci'
            [[ -f node_modules/.package-lock.json ]] && target=node_modules/.package-lock.json ;;
    esac
    [[ -n "${version}" && -f "${lockfile}" ]] || return 0

    if [[ ! -e "${target}" ]]; then
        stale=1
    elif [[ "${pm}" == pnpm && -f node_modules/.pnpm/lock.yaml ]]; then
        # pnpm keeps a copy of the lockfile it installed, so compare contents rather than mtimes.
        cmp -s "${lockfile}" node_modules/.pnpm/lock.yaml || stale=1
    elif [[ "${lockfile}" -nt "${target}" ]]; then
        stale=1
    fi
    (( stale )) || return 0
    print -r -- "📦 dependencies are missing or older than ${lockfile}"
    _node_snapshot_ask "${PWD}:deps" "Run ${install_cmd}?" && ${=install_cmd}
    return 0
}

_node_snapshot_chpwd() {
    [[ -f package.json || -f .node-version || -f .nvmrc ]] || return 0
    _node_snapshot_node_check
    _node_snapshot_deps_check
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _node_snapshot_chpwd
_node_snapshot_chpwd

(node-snapshot upgrade --check 2>/dev/null &)
