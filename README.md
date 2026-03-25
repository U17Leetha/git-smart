# git-smart

GitHub helper for laptops with both personal and work repos.

## What it does

- interactive first-run setup
- personal/work repo directory management
- SSH host alias management
- optional GitHub SSH key generation
- repo-local context storage
- simple daily commands for push, pull, status, open, and context lookup

## Main commands

```bash
git-smart setup
git-smart init
git-smart clone owner/repo
git-smart push
git-smart pull
git-smart status
git-smart where
git-smart open
git-smart switch --profile work
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
```

## Files

- `git-smart`: main CLI
- `git-smart-push`: compatibility wrapper for `git-smart push`
- `install.sh`: installer for `/usr/local/bin` or another prefix
