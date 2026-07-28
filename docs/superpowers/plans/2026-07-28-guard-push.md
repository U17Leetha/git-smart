# Guard git-smart push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before `git-smart push` commits, show an accurate stat summary of what's staged and require confirmation (skippable via `--yes`/`-y`); declining cleanly unstages and aborts without committing or pushing.

**Architecture:** One new global flag `SKIP_CONFIRM`, set by a new `--yes`/`-y` option in `push`'s existing argument parsing. The commit branch of `run_push()` gains a `git diff --cached --stat` preview and a `prompt_yes_no` confirmation between staging and committing. `--push-only` and `--dry-run` are untouched (neither reaches the commit branch this modifies in a way that's affected).

**Tech Stack:** Bash, matching the rest of `git-smart`'s conventions (`die`, `prompt_yes_no`, `info`/`warn`). No automated test suite in this repo — verification via a fully-offline sandboxed git repo with a local bare "remote" (so real `git push` can be exercised end-to-end without touching GitHub).

---

### Task 1: Add confirmation before commit in `git-smart push`

**Files:**
- Modify: `git-smart` (global var declarations)
- Modify: `git-smart` (`push`'s case arm in `parse_command_args`)
- Modify: `git-smart` (`usage_push`)
- Modify: `git-smart` (`run_push`)

- [ ] **Step 1: Add the `SKIP_CONFIRM` global**

Find:
```bash
SET_UPSTREAM=0
PUSH_ONLY=0
```
Replace with:
```bash
SET_UPSTREAM=0
PUSH_ONLY=0
SKIP_CONFIRM=0
```

- [ ] **Step 2: Accept `--yes`/`-y` for `push`**

Find:
```bash
      push)
        case "$1" in
          --push-only)
            PUSH_ONLY=1
            ;;
          --set-upstream)
            SET_UPSTREAM=1
            ;;
          *)
            break
            ;;
        esac
        ;;
```
Replace with:
```bash
      push)
        case "$1" in
          --push-only)
            PUSH_ONLY=1
            ;;
          --set-upstream)
            SET_UPSTREAM=1
            ;;
          --yes|-y)
            SKIP_CONFIRM=1
            ;;
          *)
            break
            ;;
        esac
        ;;
```

- [ ] **Step 3: Document `--yes`/`-y` in `usage_push`**

Find:
```bash
usage_push() {
  cat <<'EOF'
Usage: git-smart push [options] [commit message]

Options:
  --profile personal|work|auto
  --remote NAME
  --push-only
  --set-upstream
  --dry-run

Normally you should not need --profile after the repo has been initialized or cloned with git-smart.
EOF
}
```
Replace with:
```bash
usage_push() {
  cat <<'EOF'
Usage: git-smart push [options] [commit message]

Options:
  --profile personal|work|auto
  --remote NAME
  --push-only
  --set-upstream
  --yes, -y      Skip the confirmation before committing
  --dry-run

Before committing, push shows a summary of what's staged and asks for
confirmation unless --yes/-y is given. Normally you should not need
--profile after the repo has been initialized or cloned with git-smart.
EOF
}
```

- [ ] **Step 4: Add the stat preview and confirmation to `run_push`**

Find:
```bash
    if git diff --cached --quiet && [[ "$DRY_RUN" -eq 0 ]]; then
      warn "No staged changes to commit."
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      info "Dry run: commit would use message: $COMMIT_MESSAGE"
    else
      info "Committing..."
      git commit -m "$COMMIT_MESSAGE"
    fi
```
Replace with:
```bash
    if git diff --cached --quiet && [[ "$DRY_RUN" -eq 0 ]]; then
      warn "No staged changes to commit."
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      info "Dry run: commit would use message: $COMMIT_MESSAGE"
    else
      info "Changes to be committed:"
      git diff --cached --stat
      printf '\n'

      if [[ "$SKIP_CONFIRM" -eq 0 ]] && ! prompt_yes_no "Commit these changes with message \"$COMMIT_MESSAGE\"?" "y"; then
        git reset >/dev/null
        die "Push cancelled."
      fi

      info "Committing..."
      git commit -m "$COMMIT_MESSAGE"
    fi
```

- [ ] **Step 5: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 6: Build the shared offline test fixture**

All remaining functional tests use a fully-offline setup: a local bare repo as the "remote" (so real `git push`/`git pull` work end-to-end without touching GitHub), with `git-smart.profile`/`owner`/`sshHost` set directly via `git config --local` (bypassing the need for a real GitHub-shaped remote URL, since `parse_github_url` won't match a local file path and `rewrite_remote_if_needed` correctly no-ops when it can't parse the remote).

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
git init --bare "$SANDBOX/remote.git" >/dev/null
mkdir -p "$SANDBOX/work"
cd "$SANDBOX/work"
git init -b main >/dev/null
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "$SANDBOX/remote.git"
git config --local git-smart.profile personal
git config --local git-smart.owner testowner
git config --local git-smart.sshHost github-personal
```
Keep this shell/directory open (or re-`cd "$SANDBOX/work"`) for each of Steps 7-11 below — they all build on this same fixture, adding one file at a time.

- [ ] **Step 7: Functional test — declining unstages and aborts**

```bash
echo "hello" > file1.txt
printf 'n\n' | HOME="$SANDBOX" "$REPO/git-smart" push "test commit"
echo "exit code: $?"
echo "--- commit count (should be 0) ---"
git log --oneline | wc -l
echo "--- file1.txt should be untracked again (unstaged), not staged ---"
git status --porcelain
```
Expected: exit code `1`, commit count `0`, `git status --porcelain` shows `?? file1.txt` (untracked, confirming `git reset` successfully unstaged it — nothing was committed, nothing was pushed).

- [ ] **Step 8: Functional test — confirming proceeds to commit and push**

```bash
printf 'y\n' | HOME="$SANDBOX" "$REPO/git-smart" push "test commit"
echo "exit code: $?"
echo "--- commit count (should be 1) ---"
git log --oneline | wc -l
echo "--- remote should have the branch now ---"
git ls-remote "$SANDBOX/remote.git"
```
Expected: exit code `0`, commit count `1`, `git ls-remote` shows a `refs/heads/main` line — confirming the real end-to-end commit-and-push succeeded after confirming.

- [ ] **Step 9: Functional test — `--yes`/`-y` skips the prompt entirely**

```bash
echo "hello2" > file2.txt
HOME="$SANDBOX" "$REPO/git-smart" push --yes "another commit"
echo "exit code: $?"
echo "--- commit count (should be 2) ---"
git log --oneline | wc -l
```
Expected: exit code `0` (no stdin needed — if the prompt weren't actually skipped, this would hang waiting for input and the test would time out), commit count `2`.

- [ ] **Step 10: Functional test — `--push-only` is unaffected**

```bash
HOME="$SANDBOX" "$REPO/git-smart" push --push-only 2>&1 | grep -c "Changes to be committed"
```
Expected: `0` — the new stat-preview/confirmation block never runs in `--push-only` mode, since that mode skips staging/committing entirely (unchanged from before this feature).

- [ ] **Step 11: Functional test — `--dry-run` is unaffected**

```bash
echo "hello3" > file3.txt
HOME="$SANDBOX" "$REPO/git-smart" push --dry-run "dry run commit" 2>&1 | grep -c "Commit these changes"
```
Expected: `0` — no confirmation prompt is ever reached in dry-run mode (it's a separate `elif` branch from the one the confirmation was added to).

- [ ] **Step 12: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "feat: confirm before committing in git-smart push"
```
