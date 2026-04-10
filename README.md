# brew-snapshot

Snapshot and restore your Homebrew environment.

## Install

```bash
brew tap dongminyu/brew-snapshot
brew install brew-snapshot
brew-snapshot setup
```

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

| File | Contents |
|------|----------|
| `Brewfile` | Reinstall manifest (`brew bundle`) |
| `Brewfile.lock` | Full version history JSON |
| `Brewfile.deps` | Dependency tree |
| `Brewfile.taps` | Active taps |
| `Brewfile.refs` | Tap git commit hashes |
| `last_snapshot_utc` | Last snapshot timestamp |

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
