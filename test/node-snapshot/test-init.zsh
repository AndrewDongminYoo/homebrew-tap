#!/usr/bin/env zsh
# Scenario tests for the zsh integration emitted by `node-snapshot init`.
# node, node-snapshot and the package managers are real executables in PATH; only nvm is a
# function, as it is in a real shell. Run with: zsh -f test/node-snapshot/test-init.zsh
emulate -R zsh
setopt err_return pipe_fail

SCRIPT_DIR=${0:A:h}
INIT=${SCRIPT_DIR}/../../libexec/node-snapshot/commands/init.zsh
WORK=$(mktemp -d)
# Sourcing init starts a background `node-snapshot upgrade --check` that may still be writing.
trap 'cd /; rm -rf "${WORK}" 2>/dev/null || { sleep 0.5; rm -rf "${WORK}"; }' EXIT

export NVM_DIR=${WORK}/nvm
export CALLS=${WORK}/calls
BASE_PATH=/usr/bin:/bin
mkdir -p "${WORK}/bin" "${NVM_DIR}/alias/lts"
print v22.23.4 > "${NVM_DIR}/alias/lts/jod"
print v24.22.2 > "${NVM_DIR}/alias/lts/krypton"
print lts/krypton > "${NVM_DIR}/alias/lts/*"

_install_node() {
    mkdir -p "${NVM_DIR}/versions/node/v$1/bin"
    print -r -- "#!/bin/sh
echo v$1" > "${NVM_DIR}/versions/node/v$1/bin/node"
    chmod +x "${NVM_DIR}/versions/node/v$1/bin/node"
}

for tool in pnpm yarn npm bun; do
    print -r -- "#!/bin/sh
