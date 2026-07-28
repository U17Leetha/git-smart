# Fail-Closed Safety Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every interactive prompt fail closed on EOF instead of silently using a default; close the config-injection hole in `save_config`/`load_config`; stop `push` from destroying pre-existing staged changes; and require confirmation before silently rewriting a remote to a different owner.

**Architecture:** Four independent, localized fixes in the same file: `read ... || <fail closed>` added to the three prompt helpers; `save_config` rebuilt with `printf '%q'` quoting plus a `chmod 600`, and `load_config` gains a pre-source permission check; `run_push` gains a pre-staging dirty-index guard; `rewrite_remote_if_needed` gains an owner-mismatch confirmation. The bash version gate (shipped earlier) is tightened from `>= 4` to `>= 4.4`, since the empty-array-under-`set -u` bug it partially addressed is fully closed only at 4.4+, and the new `save_config` code relies on that.

**Tech Stack:** Bash, matching existing conventions. No automated test suite in this repo — verification via sandboxed `HOME` runs, plus this machine's real bash 3.2.57 for the tightened version gate (same technique as the earlier bash-gate task).

---

### Task 1: Fail-closed prompts, config injection fix, staged-index guard, remote-owner confirmation

**Files:**
- Modify: `git-smart` (bash version gate)
- Modify: `git-smart` (`prompt`, `prompt_yes_no`, `resolve_profile_interactively`)
- Modify: `git-smart` (`load_config`, `save_config`)
- Modify: `git-smart` (`run_push`'s staging block)
- Modify: `git-smart` (`rewrite_remote_if_needed`)

- [ ] **Step 1: Tighten the bash version gate to >= 4.4**

Find:
```bash
if (( BASH_VERSINFO[0] < 4 )); then
  printf '[!] git-smart requires bash >= 4 (found %s). On macOS: brew install bash\n' "$BASH_VERSION" >&2
  exit 1
fi
```
Replace with:
```bash
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  printf '[!] git-smart requires bash >= 4.4 (found %s). On macOS: brew install bash\n' "$BASH_VERSION" >&2
  exit 1
fi
```

- [ ] **Step 2: Make `prompt` fail closed on EOF**

Find:
```bash
prompt() {
  local prompt_text="$1"
  local default_value="${2-}"
  local input=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " input
    printf '%s\n' "${input:-$default_value}"
  else
    read -r -p "$prompt_text: " input
    printf '%s\n' "$input"
  fi
}
```
Replace with:
```bash
prompt() {
  local prompt_text="$1"
  local default_value="${2-}"
  local input=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " input || die "No input available (stdin closed)."
    printf '%s\n' "${input:-$default_value}"
  else
    read -r -p "$prompt_text: " input || die "No input available (stdin closed)."
    printf '%s\n' "$input"
  fi
}
```

- [ ] **Step 3: Make `prompt_yes_no` fail closed on EOF**

Find:
```bash
prompt_yes_no() {
  local prompt_text="$1"
  local default_answer="${2:-y}"
  local input=""

  while true; do
    if [[ "$default_answer" == "y" ]]; then
      read -r -p "$prompt_text [Y/n]: " input
      input="${input:-y}"
    else
      read -r -p "$prompt_text [y/N]: " input
      input="${input:-n}"
    fi

    case "${input,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
  done
}
```
Replace with:
```bash
prompt_yes_no() {
  local prompt_text="$1"
  local default_answer="${2:-y}"
  local input=""

  while true; do
    if [[ "$default_answer" == "y" ]]; then
      read -r -p "$prompt_text [Y/n]: " input || return 1
      input="${input:-y}"
    else
      read -r -p "$prompt_text [y/N]: " input || return 1
      input="${input:-n}"
    fi

    case "${input,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
  done
}
```

- [ ] **Step 4: Make `resolve_profile_interactively` fail closed on EOF**

Find:
```bash
resolve_profile_interactively() {
  local answer=""

  while true; do
    read -r -p "Use personal or work profile? [personal/work]: " answer
    case "${answer,,}" in
      personal|p)
        printf 'personal\n'
        return
        ;;
      work|w)
        printf 'work\n'
        return
        ;;
    esac
  done
}
```
Replace with:
```bash
resolve_profile_interactively() {
  local answer=""

  while true; do
    read -r -p "Use personal or work profile? [personal/work]: " answer || die "No input available (stdin closed). Pass --profile personal|work."
    case "${answer,,}" in
      personal|p)
        printf 'personal\n'
        return
        ;;
      work|w)
        printf 'work\n'
        return
        ;;
    esac
  done
}
```

- [ ] **Step 5: Add a permission check to `load_config`**

Find:
```bash
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
```
Replace with:
```bash
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local perms
    perms="$(stat -f '%Lp' "$CONFIG_FILE" 2>/dev/null || stat -c '%a' "$CONFIG_FILE" 2>/dev/null)"
    if [[ -n "$perms" && "${perms: -2}" != "00" ]]; then
      die "$CONFIG_FILE is group/world accessible (permissions: $perms). Run 'chmod 600 $CONFIG_FILE' before continuing."
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
```

- [ ] **Step 6: Rewrite `save_config` to quote every value and `chmod 600` the file**

Find:
```bash
save_config() {
  local personal_owner work_owner

  mkdir -p "$(dirname "$CONFIG_FILE")"

  personal_owner="${GITHUB_PERSONAL_DEFAULT_OWNER:-}"
  work_owner="${GITHUB_WORK_DEFAULT_OWNER:-}"

  cat > "$CONFIG_FILE" <<EOF
GIT_SMART_PERSONAL_DIR="$GIT_SMART_PERSONAL_DIR"
GIT_SMART_WORK_DIR="$GIT_SMART_WORK_DIR"

GITHUB_PERSONAL_HOST="$GITHUB_PERSONAL_HOST"
GITHUB_WORK_HOST="$GITHUB_WORK_HOST"

GITHUB_PERSONAL_OWNERS=(${GITHUB_PERSONAL_OWNERS[*]})
GITHUB_WORK_OWNERS=(${GITHUB_WORK_OWNERS[*]})

GITHUB_PERSONAL_DEFAULT_OWNER="$personal_owner"
GITHUB_WORK_DEFAULT_OWNER="$work_owner"

GIT_SMART_GLOBAL_PROFILE="$GIT_SMART_GLOBAL_PROFILE"
GIT_SMART_WORK_GIT_NAME="$GIT_SMART_WORK_GIT_NAME"
GIT_SMART_WORK_GIT_EMAIL="$GIT_SMART_WORK_GIT_EMAIL"
EOF
}
```
Replace with:
```bash
save_config() {
  local personal_owner work_owner
  local personal_owners_quoted="" work_owners_quoted="" owner

  mkdir -p "$(dirname "$CONFIG_FILE")"

  personal_owner="${GITHUB_PERSONAL_DEFAULT_OWNER:-}"
  work_owner="${GITHUB_WORK_DEFAULT_OWNER:-}"

  for owner in "${GITHUB_PERSONAL_OWNERS[@]}"; do
    personal_owners_quoted+="$(printf '%q ' "$owner")"
  done
  for owner in "${GITHUB_WORK_OWNERS[@]}"; do
    work_owners_quoted+="$(printf '%q ' "$owner")"
  done

  {
    printf 'GIT_SMART_PERSONAL_DIR=%q\n' "$GIT_SMART_PERSONAL_DIR"
    printf 'GIT_SMART_WORK_DIR=%q\n' "$GIT_SMART_WORK_DIR"
    printf '\n'
    printf 'GITHUB_PERSONAL_HOST=%q\n' "$GITHUB_PERSONAL_HOST"
    printf 'GITHUB_WORK_HOST=%q\n' "$GITHUB_WORK_HOST"
    printf '\n'
    printf 'GITHUB_PERSONAL_OWNERS=(%s)\n' "$personal_owners_quoted"
    printf 'GITHUB_WORK_OWNERS=(%s)\n' "$work_owners_quoted"
    printf '\n'
    printf 'GITHUB_PERSONAL_DEFAULT_OWNER=%q\n' "$personal_owner"
    printf 'GITHUB_WORK_DEFAULT_OWNER=%q\n' "$work_owner"
    printf '\n'
    printf 'GIT_SMART_GLOBAL_PROFILE=%q\n' "$GIT_SMART_GLOBAL_PROFILE"
    printf 'GIT_SMART_WORK_GIT_NAME=%q\n' "$GIT_SMART_WORK_GIT_NAME"
    printf 'GIT_SMART_WORK_GIT_EMAIL=%q\n' "$GIT_SMART_WORK_GIT_EMAIL"
  } > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}
```

- [ ] **Step 7: Guard `run_push` against a pre-existing staged index**

Find:
```bash
  if [[ "$PUSH_ONLY" -eq 0 ]]; then
    info "Staging changes..."
    [[ "$DRY_RUN" -eq 1 ]] || git add -A
```
Replace with:
```bash
  if [[ "$PUSH_ONLY" -eq 0 ]]; then
    if [[ "$DRY_RUN" -eq 0 ]] && ! git diff --cached --quiet; then
      die "You already have staged changes. Commit them yourself first, or run 'git-smart push --push-only' to push without staging/committing anything new."
    fi

    info "Staging changes..."
    [[ "$DRY_RUN" -eq 1 ]] || git add -A
```

- [ ] **Step 8: Confirm before rewriting a remote to a different owner**

Find:
```bash
  new_url="$(build_remote_url "$TARGET_OWNER" "$REMOTE_REPO" "$TARGET_PROFILE")"
  if [[ "$REMOTE_URL" == "$new_url" ]]; then
    return
  fi

  info "Updating $REMOTE remote to use profile '$TARGET_PROFILE'"
```
Replace with:
```bash
  new_url="$(build_remote_url "$TARGET_OWNER" "$REMOTE_REPO" "$TARGET_PROFILE")"
  if [[ "$REMOTE_URL" == "$new_url" ]]; then
    return
  fi

  if [[ -n "$REMOTE_OWNER" && "$TARGET_OWNER" != "$REMOTE_OWNER" ]]; then
    warn "The remote's current owner is '$REMOTE_OWNER', but git-smart is about to retarget it to '$TARGET_OWNER'."
    prompt_yes_no "Retarget $REMOTE from ${REMOTE_OWNER}/${REMOTE_REPO} to ${TARGET_OWNER}/${REMOTE_REPO}?" "n" \
      || die "Aborted. If '$REMOTE_OWNER' is correct, run 'git-smart switch --owner $REMOTE_OWNER' to fix the saved context instead."
  fi

  info "Updating $REMOTE remote to use profile '$TARGET_PROFILE'"
```

- [ ] **Step 9: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 10: Functional test — tightened version gate still refuses real bash 3.2.57**

```bash
REPO="<your working directory>"
/bin/bash --version | head -1
```
If that prints `version 3.2...`, continue:
```bash
/bin/bash "$REPO/git-smart" help
echo "exit code: $?"
```
Expected: `[!] git-smart requires bash >= 4.4 (found 3.2.57(1)-release). On macOS: brew install bash`, exit code `1`. If this machine's `/bin/bash` isn't 3.2, note that and skip to Step 11, relying on the syntax check + normal runs for coverage.

- [ ] **Step 11: Functional test — `prompt_yes_no` returns "no" on EOF regardless of default**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
mkdir -p "$SANDBOX/proj"
cd "$SANDBOX/proj"
git init -b main >/dev/null
git config user.name "Test"
git config user.email "test@example.com"
echo hi > f.txt
git add f.txt
git commit -m first >/dev/null
git config --local git-smart.profile personal
git config --local git-smart.owner testowner
git config --local git-smart.sshHost github-personal
git remote add origin /tmp/nonexistent-remote.git
echo more >> f.txt
HOME="$SANDBOX" "$REPO/git-smart" push "test" < /dev/null
echo "exit code: $?"
git log --oneline | wc -l
```
Expected: exit code `1` (the confirmation prompt's default is `"n"` already per the earlier push-guard fix, so this specific case doesn't distinguish old vs new behavior on its own — the important assertion is that it does NOT hang and does NOT proceed to commit): commit count stays `1` (only the original "first" commit, nothing new committed), confirming the decline-on-EOF path correctly aborted rather than committing.

- [ ] **Step 12: Functional test — `prompt` dies cleanly on EOF instead of proceeding with an empty value**

```bash
SANDBOX2="$(mktemp -d)"
REPO="<your working directory>"
mkdir -p "$SANDBOX2/.config"
cat > "$SANDBOX2/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX2/Personal"
GIT_SMART_WORK_DIR="$SANDBOX2/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=()
GITHUB_WORK_OWNERS=()
GITHUB_PERSONAL_DEFAULT_OWNER=""
GITHUB_WORK_DEFAULT_OWNER=""
EOF
HOME="$SANDBOX2" "$REPO/git-smart" init --profile personal < /dev/null
echo "exit code: $?"
```
This omits the repo-name positional argument, so `run_init` calls `prompt "Repository name"` (no default) with closed stdin.
Expected: `[!] No input available (stdin closed).`, exit code `1` — not a hang, not a silent empty-name proceed.

- [ ] **Step 13: Functional test — `resolve_profile_interactively` dies instead of looping forever on EOF**

```bash
SANDBOX3="$(mktemp -d)"
REPO="<your working directory>"
mkdir -p "$SANDBOX3/proj"
cd "$SANDBOX3/proj"
git init -b main >/dev/null
git remote add origin git@github.com:someorg/somerepo.git
timeout 5 env HOME="$SANDBOX3" "$REPO/git-smart" switch < /dev/null
echo "exit code: $?"
```
`switch` with no `--profile` and an owner (`someorg`) not in any configured owners list falls through to `resolve_profile_interactively`. Expected: exit code `1` with the "No input available" message, well within the 5-second timeout — if this instead hangs and `timeout` kills it, that's exit code `124`, meaning the fix didn't take. (If `timeout` isn't available on this system, use `gtimeout` from coreutils, or just confirm manually that the command returns promptly rather than hanging.)

- [ ] **Step 14: Functional test — config injection is closed (full round-trip)**

```bash
SANDBOX4="$(mktemp -d)"
REPO="<your working directory>"
HOME="$SANDBOX4" git config --global user.name "Test Work"
HOME="$SANDBOX4" git config --global user.email "work@example.com"
INJECTION='harmless$(touch /tmp/PWNED_gitsmart_test)evil'
printf '%s\n' \
  "U17Leetha" \
  "$INJECTION" \
  "$SANDBOX4/Personal" "$SANDBOX4/Work" \
  "github-personal" "github-work" "n" "none" \
  | HOME="$SANDBOX4" "$REPO/git-smart" setup > /dev/null 2>&1

echo "--- did the injection execute? (file must NOT exist) ---"
[[ -f /tmp/PWNED_gitsmart_test ]] && echo "FAIL: injection executed" || echo "PASS: no execution"

echo "--- does the value round-trip correctly on the NEXT load? ---"
HOME="$SANDBOX4" "$REPO/git-smart" doctor 2>&1 | grep "Work owners"
```
Expected: `PASS: no execution` (the file was never created, proving neither `save_config`'s write nor the next `load_config`'s `source` executed the embedded command substitution), and the `doctor` output shows `Work owners        : harmless$(touch /tmp/PWNED_gitsmart_test)evil` as a literal string — the exact original value, correctly round-tripped, not corrupted or truncated.

- [ ] **Step 15: Functional test — saved config is `chmod 600`**

```bash
stat -f '%Lp' "$SANDBOX4/.config/git-smart.conf" 2>/dev/null || stat -c '%a' "$SANDBOX4/.config/git-smart.conf"
```
Expected: `600`.

- [ ] **Step 16: Functional test — `load_config` refuses an insecure config file**

```bash
chmod 644 "$SANDBOX4/.config/git-smart.conf"
HOME="$SANDBOX4" "$REPO/git-smart" doctor 2>&1
echo "exit code: $?"
chmod 600 "$SANDBOX4/.config/git-smart.conf"
HOME="$SANDBOX4" "$REPO/git-smart" doctor > /dev/null 2>&1
echo "exit code after re-securing: $?"
```
Expected: first run dies with `... is group/world accessible (permissions: 644). Run 'chmod 600 ...' before continuing.`, exit code `1`. Second run (after re-securing to 600) succeeds, exit code `0`.

- [ ] **Step 17: Functional test — `push` refuses when the index already has staged changes**

```bash
SANDBOX5="$(mktemp -d)"
REPO="<your working directory>"
git init --bare -b main "$SANDBOX5/remote.git" >/dev/null
mkdir -p "$SANDBOX5/work"
cd "$SANDBOX5/work"
git init -b main >/dev/null
git config user.name "Test"
git config user.email "test@example.com"
git remote add origin "$SANDBOX5/remote.git"
git config --local git-smart.profile personal
git config --local git-smart.owner testowner
git config --local git-smart.sshHost github-personal
echo "already staged" > staged.txt
git add staged.txt

HOME="$SANDBOX5" "$REPO/git-smart" push --yes "should refuse" 2>&1
echo "exit code: $?"
git status --porcelain
```
Expected: `[!] You already have staged changes. Commit them yourself first, or run 'git-smart push --push-only' to push without staging/committing anything new.`, exit code `1`, and `git status --porcelain` still shows `staged.txt` as staged (`A  staged.txt`) — untouched, proving git-smart didn't run `git add -A` or `git reset` at all in this case.

- [ ] **Step 18: Functional test — remote-owner-drift confirmation fires only when the owner actually changes**

```bash
SANDBOX6="$(mktemp -d)"
REPO="<your working directory>"
mkdir -p "$SANDBOX6/.config" "$SANDBOX6/proj"
cat > "$SANDBOX6/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX6/Personal"
GIT_SMART_WORK_DIR="$SANDBOX6/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=(realowner otherowner)
GITHUB_WORK_OWNERS=(acme-work)
GITHUB_PERSONAL_DEFAULT_OWNER="realowner"
GITHUB_WORK_DEFAULT_OWNER="acme-work"
EOF
cd "$SANDBOX6/proj"
git init -b main >/dev/null
git remote add origin git@github-personal:realowner/proj.git

echo "--- same-owner switch (should NOT prompt, no 'Retarget' text) ---"
HOME="$SANDBOX6" "$REPO/git-smart" switch --profile personal < /dev/null 2>&1 | grep -c "Retarget"

echo "--- explicit different-owner switch, declining (should abort, remote unchanged) ---"
HOME="$SANDBOX6" "$REPO/git-smart" switch --profile personal --owner otherowner < /dev/null 2>&1
echo "exit code: $?"
git remote get-url origin
```
Expected: first block's grep count is `0` (no confirmation text at all for a same-owner switch — `switch` with no explicit `--owner` inherits the current remote's owner, so nothing changed). Second block: since stdin is closed (`< /dev/null`), the confirmation prompt itself fails closed (per Step 3's fix) and returns "no", so it dies with the `Aborted. If 'realowner' is correct...` message, exit code `1`, and `git remote get-url origin` still shows the original `realowner` URL, unchanged.

- [ ] **Step 19: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "fix: fail closed on EOF prompts, quote config values, guard staged index, confirm remote owner changes"
```
