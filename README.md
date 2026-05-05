# homebrew-tap

A Homebrew tap with two CLI tools for snapshotting your Mac development environment.

## Tools

| Tool            | Purpose                                              |
| --------------- | ---------------------------------------------------- |
| `brew-snapshot` | Snapshot and restore your Homebrew environment       |
| `node-snapshot` | Manage nvm LTS versions and global npm package locks |

---

## brew-snapshot

### Install

```bash
brew tap AndrewDongminYoo/tap
brew install brew-snapshot
brew-snapshot setup
```

### Usage

```bash
brew-snapshot snapshot           # save current Homebrew state
brew-snapshot snapshot --greedy  # also upgrade casks
brew-snapshot restore            # reinstall from Brewfile on a new Mac
brew-snapshot status             # show last snapshot info
brew-snapshot setup              # register launchd agent for login automation
```

### State Files

Stored in `~/.local/share/brew-snapshot/` (override: `$BREW_SNAPSHOT_DIR`):

| File                | Contents                           |
| ------------------- | ---------------------------------- |
| `Brewfile`          | Reinstall manifest (`brew bundle`) |
| `Brewfile.lock`     | Full version history JSON          |
| `Brewfile.deps`     | Dependency tree                    |
| `Brewfile.taps`     | Active taps                        |
| `Brewfile.refs`     | Tap git commit hashes              |
| `last_snapshot_utc` | Last snapshot timestamp            |

### Restore on a New Mac

```bash
brew-snapshot restore
```

For version-critical packages (e.g. `postgresql@17`), check `Brewfile.lock` for the
previous version and use a versioned formula or `brew extract` if needed.

### What This Tool Does Not Do

- Guarantee exact version reproduction for all packages
- Pin all formulae with `brew pin`
- Support non-macOS platforms

---

## node-snapshot

### Install

```bash
brew tap AndrewDongminYoo/tap
brew install node-snapshot
```

Add shell integration to your `.zshrc`:

```bash
source <(node-snapshot init)
```

On first run, create a config with your tracked LTS aliases:

```bash
mkdir -p ~/.local/share/node-snapshot
echo '{"tracked":["iron","jod","krypton"],"check_interval_days":7,"last_check_utc":""}' \
  > ~/.local/share/node-snapshot/config.json
```

### Usage

```bash
node-snapshot snapshot           # save global packages for all tracked LTS versions
node-snapshot snapshot iron      # save global packages for a single LTS alias
node-snapshot upgrade            # update all tracked LTS versions and migrate packages
node-snapshot upgrade iron       # update a single LTS alias
node-snapshot upgrade --check    # check for updates without installing
node-snapshot migrate iron jod   # copy packages from one LTS alias to another
node-snapshot status             # show tracked versions and lock file state
```

### State Files

Stored in `~/.local/share/node-snapshot/` (override: `$NODE_SNAPSHOT_DIR`):

| File                    | Contents                                        |
| ----------------------- | ----------------------------------------------- |
| `config.json`           | Tracked aliases, check interval, last check UTC |
| `lts-<alias>.lock.json` | Per-alias Node version and global package list  |
| `last_snapshot_utc`     | Last snapshot timestamp                         |

### Shell Integration

`node-snapshot init` emits a zsh `chpwd` hook that:

- Automatically switches the active Node version when entering a directory with `.nvmrc` or `.node-version`
- Prints the active Node, npm, and package manager versions on directory change
- Runs `node-snapshot upgrade --check` in the background on shell startup

### What This Tool Does Not Do

- Support shells other than zsh (hook registration uses `add-zsh-hook`)
- Manage npm packages globally without nvm
