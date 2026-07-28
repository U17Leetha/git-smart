# Guard `git-smart push`

## Problem

`run_push()` runs `git add -A` (stages *everything* in the working directory), then commits with either a user-supplied message or an auto-generated `"Update <date>"` message, showing only `git status -sb` (a terse one-line-per-file summary) before doing so. There's no confirmation and no meaningful preview. Per the broader adversarial review of this tool, this is a real footgun: it's easy to stage and commit something unintended (a stray file, a secret, half-finished junk) without noticing, especially for someone who doesn't already have a strong mental model of what `git add -A` does.

## Goals

- Before every commit `push` makes, show an accurate summary of exactly what's about to be committed (file-level stat: files changed, lines added/removed), and require confirmation.
- Provide a `--yes`/`-y` flag to skip the confirmation for anyone who doesn't want to be prompted every time.
- If the user declines, cleanly abort: unstage everything, don't commit, don't push.

## Non-goals

- No change to `--push-only` mode (skips staging/commit entirely already — nothing to guard).
- No change to `--dry-run` behavior (already skips staging and prints what it would do).
- No full line-by-line diff option — stat summary only (per explicit choice: always fits on screen, gives a clear "is this what I expect" check without scrolling).

## Design

### New flag

`--yes` / `-y`, parsed in `push`'s existing case arm in `parse_command_args` (alongside `--push-only`/`--set-upstream`). Sets a new global `SKIP_CONFIRM=1`.

### Changed flow in `run_push()`

Only the `PUSH_ONLY -eq 0` (commit) branch changes:

1. Stage as today: `git add -A` (unless `DRY_RUN`).
2. Show `git status -sb` as today.
3. If there's nothing staged: unchanged (`warn "No staged changes to commit."`).
4. If `DRY_RUN`: unchanged (prints what commit message would be used).
5. **New**, before committing: print `git diff --cached --stat` — computed *after* staging, so it's always an accurate reflection of what's actually staged (no separate prediction logic needed).
6. **New**: unless `SKIP_CONFIRM -eq 1`, prompt `Commit these changes with message "$COMMIT_MESSAGE"? [Y/n]` (reusing the existing `prompt_yes_no` helper).
7. **New**: if declined, `git reset` (unstage everything) and abort the whole `push` command via `die` — no commit, no push, clean no-op state.
8. If confirmed (or `-y`/`--yes` was given): commit and push exactly as today.

## Error handling

- Decline path: `git reset >/dev/null` then `die "Push cancelled."` — matches the file's existing `die`-based abort convention. `git reset` on an already-empty index is a safe no-op if there was nothing to unstage (can't happen here since we only reach the confirmation when something was staged, but noting for completeness).
- `--dry-run` + declining doesn't apply (the confirmation step is entirely inside the non-dry-run commit path).

## Testing

No automated test suite in this repo (established convention). Verification: sandboxed repo runs confirming (a) the stat summary appears and is accurate, (b) declining unstages and aborts without committing or pushing, (c) confirming proceeds normally, (d) `-y`/`--yes` skips the prompt entirely, (e) `--push-only` and `--dry-run` are unaffected.
