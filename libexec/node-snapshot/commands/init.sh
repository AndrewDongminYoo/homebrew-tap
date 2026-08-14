#!/usr/bin/env bash
set -euo pipefail

# Emit zsh shell integration to stdout.
# Usage in .zshrc: source <(node-snapshot init)
# Requires zsh — add-zsh-hook chpwd is zsh-specific.
#
# Keep the integration in a static file rather than a Bash heredoc. Homebrew
# Bash 5.3 can block while emitting the previous heredoc body.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec cat "${script_dir}/init.zsh"
