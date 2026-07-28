# Plain-English error translation for push/pull

## Problem

`run_push()` and `run_pull()` let raw git errors (SSH auth failures, fast-forward rejections, network issues) surface directly to the user with no interpretation. Per the broader adversarial UX review of this tool, this is a real barrier for anyone who doesn't already know what "non-fast-forward" or "Permission denied (publickey)" means or what to do about it.

## Goals

- On a `push`/`pull` failure, print a plain-English diagnosis (via `warn`) identifying the likely cause and the next command to run, in addition to (not instead of) git's own raw output, which continues to stream live as it does today.
- Cover the failure modes most likely to actually occur for this tool's users: SSH auth rejection, unreachable/no-access remote, diverged history (both the push-side "remote has changes" case and the pull-side "can't fast-forward" case), and basic connectivity failure.
- Never hide or guess wrong: if the failure doesn't match a known pattern, show the raw output with no fabricated explanation, just a generic pointer to what was printed above.

## Non-goals

- No change to `git-smart clone`, `init`'s `gh repo create` step, or any other command (explicit scope decision — push/pull are the daily-driver commands where this matters most).
- No change to commit-time failures (hooks, etc.) — only the actual `git push`/`git pull` network operations are covered.
- No change to `--dry-run` behavior (those branches never reach the real git command today, and still won't).

## Design

### Shared helper: `explain_git_failure()`

Takes captured git output (stdout+stderr combined) as an argument, pattern-matches (case-insensitive `grep`) against known signatures, and prints one `warn` line per match via an if/elif chain (first match wins, since these patterns are mutually exclusive in practice):

```bash
explain_git_failure() {
  local output="$1"

  if printf '%s' "$output" | grep -qi "permission denied (publickey)"; then
    warn "GitHub rejected your SSH key. Run 'git-smart doctor' to check your SSH setup."
  elif printf '%s' "$output" | grep -qi "could not read from remote repository"; then
    warn "Could not reach the remote repository -- check your SSH key and that you have access. Run 'git-smart doctor' to diagnose."
  elif printf '%s' "$output" | grep -qi "not possible to fast-forward"; then
    warn "Your branch and the remote have both changed (they've diverged)."
    warn "This tool only does fast-forward pulls to avoid surprise merges -- resolve this with plain git (e.g. 'git merge' or 'git rebase'), then try again."
  elif printf '%s' "$output" | grep -qi -E "failed to push some refs|non-fast-forward|fetch first"; then
    warn "The remote has changes you don't have locally. Run 'git-smart pull' first, then try pushing again."
  elif printf '%s' "$output" | grep -qi -E "could not resolve host|network is unreachable|could not connect"; then
    warn "Could not reach GitHub -- check your internet connection."
  fi
}
```

### Call sites

Both `run_push`'s final `git push` and `run_pull`'s `git pull --ff-only` change from a bare call to: stream output live via `tee` to a temp file (the file already runs with `set -o pipefail`, so the pipeline's exit status correctly reflects git's exit code, not `tee`'s), and on failure, feed the captured output to `explain_git_failure` before aborting via `die`. Example shape (`run_pull`):

```bash
  info "Pulling from $REMOTE $BRANCH..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[*] Dry run: git pull --ff-only %s %s\n' "$REMOTE" "$BRANCH"
  else
    local pull_output
    pull_output="$(mktemp)"
    if git pull --ff-only "$REMOTE" "$BRANCH" 2>&1 | tee "$pull_output"; then
      rm -f "$pull_output"
    else
      explain_git_failure "$(cat "$pull_output")"
      rm -f "$pull_output"
      die "git pull failed. See the output above for details."
    fi
  fi
```
`run_push`'s change is structurally identical, applied to its final `git push "${push_args[@]}" "$REMOTE" "$BRANCH"` call.

## Error handling

- The temp file is always cleaned up (`rm -f`) on both success and failure paths.
- `explain_git_failure` never fails the script itself (plain `grep`/`printf`, no `die` inside it) — the actual abort happens at the call site via `die` after it returns, keeping the "diagnose, then fail" ordering explicit and consistent with the rest of the file's `die`-based control flow.
- If git's own message changes wording in a future git version and a pattern stops matching, the fallback (no extra warning line, just the raw output) is safe — never worse than today's behavior, never a false diagnosis.

## Testing

No automated test suite in this repo (established convention). Verification: simulate each failure mode in an offline sandbox where possible (diverged history is fully reproducible offline via two local clones of a shared bare repo; SSH/network failures are harder to reproduce deterministically offline, so those will be verified by reading `explain_git_failure`'s logic and confirming the `grep` patterns match real git/ssh error text, rather than triggering an actual auth failure).
