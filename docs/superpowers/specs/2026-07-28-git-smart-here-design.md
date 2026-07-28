# `git-smart here`: attach the current directory to a profile

## Problem

`git-smart` has no command for the case where you `cd` into a directory that has no git repo yet (or has one but no remote) and want to bind it to a personal/work profile in place. The existing commands don't cover this:

- `git-smart init` creates a **new** directory under the profile's configured base dir (`~/Development/Personal/<name>`) — it never operates on the directory you're already in.
- `git-smart switch` requires a repo **with a remote already configured** — it dies (`ensure_repo`/`load_remote_state`) if either is missing.

The only current workaround is manual: `git init`, `git remote add origin ...`, then `git-smart switch --profile ...`. This is a real gap surfaced while using the tool day-to-day.

## Goals

- One command, `git-smart here`, bootstraps a directory that has no remote yet: initializes git if needed, wires up the remote, and saves repo-local context — all without leaving the current directory.
- Reuses existing helpers (`build_remote_url`, `write_repo_context`, `profile_default_owner`, `ensure_profile_for_creation`) rather than duplicating logic already used by `init`/`switch`.
- Consistent with the rest of the CLI: supports `--profile`, `--owner`, `--dry-run`; prompts interactively when required info is missing, same as `init`/`switch`/`global`.

## Non-goals

- No `gh repo create` integration. `here` assumes the GitHub repo already exists; the user creates it themselves first if it doesn't. (Unlike `init`, which does offer to create it, since `init` already owns the "create something brand new" workflow.)
- No repo-name override. The repo name is always the current directory's basename — if a different name is needed, rename the directory or the GitHub repo.
- No handling of "repo already has a remote." If one exists, `here` errors and points at `git-smart switch` instead, keeping the two commands' responsibilities distinct: `here` = zero-remote bootstrap, `switch` = rebind an existing remote.

## Design

### Command

```
Usage: git-smart here [options]

Options:
  --profile personal|work
  --owner OWNER
  --dry-run
```

### `run_here()` behavior

1. Resolve profile: `--profile` if given, else prompt interactively (`ensure_profile_for_creation`, same as `run_init`).
2. `repo_name="$(basename "$PWD")"`.
3. Repo-state check:
   - `git rev-parse --is-inside-work-tree` fails → not a repo yet. `git init -b main` in the current directory (respecting `--dry-run`).
   - It succeeds and `git rev-parse --show-toplevel` equals `$PWD` → already a repo, already rooted here — skip init, proceed.
   - It succeeds but toplevel differs from `$PWD` → cwd is a subdirectory of some other repo. `die` with a clear message (don't nest repos).
4. Remote check: if `git remote get-url "$REMOTE"` succeeds (default `$REMOTE` is `origin`), `die` with a message pointing at `git-smart switch --profile ... ` instead.
5. Resolve owner: `--owner` flag → `profile_default_owner "$PROFILE"` → prompt.
6. `remote_url="$(build_remote_url "$owner" "$repo_name" "$PROFILE")"`; `git remote add "$REMOTE" "$remote_url"` (respecting `--dry-run`).
7. `write_repo_context "$PROFILE" "$owner" "$(profile_host "$PROFILE")"` (respecting `--dry-run`, same helper `switch`/the deduped `init`/`clone` use).
8. Print a summary (profile, owner, repo dir, remote URL) — same style as `run_init`'s closing `info` lines.

### Wiring

Same pattern as every other command: `usage()` gains a `here` line, a new `usage_here()`, `here` added to the recognized-command list in `parse_global_args`, help-routing in `parse_common_option`, an `--owner`-accepting case arm in `parse_command_args` (mirrors `init`'s/`switch`'s existing `--owner` handling), and dispatch in `main()`.

## Error handling

- Not run inside any directory issue (n/a — always runs in cwd, no `ensure_repo`/`cd` needed since we're deliberately *not* requiring a pre-existing repo).
- Nested-repo case: `die "This directory is inside an existing repo at <toplevel>. Run 'git-smart here' from a directory that isn't nested inside another repo."`
- Existing-remote case: `die "Remote '$REMOTE' is already configured for this repo. Run 'git-smart switch --profile ...' instead."`
- Missing owner with no default and non-interactive context: same `prompt` fallback every other command uses (no special handling needed).

## Testing

No automated test suite in this repo (established convention — see prior work on this branch). Verification will be the same sandboxed-`HOME` approach used throughout: `--dry-run` runs to confirm no mutation, real runs in a `mktemp -d` sandbox to confirm the repo/remote/context end up correct, and explicit tests for both error paths (nested repo, existing remote).
