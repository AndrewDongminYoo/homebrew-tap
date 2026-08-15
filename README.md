# homebrew-tap

[![GitHub release](https://img.shields.io/github/v/release/AndrewDongminYoo/homebrew-tap?sort=semver)](https://github.com/AndrewDongminYoo/homebrew-tap/releases)
[![License: MIT](https://img.shields.io/github/license/AndrewDongminYoo/homebrew-tap)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey)

A Homebrew tap with CLI tools for running and snapshotting a Mac development environment.

| Tool            | Purpose                                                   |
| --------------- | --------------------------------------------------------- |
| `maintainer`    | Terminal dashboard over every repository you can push to  |
| `imgen`         | Terminal browser and generator for Codex-generated images |
| `brew-snapshot` | Snapshot and restore your Homebrew environment            |
| `node-snapshot` | Manage nvm LTS versions and global npm package locks      |

## Requirements

- macOS with [Homebrew](https://brew.sh).
- `maintainer`: the [GitHub CLI](https://cli.github.com), pulled in automatically as a formula dependency; authenticate it once with `gh auth login`. Apple Silicon only.
- `imgen`: the [Codex CLI](https://github.com/openai/codex), which Homebrew does not package — install it with `npm install -g @openai/codex`. Apple Silicon only.
- `brew-snapshot`: no extra dependencies.
- `node-snapshot`: [nvm](https://github.com/nvm-sh/nvm) installed (loaded from `$NVM_DIR/nvm.sh`); `jq` is pulled in automatically as a formula dependency.

`maintainer` and `imgen` ship a prebuilt binary rather than a script, and that binary is built on Apple Silicon; the formulae declare `arch: :arm64` so Homebrew refuses rather than installing something that cannot run.

## Install

Install any tool directly — Homebrew adds the tap for you:

```bash
brew install AndrewDongminYoo/tap/maintainer
brew install AndrewDongminYoo/tap/imgen
brew install AndrewDongminYoo/tap/brew-snapshot
brew install AndrewDongminYoo/tap/node-snapshot
```

Or add the tap once, then install by short name:

```bash
brew tap AndrewDongminYoo/tap
brew install maintainer imgen brew-snapshot node-snapshot
```

Each tool needs a one-time setup step — see its section below.

---

## maintainer

A terminal dashboard over every repository you can push to, built for the "open everything I need to look at, then leave the house" workflow.
It lists your repos with the signals that decide whether one needs you — open PRs, Dependabot alerts, unreleased commits — lets you check off the ones worth opening, and launches each in your terminal or editor.

[Source and full documentation](https://github.com/AndrewDongminYoo/maintainer_tui)

### Setup

```bash
gh auth login          # once, if you have not already
maintainer --config    # write ~/.config/maintainer-tui/config.json and print it
```

Point `roots` at the directories your checkouts live in.
The current directory is always searched first, and when it is itself a checkout its parent is searched too, so running `maintainer` from inside any project finds its siblings without configuration.

### Usage

```bash
maintainer                                      # interactive TUI
maintainer --json                               # the same listing, as JSON
maintainer --json --filter=vuln --sort=popular  # scriptable
```

In the TUI, `space` selects, `o` opens the selection, `c` clones whatever is missing, and `g` runs `claude` or `codex` over the focused repo.
`?` lists every key.

### What This Tool Does Not Do

- Review or merge pull requests — it tells you which repos need attention, not what to do about a diff
- Run on Intel Macs or Linux
- Work without `gh` authenticated

---

## imgen

A terminal browser and generator for the images the Codex CLI makes.
Type a description, watch the candidate appear in the terminal at full size, keep it or roll again.
Every image Codex has generated on this machine is already in the gallery.

[Source and full documentation](https://github.com/AndrewDongminYoo/imgen)

### Setup

```bash
npm install -g @openai/codex && codex login
codex features list | grep image_generation   # must report: stable  true
```

### Usage

```bash
imgen
```

`i` focuses the prompt and `enter` sends it, `v` attaches the clipboard image as a reference, `c` copies the selected image back to the clipboard, and `s` saves it into the current directory.

Preview quality is a property of your terminal rather than of the tool; `imgen` prints which protocol it resolved in its header.
`kitty` and `sixel` draw real pixels, `blocks` is the universal half-block fallback.

### What This Tool Does Not Do

- Generate images itself — every generation is a Codex agent turn, with that turn's cost and latency
- Report a progress percentage, because the turn does not publish one
- Run on Intel Macs or Linux

---

## brew-snapshot

### Setup

```bash
brew-snapshot setup   # register launchd agent for login automation
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

For version-critical packages (e.g. `postgresql@17`), check `Brewfile.lock` for the previous version and use a versioned formula or `brew extract` if needed.

### What This Tool Does Not Do

- Guarantee exact version reproduction for all packages
- Pin all formulae with `brew pin`
- Support non-macOS platforms

---

## node-snapshot

### Setup

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
node-snapshot snapshot              # save global packages for all tracked LTS versions
node-snapshot snapshot iron         # save global packages for a single LTS alias
node-snapshot snapshot --force iron # record an empty global set over a non-empty lock (override the wipe guard)
node-snapshot upgrade               # update all tracked LTS versions and migrate packages
node-snapshot upgrade iron          # update a single LTS alias
node-snapshot upgrade --check       # check for updates without installing
node-snapshot migrate iron jod      # copy packages from one LTS alias to another
node-snapshot consolidate           # merge packages from all v20/v22/v24 patch versions into the latest
node-snapshot consolidate jod       # consolidate a single LTS alias
node-snapshot status                # show tracked versions and lock file state
```

### State Files

Stored in `~/.local/share/node-snapshot/` (override: `$NODE_SNAPSHOT_DIR`):

| File                    | Contents                                        |
| ----------------------- | ----------------------------------------------- |
| `config.json`           | Tracked aliases, check interval, last check UTC |
| `lts-<alias>.lock.json` | Per-alias Node version and global package list  |
| `last_snapshot_utc`     | Last snapshot timestamp                         |

### Consolidating packages across patch versions

When you install a new Node patch (e.g. `v22.22.0` after `v22.21.1`), nvm does not automatically carry over global packages from the old installation. Over time, each patch version accumulates a different set of packages and the latest one is often the most bare.

`node-snapshot consolidate` fixes this by scanning every installed patch version of each tracked major (`~/.nvm/versions/node/v22.*/lib/node_modules`), taking the **union** of all user-installed packages, and installing any that are missing into the current (latest) LTS version. It reads directly from disk — no nvm activation per version — and handles `@scope/pkg` layout.

```bash
node-snapshot consolidate jod
# → lts/jod: consolidating v22.x.x → v22.22.2
#   scanning: v22.21.1 v22.22.0 v22.22.1 v22.22.2
#   6 unique package(s) found
#   ✓ @openai/codex@0.80.0
#   npm install -g vercel@50.1.6
#   ...
#   installed: 1, already present: 5
```

After installation the lock file is updated via `snapshot`.

### Protecting the lock from accidental wipes

`snapshot` records the live global set, and `nvm use lts/<alias>` always resolves to the **newest installed** Node version of that line.
So right after a new Node minor is installed — before its globals are migrated — the live set is empty.
Running `snapshot` in that window would otherwise overwrite a populated lock with `{}` and bake the loss into the next commit.

Two safeguards prevent this:

- **`upgrade` carries packages forward.** On a version bump it passes `nvm install --reinstall-packages-from=<old version>`, so the new version inherits the old globals instead of starting bare.
- **`snapshot` refuses a full wipe.** If the live global set is empty but the lock still tracks packages, `snapshot` aborts rather than recording the empty state. Partial drops (some packages removed) are recorded but printed as a warning so the change is visible before you commit.

```bash
node-snapshot snapshot jod
# ✗ lts/jod: refusing to overwrite 5 tracked package(s) with an empty snapshot.
#   Restore them:        node-snapshot migrate jod jod
#   Record empty anyway: node-snapshot snapshot --force jod
```

To restore the packages, run `node-snapshot migrate <alias> <alias>` (reinstalls from the lock) or recover the previous lock from git.
To deliberately record an empty global set, pass `--force`.

### Shell Integration

`node-snapshot init` emits a zsh `chpwd` hook that:

- Automatically switches the active Node version when entering a directory with `.nvmrc` or `.node-version`
- Prints the active Node, npm, and package manager versions on directory change
- Runs `node-snapshot upgrade --check` in the background on shell startup

### What This Tool Does Not Do

- Support shells other than zsh (hook registration uses `add-zsh-hook`)
- Manage npm packages globally without nvm

---

## Updating

```bash
brew update && brew upgrade maintainer imgen brew-snapshot node-snapshot
```

## Uninstalling

```bash
brew uninstall maintainer imgen brew-snapshot node-snapshot
brew untap AndrewDongminYoo/tap
```

## Contributing

Issues and pull requests are welcome.
Scripts must pass `shellcheck` and the unit tests under `test/` before merging:

```bash
shellcheck bin/* libexec/*/commands/*.sh
bash test/brew-snapshot/test-unit.sh
bash test/node-snapshot/test-unit.sh
```

## License

[MIT](LICENSE) © Dongmin, Yu