echo \"${tool} \$*\" >> \"\${CALLS}\"
[ \"\$1\" = --version ] && echo \"\${FAKE_PM_VERSION:-1.0.0}\"
exit 0" > "${WORK}/bin/${tool}"
done
print -r -- '#!/bin/sh
echo "node-snapshot $*" >> "${CALLS}"
[ "$1" = upgrade ] && [ "$2" = jod ] || exit 0
mkdir -p "${NVM_DIR}/versions/node/v22.23.9/bin"
printf "#!/bin/sh\necho v22.23.9\n" > "${NVM_DIR}/versions/node/v22.23.9/bin/node"
chmod +x "${NVM_DIR}/versions/node/v22.23.9/bin/node"' > "${WORK}/bin/node-snapshot"
chmod +x "${WORK}/bin/"*

nvm() {
    print -r -- "nvm $*" >> "${CALLS}"
    local cmd=$1 save=0 v resolved; shift
    if [[ ${cmd} == install ]]; then
        _install_node "${1#v}"
        set -- "$1"
    fi
    while [[ $1 == --* ]]; do [[ $1 == --save ]] && save=1; shift; done
    v=${1#v}
    [[ $1 == lts/* ]] && v=$(<"${NVM_DIR}/alias/lts/${1#lts/}") && v=${v#v}
    for resolved in "${NVM_DIR}"/versions/node/v*(N/nOn); do
        resolved=${${resolved:t}#v}
        [[ ${resolved} == "${v}" || ${resolved} == "${v}".* ]] && break
        resolved=''
    done
    [[ -n ${resolved} ]] || return 3
    path=("${NVM_DIR}/versions/node/v${resolved}/bin" ${path:#${NVM_DIR}/*})
    (( save )) && print -r -- "$1" > .nvmrc
    return 0
}

source "${INIT}" >/dev/null 2>&1
_node_snapshot_ask() { print -r -- "ask $2" >> "${CALLS}"; [[ ${ANSWER} == y ]]; }

failures=0
check() {
    if eval "$2"; then print -r -- "ok   $1"; else print -r -- "FAIL $1"; failures=$((failures + 1)); fi
}
calls() { [[ -f ${CALLS} ]] && print -r -- "$(<"${CALLS}")"; }
scenario() {
    ANSWER=${1:-n}
    rm -rf "${WORK}/project" "${NVM_DIR}/versions"
    mkdir -p "${WORK}/project"
    cd "${WORK}/project"
    _install_node 22.23.4
    _install_node 24.22.2
    path=("${NVM_DIR}/versions/node/v24.22.2/bin" "${WORK}/bin" ${(s.:.)BASE_PATH})
    : > "${CALLS}"
    _node_snapshot_asked=()
    _node_snapshot_pm_versions=()
}
# The chpwd hook runs in the current shell, so run it here rather than in $(...): PATH changes
# from nvm use and the version cache must survive into the next call.
run() { _node_snapshot_chpwd > "${WORK}/out" 2>&1 || true; out=$(<"${WORK}/out"); }

scenario y; print 22.23.2 > .nvmrc; run
check "newer patch is reported" '[[ ${out} == *"node v22.23.4 is newer than .nvmrc (22.23.2)"* ]]'
check "newer patch asks to save" '[[ $(calls) == *"ask Write 22.23.4 to .nvmrc?"* ]]'
check "save goes through nvm use --save" '[[ $(calls) == *"nvm use --silent --save 22.23.4"* && $(<.nvmrc) == 22.23.4 ]]'

scenario n; print 22.23.2 > .nvmrc; run
check "declining keeps .nvmrc" '[[ $(<.nvmrc) == 22.23.2 ]]'

scenario y; print v22.23.2 > .node-version; run
check ".node-version is rewritten with its v prefix" '[[ $(<.node-version) == v22.23.4 && ! -e .nvmrc ]]'

scenario y; print v22.23.9 > .node-version; run
check "older patch is reported" '[[ ${out} == *"node v22.23.4 is older than .node-version (v22.23.9)"* ]]'
check "older LTS patch runs node-snapshot upgrade" '[[ $(calls) == *"node-snapshot upgrade jod"* ]]'
check "upgrade switches to the new patch" '[[ ${out} == *"node v22.23.9 is now active"* ]]'

scenario y; print 23.1.0 > .nvmrc; run
check "missing non-LTS major is reported" '[[ ${out} == *"no node 23.x is installed (active: v24.22.2)"* ]]'
check "missing non-LTS major runs nvm install" '[[ $(calls) == *"nvm install 23.1.0"* && ${out} == *"node v23.1.0 is now active"* ]]'

scenario y; print 22.23.4 > .nvmrc; run
check "exact match asks nothing" '[[ ${out} == *"node v22.23.4 for .nvmrc (22.23.4)"* && $(calls) != *ask* ]]'
: > "${CALLS}"; run
check "re-entering skips nvm use" '[[ $(calls) != *"nvm use"* ]]'

scenario y; print '# pinned for CI' > .nvmrc; print 'lts/jod' >> .nvmrc; run
check "alias after a comment line is used" '[[ ${out} == *"node v22.23.4 for .nvmrc (lts/jod)"* ]]'

scenario y; print 22.23.4 > .nvmrc
print '{ "packageManager": "pnpm@11.23.0+sha512.abc" }' > package.json; : > pnpm-lock.yaml; run
check "declared package manager is printed without running it" '[[ ${out} == *"pnpm 11.23.0 (packageManager)"* && $(calls) != *"pnpm --version"* ]]'
check "missing node_modules runs the frozen pnpm install" '[[ $(calls) == *"pnpm install --frozen-lockfile"* ]]'

scenario y; print '{ "packageManager": "pnpm@11.23.0" }' > package.json; print a > pnpm-lock.yaml
mkdir -p node_modules/.pnpm; print a > node_modules/.pnpm/lock.yaml; sleep 1; touch pnpm-lock.yaml; run
check "touched but identical pnpm lockfile asks nothing" '[[ $(calls) != *ask* ]]'
print b > pnpm-lock.yaml; run
check "changed pnpm lockfile asks to install" '[[ $(calls) == *"ask Run pnpm install --frozen-lockfile?"* ]]'

scenario n; print '{}' > package.json; : > yarn.lock; FAKE_PM_VERSION=1.22.22 run
check "undeclared yarn 1 runs once and uses --frozen-lockfile" '[[ ${out} == *"yarn 1.22.22"* && $(calls) == *"ask Run yarn install --frozen-lockfile?"* ]]'
: > "${CALLS}"; FAKE_PM_VERSION=1.22.22 run
check "undeclared package manager version is cached per shell" '[[ $(calls) != *"yarn --version"* ]]'

scenario n; print '{ "packageManager": "yarn@4.11.0" }' > package.json; : > yarn.lock; sleep 1; : > .pnp.cjs; run
check "yarn 4 with an up-to-date .pnp.cjs asks nothing" '[[ ${out} == *"yarn 4.11.0 (packageManager)"* && $(calls) != *ask* ]]'

scenario n; print '{}' > package.json; : > bun.lock; run
check "bun.lock selects bun" '[[ $(calls) == *"ask Run bun install --frozen-lockfile?"* ]]'

scenario n; print '{}' > package.json; : > pnpm-lock.yaml; : > package-lock.json; run
check "pnpm-lock.yaml wins over package-lock.json" '[[ ${out} == *"pnpm 1.0.0"* ]]'

scenario n; print '{}' > package.json; : > package-lock.json; run
check "package-lock.json alone uses npm ci" '[[ $(calls) == *"ask Run npm ci?"* ]]'

scenario y; run
check "outside a Node project prints nothing" '[[ -z ${out} ]]'

unfunction _node_snapshot_ask
source "${INIT}" >/dev/null 2>&1
check "without a terminal nothing is asked" '! _node_snapshot_ask key question </dev/null'

(( failures == 0 )) || { print -r -- "${failures} init scenario(s) failed"; exit 1; }
print -r -- "init scenarios passed"
