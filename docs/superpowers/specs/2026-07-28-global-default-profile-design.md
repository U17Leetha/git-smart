# Global default profile for git-smart

## Problem

git-smart already manages two SSH host aliases (`github-personal`, `github-work`) and rewrites each repo's remote to the right one once you run `git-smart init/clone/switch/push` on that repo. That's "personal per directory" and it already works as-is — no changes needed there.

What's missing: anything that talks to GitHub over SSH *without* going through git-smart's rewriting (a bare `git@github.com:...` clone, `gh`, etc.) falls back to whatever `Host github.com` in `~/.ssh/config` happens to point to — currently a stale, unrelated key. Likewise, the global `~/.gitconfig` `user.name`/`user.email` are just whatever was last set by hand, with no link to git-smart's personal/work concept. The user wants the **work** profile to be that fallback/default everywhere, deliberately and reproducibly, while personal stays opt-in per repo exactly as today.

A new SSH key, `id_ed25519_github_axe`, was generated to replace the current work key and needs to become what `github-work` (and the new global default) point to.

## Goals

- One command (`git-smart global`) makes a profile the machine-wide SSH + git-identity default.
- `setup` and `doctor` know about this concept: `setup` can configure it in the onboarding flow, `doctor` detects drift and suggests the fix.
- Consistent with existing UX: commands prompt interactively when required info is missing, rather than requiring the user to remember flags (matches `switch`/`init`'s existing behavior).
- One-time cleanup of this machine's `~/.ssh/config`: `github-work` repointed to the new key, redundant manual `github-strongcrypto` and `github-axe` stanzas removed.

## Non-goals

- No per-repo personal git-identity (`user.name`/`user.email`) switching. Only SSH key selection is per-repo; only the work profile gets a persisted global git identity. (An earlier uncommitted, unrelated attempt at per-repo git identity is being discarded, not resumed.)
- No general-purpose refactor of unrelated commands (`push`, `pull`, `status`, etc.). Scope is limited to the new global-profile feature plus two small, low-risk dedup fixes it touches directly (see "Incidental simplification" below).

## Design

### New config fields (`~/.config/git-smart.conf`)

```bash
GIT_SMART_GLOBAL_PROFILE="work"
GIT_SMART_WORK_GIT_NAME="Matt Prater"
GIT_SMART_WORK_GIT_EMAIL="matt.prater@strongcrypto.com"
```

`GIT_SMART_GLOBAL_PROFILE` records which profile is currently applied as the machine default (shown by `doctor`, used as the default `--profile` for `git-smart global`). The git name/email fields default from the current `git config --global` values if unset, so adopting this on an already-configured machine is a no-op until the user changes something.

No new field is added for SSH key *paths* — `global` reads the key straight off the existing `github-work`/`github-personal` alias stanza in `~/.ssh/config` (single source of truth, via the existing `current_identity_for_host_config` helper).

### New command: `git-smart global`

```
Usage: git-smart global [options]

Options:
  --profile personal|work
  --dry-run
```

Behavior:
1. Resolve profile: `--profile` if given, else `GIT_SMART_GLOBAL_PROFILE` from config, else prompt interactively (reusing `resolve_profile_interactively`, same pattern as `switch`/`init`).
2. Look up that profile's current SSH key via `current_identity_for_host_config(profile_host(profile))`. If the alias has no identity configured yet, tell the user to run `git-smart setup` first and exit.
3. Write/update the bare `Host github.com` stanza in `~/.ssh/config` to that key, using the existing `append_ssh_host_if_missing` / `update_ssh_host_identity` helpers (already generic over host name).
4. Run `git config --global user.name`/`user.email` from `GIT_SMART_<PROFILE>_GIT_NAME`/`EMAIL` if set (currently only meaningful for `work`; if a personal identity isn't configured, this step is skipped with an info message, not an error).
5. Persist `GIT_SMART_GLOBAL_PROFILE="$profile"` via `save_config`.
6. Print a summary (key path applied, git identity applied) — same style as `show_repo_context`.
7. Respects `--dry-run` throughout, same convention as every other mutating command.

### `setup` changes

After the existing host-alias/key prompts, add one more: *"Global default profile for tools outside git-smart (blank = skip)"*. If answered `personal` or `work`, call the same apply logic used by the `global` command.

### `doctor` changes

Add a section reporting:
- Configured global profile (or "(unset)")
- Bare `github.com` identity file vs. the expected key for that profile → suggestion to run `git-smart global --profile <p>` on mismatch
- Global `git config user.name`/`user.email` vs. the profile's expected values → same suggestion on mismatch

This mirrors the existing repo-level drift-detection style already in `doctor`.

### Incidental simplification (in scope because `global` touches the same code paths)

`run_init` and `run_clone` currently duplicate three `git config --local git-smart.*` calls inline instead of calling the existing `write_repo_context` function that `resolve_repo_context`/`switch` already use for the same purpose. While wiring `global`'s shared helpers, also replace those inline blocks with calls to `write_repo_context`. Pure dedup, no behavior change.

`usage()` gains a `global` line alongside `switch`/`doctor`.

## One-time manual cleanup (this machine, not code)

After `global` is implemented:
1. Run `git-smart global --profile work` (applies `id_ed25519_github_axe` to bare `github.com`, confirms/pins global git identity, persists `GIT_SMART_GLOBAL_PROFILE=work`).
2. Edit `~/.ssh/config` by hand: repoint `github-work`'s `IdentityFile` to `~/.ssh/id_ed25519_github_axe`, delete the `github-strongcrypto` and `github-axe` stanzas entirely.

## Prerequisite

Discard the currently uncommitted, unrelated per-repo git-identity diff (`git checkout -- README.md git-smart`) before starting implementation, per user decision.

## Error handling

- `global` with no resolvable profile and no TTY for prompting → `die` with a clear message (matches existing `die`/`ensure_profile_for_creation` conventions).
- `global` when the target alias (`github-work`/`github-personal`) has no `IdentityFile` yet → `die`, pointing the user to `git-smart setup`.
- All SSH config writes go through the existing awk-based `update_ssh_host_identity`, which is already used for the aliased hosts — no new parsing logic needed for the bare-host case.

## Testing

No existing automated test suite in this repo (it's a bash CLI with manual/interactive flows, per the existing `install.sh --dry-run` pattern). Verification will be manual:
- `git-smart global --dry-run --profile work` prints the intended changes without touching files.
- `git-smart global --profile work` applied on this machine, then `ssh -T github.com` and `git config --global --get user.email` checked against expectations.
- `git-smart doctor` re-run to confirm no drift is reported.
- `git-smart setup`'s new prompt exercised via a spare terminal / dry-run pass to confirm it doesn't break the existing flow when left blank.
