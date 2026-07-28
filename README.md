# git-smart

GitHub helper for laptops with both personal and work repos.

## What it does

- interactive first-run setup
- personal/work repo directory management
- SSH host alias management
- optional GitHub SSH key generation
- machine-wide default profile (SSH host + git identity) for tools outside git-smart
- attach an existing directory to a profile in place
- repo-local context storage
- simple daily commands for push, pull, status, open, and context lookup

## Main commands

```bash
git-smart setup
git-smart init
git-smart clone owner/repo
git-smart here --profile personal
git-smart push
git-smart pull
git-smart status
git-smart where
git-smart open
git-smart switch --profile work
git-smart global --profile work
git-smart doctor
```

## Install

```bash
./install.sh
```

Optional:

```bash
./install.sh --dry-run
./install.sh --prefix "$HOME/.local/bin"
```

## First-run flow

```bash
git-smart setup
git-smart doctor
```

`git-smart setup` can:

- prompt for personal and work GitHub owners
- prompt for personal and work repo directories
- add or update SSH host aliases in `~/.ssh/config`
- generate missing personal and work SSH keys
- optionally set one profile as the machine-wide default (SSH host + git identity)
- print the public keys you need to add to GitHub

## Repo context

`git-smart` stores repo-local metadata in git config:

- `git-smart.profile`
- `git-smart.owner`
- `git-smart.sshHost`

That lets normal daily commands work without repeating personal/work flags:

```bash
git-smart push
git-smart pull
git-smart status
```

## Attaching an existing directory

If you `cd` into a directory that has no git repo yet (or has one but no
remote configured) and want to bind it to a profile:

```bash
git-smart here --profile personal
```

This runs `git init` if needed (skipping it if the directory is already a
repo rooted there), adds the remote (the GitHub repo must already exist --
`here` doesn't create it for you), and saves the same repo-local context
`switch` does. If a remote is already configured, `here` refuses and points
you at `git-smart switch` instead, which is the right tool for rebinding an
already-remoted repo. It also refuses if the current directory is nested
inside another repo's working tree.

## Global default profile

Repos managed by `git-smart` (via `init`/`clone`/`switch`/`push`) always resolve
their own SSH key and remote correctly, regardless of any global default.

Anything outside git-smart's control — a plain `git@github.com:...` clone,
`gh`, or any tool that doesn't go through this CLI — falls back to whatever the
bare `Host github.com` entry in `~/.ssh/config` and your global
`~/.gitconfig` say. `git-smart global` lets you pin that fallback to one
profile explicitly:

```bash
git-smart global --profile work
```

This updates the bare `github.com` SSH host to that profile's key, and — for
the `work` profile only — sets `git config --global user.name`/`user.email`
from `GIT_SMART_WORK_GIT_NAME`/`GIT_SMART_WORK_GIT_EMAIL` (`--profile personal`
only repoints the SSH default; there's no persisted personal git identity
today). Either way it remembers your choice in `GIT_SMART_GLOBAL_PROFILE`.
`git-smart doctor` reports drift if the bare host or global git identity
later stop matching. `git-smart setup` also offers to configure this during
onboarding.

## Dependencies

Required:

- `git`
- `ssh`

Optional:

- `gh` for GitHub repo creation during `git-smart init`
- `pbcopy` on macOS for clipboard support during `git-smart setup`
- `open` on macOS for `git-smart open`
- `xdg-open` on Linux for `git-smart open`
- `wl-copy` or `xclip` on Linux for clipboard support during `git-smart setup`

`install.sh` checks these and prints warnings or install hints where appropriate.

## Config file

`git-smart` uses:

```bash
~/.config/git-smart.conf
```

Example:

```bash
GIT_SMART_PERSONAL_DIR="$HOME/Development/Personal"
GIT_SMART_WORK_DIR="$HOME/Development/Work"

GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"

GITHUB_PERSONAL_OWNERS=(U17Leetha)
GITHUB_WORK_OWNERS=(Strong-Crypto-Innovations)

GITHUB_PERSONAL_DEFAULT_OWNER="U17Leetha"
GITHUB_WORK_DEFAULT_OWNER="Strong-Crypto-Innovations"

GIT_SMART_GLOBAL_PROFILE="work"
GIT_SMART_WORK_GIT_NAME="Matt Prater"
GIT_SMART_WORK_GIT_EMAIL="matt.prater@strongcrypto.com"
```

## Files

- `git-smart`: main CLI
- `git-smart-push`: compatibility wrapper for `git-smart push`
- `install.sh`: installer for `/usr/local/bin` or another prefix
