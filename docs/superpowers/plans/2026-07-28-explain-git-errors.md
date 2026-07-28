# Explain Push/Pull Errors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `git-smart push` or `git-smart pull` fails, print a plain-English diagnosis of the likely cause (SSH auth rejection, unreachable remote, diverged history, connectivity) in addition to git's own raw output, which continues to stream live exactly as it does today.

**Architecture:** One new shared helper, `explain_git_failure()`, pattern-matches captured git output against known failure signatures. Both `run_push`'s final `git push` and `run_pull`'s `git pull --ff-only` change from a bare call to streaming through `tee` (captures output for pattern-matching while still showing it live; the file already runs with `set -o pipefail` so the pipeline's exit status correctly reflects git's real exit code) and calling the helper on failure before aborting via `die`.

**Tech Stack:** Bash, matching the rest of `git-smart`'s conventions. No automated test suite in this repo — verification via fully-offline sandboxed git repos (a shared local bare repo as the "remote," diverged via two separate clones, to deterministically reproduce both a push rejection and a pull fast-forward failure without touching GitHub or needing real SSH/network failures).

---

### Task 1: Add plain-English error translation to push/pull

**Files:**
- Modify: `git-smart` (add `explain_git_failure`, right before `show_repo_context`)
- Modify: `git-smart` (`run_push`'s final push block)
- Modify: `git-smart` (`run_pull`'s pull block)

- [ ] **Step 1: Add the `explain_git_failure` helper**

Find:
```bash
show_repo_context() {
```
Replace with:
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

show_repo_context() {
```

- [ ] **Step 2: Wrap `run_push`'s final push with capture + explanation**

Find:
```bash
  info "Pushing to $REMOTE $BRANCH..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[*] Dry run: git push'
    if [[ ${#push_args[@]} -gt 0 ]]; then
      printf ' %s' "${push_args[@]}"
    fi
    printf ' %s %s\n' "$REMOTE" "$BRANCH"
  else
    git push "${push_args[@]}" "$REMOTE" "$BRANCH"
  fi

  info "Done."
}

run_pull() {
```
Replace with:
```bash
  info "Pushing to $REMOTE $BRANCH..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[*] Dry run: git push'
    if [[ ${#push_args[@]} -gt 0 ]]; then
      printf ' %s' "${push_args[@]}"
    fi
    printf ' %s %s\n' "$REMOTE" "$BRANCH"
  else
    local push_output
    push_output="$(mktemp)"
    if git push "${push_args[@]}" "$REMOTE" "$BRANCH" 2>&1 | tee "$push_output"; then
      rm -f "$push_output"
    else
      explain_git_failure "$(cat "$push_output")"
      rm -f "$push_output"
      die "git push failed. See the output above for details."
    fi
  fi

  info "Done."
}

run_pull() {
```

- [ ] **Step 3: Wrap `run_pull`'s pull with capture + explanation**

Find:
```bash
  info "Pulling from $REMOTE $BRANCH..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[*] Dry run: git pull --ff-only %s %s\n' "$REMOTE" "$BRANCH"
  else
    git pull --ff-only "$REMOTE" "$BRANCH"
  fi
}
```
Replace with:
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
}
```

- [ ] **Step 4: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 5: Build the shared offline test fixture**

This reproduces a real push rejection and a real pull fast-forward failure fully offline, using a shared local bare repo as the "remote" and two independent clones that diverge from each other — no GitHub, no real SSH/network needed for these two cases.

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
git init --bare "$SANDBOX/remote.git" >/dev/null

mkdir -p "$SANDBOX/repo1"
cd "$SANDBOX/repo1"
git init -b main >/dev/null
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "$SANDBOX/remote.git"
git config --local git-smart.profile personal
git config --local git-smart.owner testowner
git config --local git-smart.sshHost github-personal
echo "base" > shared.txt
git add shared.txt
git commit -m "base commit" >/dev/null
git push -u origin main >/dev/null 2>&1

git clone "$SANDBOX/remote.git" "$SANDBOX/repo2" >/dev/null 2>&1
cd "$SANDBOX/repo2"
git config user.name "Test User 2"
git config user.email "test2@example.com"
git config --local git-smart.profile personal
git config --local git-smart.owner testowner
git config --local git-smart.sshHost github-personal
```

- [ ] **Step 6: Functional test — push rejection shows the "remote has changes" explanation**

```bash
cd "$SANDBOX/repo1"
echo "change from repo1" >> shared.txt
git add shared.txt
git commit -m "repo1 change" >/dev/null
HOME="$SANDBOX" "$REPO/git-smart" push --yes "repo1 push" > "$SANDBOX/push1.log" 2>&1
echo "repo1 push exit: $?"

cd "$SANDBOX/repo2"
echo "change from repo2" >> shared.txt
git add shared.txt
git commit -m "repo2 change" >/dev/null
HOME="$SANDBOX" "$REPO/git-smart" push --yes "repo2 push" > "$SANDBOX/push2.log" 2>&1
echo "repo2 push exit: $?"
grep -c "remote has changes you don't have locally" "$SANDBOX/push2.log"
```
Expected: repo1's push exits `0` (succeeds, updates the shared remote). repo2's push exits nonzero (its local history is now behind the remote), and `$SANDBOX/push2.log` contains exactly one match for "remote has changes you don't have locally".

- [ ] **Step 7: Functional test — pull fast-forward failure shows the "diverged" explanation**

Continuing directly from Step 6's state (`repo2` still has its own uncommitted-to-remote local commit that conflicts with what's now on the remote):

```bash
cd "$SANDBOX/repo2"
HOME="$SANDBOX" "$REPO/git-smart" pull > "$SANDBOX/pull1.log" 2>&1
echo "pull exit: $?"
grep -c "they've diverged" "$SANDBOX/pull1.log"
```
Expected: nonzero exit code, `$SANDBOX/pull1.log` contains exactly one match for "they've diverged" (repo2 has a local commit the remote doesn't have, AND the remote has repo1's commit repo2 doesn't have — a genuine divergence that `--ff-only` correctly refuses).

- [ ] **Step 8: Functional test — no false positives on a clean push/pull**

A fresh, unrelated bare-remote-plus-single-repo pair, to confirm the explanation logic produces zero output when nothing actually failed.

```bash
git init --bare "$SANDBOX/remote2.git" >/dev/null
mkdir -p "$SANDBOX/repo4"
cd "$SANDBOX/repo4"
git init -b main >/dev/null
git config user.name "Test User 4"
git config user.email "test4@example.com"
git remote add origin "$SANDBOX/remote2.git"
git config --local git-smart.profile personal
git config --local git-smart.owner testowner
git config --local git-smart.sshHost github-personal
echo "hello" > f.txt
git add f.txt
git commit -m "first" >/dev/null

HOME="$SANDBOX" "$REPO/git-smart" push --yes "clean push" > "$SANDBOX/push_clean.log" 2>&1
echo "push exit: $?"
grep -c "diverged\|Run 'git-smart doctor'\|Could not reach" "$SANDBOX/push_clean.log"

HOME="$SANDBOX" "$REPO/git-smart" pull > "$SANDBOX/pull_clean.log" 2>&1
echo "pull exit: $?"
grep -c "diverged\|Run 'git-smart doctor'\|Could not reach" "$SANDBOX/pull_clean.log"
```
Expected: both commands exit `0`, and both `grep -c` calls return `0` — no explanation text leaks into a successful run.

- [ ] **Step 9: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "feat: explain common push/pull failures in plain English"
```
