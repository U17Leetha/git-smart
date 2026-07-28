# Global Default Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `git-smart global` command (plus `setup`/`doctor` integration) that makes one profile — normally `work` — the machine-wide SSH and git-identity default, while personal repos stay opt-in per directory exactly as they work today; then apply it on this machine with the new `github_axe` key.

**Architecture:** A single new core function, `apply_global_profile`, does the actual work (point the bare `Host github.com` SSH stanza at a profile's key, set global `git config user.name`/`user.email`, persist which profile is active). `run_global` (new command), `run_setup` (one new prompt), and `run_doctor` (one new report/suggestion block) all call into it or read the same config fields. No new files — this is all in the single `git-smart` script, matching the existing single-file CLI structure.

**Tech Stack:** Bash (existing script conventions: `set -euo pipefail`, `info`/`warn`/`die` helpers, awk-based SSH config editing). No test framework exists in this repo (see README/`install.sh --dry-run` for the existing manual-verification convention) — every task below is verified with real subprocess runs against a sandboxed `$HOME` (via `mktemp -d`), never against the developer's actual `~/.ssh/config` or `~/.gitconfig`, until the final task which deliberately applies to the real machine.

---

### Task 1: Discard the in-progress uncommitted diff

**Files:**
- Modify: `git-smart` (revert to HEAD)
- Modify: `README.md` (revert to HEAD)

- [ ] **Step 1: Confirm what's about to be discarded**

Run: `git -C /Users/matt/Development/Personal/git-smart status --short`
Expected output:
```
 M README.md
 M git-smart
```

- [ ] **Step 2: Discard the uncommitted changes**

Run: `git -C /Users/matt/Development/Personal/git-smart checkout -- README.md git-smart`

- [ ] **Step 3: Verify clean working tree**

Run: `git -C /Users/matt/Development/Personal/git-smart status --short`
Expected output: (empty — nothing printed)

No commit needed for this step (nothing staged; the tree now matches HEAD).

---

### Task 2: Add global-profile config fields and identity accessors

**Files:**
- Modify: `git-smart:10-12` (top-level defaults)
- Modify: `git-smart:232-254` (`load_config`)
- Modify: `git-smart:256-277` (`save_config`)
- Modify: `git-smart:465-471` (after `profile_default_owner`)

- [ ] **Step 1: Add top-level defaults for the work git identity**

In `git-smart`, find:
```bash
DEFAULT_PERSONAL_DIR="${HOME}/Development/Personal"
DEFAULT_WORK_DIR="${HOME}/Development/Work"
```
Replace with:
```bash
DEFAULT_PERSONAL_DIR="${HOME}/Development/Personal"
DEFAULT_WORK_DIR="${HOME}/Development/Work"
DEFAULT_WORK_GIT_AUTHOR_NAME="$(git config --global --get user.name 2>/dev/null || true)"
DEFAULT_WORK_GIT_AUTHOR_EMAIL="$(git config --global --get user.email 2>/dev/null || true)"
```

- [ ] **Step 2: Load the new fields in `load_config`**

Find:
```bash
  GIT_SMART_PERSONAL_DIR="${GIT_SMART_PERSONAL_DIR:-$DEFAULT_PERSONAL_DIR}"
  GIT_SMART_WORK_DIR="${GIT_SMART_WORK_DIR:-$DEFAULT_WORK_DIR}"

  if ! declare -p GITHUB_PERSONAL_OWNERS >/dev/null 2>&1; then
```
Replace with:
```bash
  GIT_SMART_PERSONAL_DIR="${GIT_SMART_PERSONAL_DIR:-$DEFAULT_PERSONAL_DIR}"
  GIT_SMART_WORK_DIR="${GIT_SMART_WORK_DIR:-$DEFAULT_WORK_DIR}"
  GIT_SMART_GLOBAL_PROFILE="${GIT_SMART_GLOBAL_PROFILE:-}"
  GIT_SMART_WORK_GIT_NAME="${GIT_SMART_WORK_GIT_NAME:-$DEFAULT_WORK_GIT_AUTHOR_NAME}"
  GIT_SMART_WORK_GIT_EMAIL="${GIT_SMART_WORK_GIT_EMAIL:-$DEFAULT_WORK_GIT_AUTHOR_EMAIL}"

  if ! declare -p GITHUB_PERSONAL_OWNERS >/dev/null 2>&1; then
```

- [ ] **Step 3: Persist the new fields in `save_config`**

Find:
```bash
GITHUB_PERSONAL_DEFAULT_OWNER="$personal_owner"
GITHUB_WORK_DEFAULT_OWNER="$work_owner"
EOF
}
```
Replace with:
```bash
GITHUB_PERSONAL_DEFAULT_OWNER="$personal_owner"
GITHUB_WORK_DEFAULT_OWNER="$work_owner"

GIT_SMART_GLOBAL_PROFILE="$GIT_SMART_GLOBAL_PROFILE"
GIT_SMART_WORK_GIT_NAME="$GIT_SMART_WORK_GIT_NAME"
GIT_SMART_WORK_GIT_EMAIL="$GIT_SMART_WORK_GIT_EMAIL"
EOF
}
```

- [ ] **Step 4: Add `profile_git_name`/`profile_git_email` accessors**

Find:
```bash
profile_default_owner() {
  case "$1" in
    personal) printf '%s\n' "$GITHUB_PERSONAL_DEFAULT_OWNER" ;;
    work) printf '%s\n' "$GITHUB_WORK_DEFAULT_OWNER" ;;
    *) printf '\n' ;;
  esac
}

profile_host() {
```
Replace with:
```bash
profile_default_owner() {
  case "$1" in
    personal) printf '%s\n' "$GITHUB_PERSONAL_DEFAULT_OWNER" ;;
    work) printf '%s\n' "$GITHUB_WORK_DEFAULT_OWNER" ;;
    *) printf '\n' ;;
  esac
}

# Only "work" has a persisted global git identity today — personal repos don't
# get repo-local identity switching (out of scope, see design spec's non-goals).
profile_git_name() {
  case "$1" in
    work) printf '%s\n' "$GIT_SMART_WORK_GIT_NAME" ;;
    *) printf '\n' ;;
  esac
}

profile_git_email() {
  case "$1" in
    work) printf '%s\n' "$GIT_SMART_WORK_GIT_EMAIL" ;;
    *) printf '\n' ;;
  esac
}

profile_host() {
```

- [ ] **Step 5: Syntax check**

Run: `bash -n /Users/matt/Development/Personal/git-smart/git-smart`
Expected: no output, exit code 0.

- [ ] **Step 6: Sanity-check the new fields load and save round-trip**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
HOME="$SANDBOX" git config --global user.name "Test Work"
HOME="$SANDBOX" git config --global user.email "work@example.com"
HOME="$SANDBOX" "$REPO/git-smart" doctor >/dev/null 2>&1 || true
cat "$SANDBOX/.config/git-smart.conf" 2>/dev/null | grep -E "GIT_SMART_WORK_GIT_(NAME|EMAIL)|GIT_SMART_GLOBAL_PROFILE" || echo "NO CONFIG FILE YET (expected: doctor doesn't call save_config)"
rm -rf "$SANDBOX"
```
Expected: `doctor` doesn't write a config file (only `setup`/`global` do via `save_config`), so this prints "NO CONFIG FILE YET (expected...)" — this step just confirms the script still runs without error after the edits (no syntax/runtime crash on `load_config`). Full functional coverage of these fields happens in Task 3 and Task 5.

- [ ] **Step 7: Commit**

```bash
cd /Users/matt/Development/Personal/git-smart
git add git-smart
git commit -m "feat: add global-profile config fields and git-identity accessors"
```

---

### Task 3: Implement `git-smart global` command

**Files:**
- Modify: `git-smart:87-113` (`usage`)
- Modify: `git-smart:210-230` (add `usage_global`, between `usage_switch` and `usage_doctor`)
- Modify: `git-smart:279-300` (`parse_global_args`)
- Modify: `git-smart:302-341` (`parse_common_option`)
- Modify: `git-smart:343-443` (`parse_command_args`)
- Modify: `git-smart:974-993` (add `apply_global_profile` + `run_global` after `show_public_key_details`, before `run_setup`)
- Modify: `git-smart:1410-1428` (`main`)

- [ ] **Step 1: Add `global` to the usage banner**

Find:
```bash
  switch    Rebind the current repo to personal or work
  doctor    Diagnose config, SSH aliases, and current repo context
  help      Show help
```
Replace with:
```bash
  switch    Rebind the current repo to personal or work
  global    Set the machine-wide default profile (SSH + git identity)
  doctor    Diagnose config, SSH aliases, and current repo context
  help      Show help
```

- [ ] **Step 2: Add `usage_global`**

Find:
```bash
usage_switch() {
  cat <<'EOF'
Usage: git-smart switch [options]

Options:
  --profile personal|work
  --owner OWNER
  --remote NAME
  --dry-run
EOF
}

usage_doctor() {
```
Replace with:
```bash
usage_switch() {
  cat <<'EOF'
Usage: git-smart switch [options]

Options:
  --profile personal|work
  --owner OWNER
  --remote NAME
  --dry-run
EOF
}

usage_global() {
  cat <<'EOF'
Usage: git-smart global [options]

Options:
  --profile personal|work
  --dry-run

Sets the machine-wide default: the bare github.com SSH host and the
global git config identity. If --profile is omitted, uses the saved
GIT_SMART_GLOBAL_PROFILE or prompts interactively.
EOF
}

usage_doctor() {
```

- [ ] **Step 3: Accept `global` as a command**

Find:
```bash
    setup|init|clone|push|pull|status|where|open|switch|doctor)
      COMMAND="$1"
      shift
      ;;
```
Replace with:
```bash
    setup|init|clone|push|pull|status|where|open|switch|global|doctor)
      COMMAND="$1"
      shift
      ;;
```

- [ ] **Step 4: Route `-h`/`--help` for `global`**

Find:
```bash
        open) usage_open ;;
        switch) usage_switch ;;
        doctor) usage_doctor ;;
      esac
```
Replace with:
```bash
        open) usage_open ;;
        switch) usage_switch ;;
        global) usage_global ;;
        doctor) usage_doctor ;;
      esac
```

- [ ] **Step 5: Let `global` fall through the common `--profile`/`--dry-run` parsing**

Find:
```bash
      pull|status|where|open|doctor)
        break
        ;;
```
Replace with:
```bash
      pull|status|where|open|global|doctor)
        break
        ;;
```

- [ ] **Step 6: Implement `apply_global_profile` and `run_global`**

Find:
```bash
  if copy_file_to_clipboard "$pub_path"; then
    info "Copied $label public key to clipboard."
  else
    warn "No clipboard helper found. Copy the key above into GitHub manually."
  fi
}

run_setup() {
```
Replace with:
```bash
  if copy_file_to_clipboard "$pub_path"; then
    info "Copied $label public key to clipboard."
  else
    warn "No clipboard helper found. Copy the key above into GitHub manually."
  fi
}

apply_global_profile() {
  local profile="$1"
  local host_alias key_path current_default git_name git_email

  host_alias="$(profile_host "$profile")"
  key_path="$(current_identity_for_host_config "$host_alias")"

  [[ -n "$key_path" ]] || die "No SSH key configured for '$host_alias' yet. Run 'git-smart setup' first."

  info "Applying '$profile' as the global default profile"

  current_default="$(current_identity_for_host_config "$GITHUB_DEFAULT_HOST")"
  if [[ -z "$current_default" ]]; then
    if [[ "$DRY_RUN" -eq 0 ]]; then
      append_ssh_host_if_missing "$GITHUB_DEFAULT_HOST" "$key_path"
    else
      printf '[*] Dry run: add Host %s with IdentityFile %s\n' "$GITHUB_DEFAULT_HOST" "$key_path"
    fi
  elif [[ "$(expand_path "$current_default")" != "$(expand_path "$key_path")" ]]; then
    if [[ "$DRY_RUN" -eq 0 ]]; then
      update_ssh_host_identity "$GITHUB_DEFAULT_HOST" "$key_path"
    else
      printf '[*] Dry run: update Host %s IdentityFile to %s\n' "$GITHUB_DEFAULT_HOST" "$key_path"
    fi
  fi
  info "SSH default (Host $GITHUB_DEFAULT_HOST) -> $key_path"

  git_name="$(profile_git_name "$profile")"
  git_email="$(profile_git_email "$profile")"

  if [[ -n "$git_name" ]]; then
    [[ "$DRY_RUN" -eq 0 ]] && git config --global user.name "$git_name"
    info "Global git user.name -> $git_name"
  else
    info "No git author name configured for '$profile'; skipping global git identity name."
  fi

  if [[ -n "$git_email" ]]; then
    [[ "$DRY_RUN" -eq 0 ]] && git config --global user.email "$git_email"
    info "Global git user.email -> $git_email"
  else
    info "No git author email configured for '$profile'; skipping global git identity email."
  fi

  GIT_SMART_GLOBAL_PROFILE="$profile"
  [[ "$DRY_RUN" -eq 0 ]] && save_config
}

run_global() {
  local requested_profile="$PROFILE"

  if [[ "$requested_profile" == "auto" ]]; then
    if [[ -n "$GIT_SMART_GLOBAL_PROFILE" ]]; then
      requested_profile="$GIT_SMART_GLOBAL_PROFILE"
    else
      requested_profile="$(resolve_profile_interactively)"
    fi
  fi

  apply_global_profile "$requested_profile"

  printf '\n'
  info "Global default profile is now '$requested_profile'."
}

run_setup() {
```

- [ ] **Step 7: Dispatch `global` in `main`**

Find:
```bash
    switch) run_switch ;;
    doctor) run_doctor ;;
    *) usage; exit 1 ;;
```
Replace with:
```bash
    switch) run_switch ;;
    global) run_global ;;
    doctor) run_doctor ;;
    *) usage; exit 1 ;;
```

- [ ] **Step 8: Syntax check**

Run: `bash -n /Users/matt/Development/Personal/git-smart/git-smart`
Expected: no output, exit code 0.

- [ ] **Step 9: Functional test — apply for real (in a sandbox `$HOME`)**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
mkdir -p "$SANDBOX/.ssh" "$SANDBOX/.config"

cat > "$SANDBOX/.ssh/config" <<EOF
Host github-work
  HostName github.com
  User git
  IdentityFile $SANDBOX/.ssh/id_ed25519_work
  IdentitiesOnly yes
EOF
touch "$SANDBOX/.ssh/id_ed25519_work"

cat > "$SANDBOX/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX/Personal"
GIT_SMART_WORK_DIR="$SANDBOX/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=()
GITHUB_WORK_OWNERS=()
GITHUB_PERSONAL_DEFAULT_OWNER=""
GITHUB_WORK_DEFAULT_OWNER=""
GIT_SMART_WORK_GIT_NAME="Test Work"
GIT_SMART_WORK_GIT_EMAIL="work@example.com"
EOF

HOME="$SANDBOX" "$REPO/git-smart" global --profile work

echo "--- bare github.com stanza ---"
grep -A4 "^Host github.com$" "$SANDBOX/.ssh/config"
echo "--- global git identity ---"
HOME="$SANDBOX" git config --global --get user.name
HOME="$SANDBOX" git config --global --get user.email
echo "--- persisted profile ---"
grep GIT_SMART_GLOBAL_PROFILE "$SANDBOX/.config/git-smart.conf"

rm -rf "$SANDBOX"
```
Expected:
- The `Host github.com` block's `IdentityFile` is `$SANDBOX/.ssh/id_ed25519_work`.
- `user.name` prints `Test Work`, `user.email` prints `work@example.com`.
- `GIT_SMART_GLOBAL_PROFILE="work"` is present in the config file.

- [ ] **Step 10: Functional test — `--dry-run` makes no changes**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
mkdir -p "$SANDBOX/.ssh" "$SANDBOX/.config"

cat > "$SANDBOX/.ssh/config" <<EOF
Host github-work
  HostName github.com
  User git
  IdentityFile $SANDBOX/.ssh/id_ed25519_work
  IdentitiesOnly yes
EOF
touch "$SANDBOX/.ssh/id_ed25519_work"

cat > "$SANDBOX/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX/Personal"
GIT_SMART_WORK_DIR="$SANDBOX/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=()
GITHUB_WORK_OWNERS=()
GITHUB_PERSONAL_DEFAULT_OWNER=""
GITHUB_WORK_DEFAULT_OWNER=""
GIT_SMART_WORK_GIT_NAME="Test Work"
GIT_SMART_WORK_GIT_EMAIL="work@example.com"
EOF

BEFORE_SSH="$(sha256sum "$SANDBOX/.ssh/config" | awk '{print $1}')"
BEFORE_CONF="$(sha256sum "$SANDBOX/.config/git-smart.conf" | awk '{print $1}')"

HOME="$SANDBOX" "$REPO/git-smart" global --profile work --dry-run | grep -i "dry run"

AFTER_SSH="$(sha256sum "$SANDBOX/.ssh/config" | awk '{print $1}')"
AFTER_CONF="$(sha256sum "$SANDBOX/.config/git-smart.conf" | awk '{print $1}')"

[[ "$BEFORE_SSH" == "$AFTER_SSH" ]] && echo "SSH config unchanged: OK" || echo "SSH config CHANGED: FAIL"
[[ "$BEFORE_CONF" == "$AFTER_CONF" ]] && echo "git-smart.conf unchanged: OK" || echo "git-smart.conf CHANGED: FAIL"

rm -rf "$SANDBOX"
```
Expected: a `[*] Dry run: add Host github.com...` line printed, and both `OK` lines — no files were touched.

- [ ] **Step 11: Functional test — missing key errors clearly**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
mkdir -p "$SANDBOX/.config"
cat > "$SANDBOX/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX/Personal"
GIT_SMART_WORK_DIR="$SANDBOX/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=()
GITHUB_WORK_OWNERS=()
GITHUB_PERSONAL_DEFAULT_OWNER=""
GITHUB_WORK_DEFAULT_OWNER=""
EOF

HOME="$SANDBOX" "$REPO/git-smart" global --profile work; echo "exit code: $?"
rm -rf "$SANDBOX"
```
Expected: prints `[!] No SSH key configured for 'github-work' yet. Run 'git-smart setup' first.` to stderr, then `exit code: 1` (the `;` runs `echo` regardless of the preceding command's status, so it reports `die`'s `exit 1`).

- [ ] **Step 12: Commit**

```bash
cd /Users/matt/Development/Personal/git-smart
git add git-smart
git commit -m "feat: add git-smart global command for machine-wide default profile"
```

---

### Task 4: `doctor` reports global-profile drift

**Files:**
- Modify: `git-smart:1336-1337` (local var declarations)
- Modify: `git-smart:1362-1365` (insert new reporting block)

- [ ] **Step 1: Add new local variables**

Find:
```bash
run_doctor() {
  local current_url="" identity_personal="" identity_work="" repo_profile="" repo_owner="" repo_host=""
  local suggestions=()
```
Replace with:
```bash
run_doctor() {
  local current_url="" identity_personal="" identity_work="" repo_profile="" repo_owner="" repo_host=""
  local expected_default_key="" actual_default_key="" expected_git_name="" expected_git_email=""
  local actual_git_name="" actual_git_email=""
  local suggestions=()
```

- [ ] **Step 2: Insert the global-profile report**

Find:
```bash
  if [[ -n "$identity_work" ]]; then
    info "Work identity    : $identity_work"
  else
    suggestions+=("Add SSH config for '$GITHUB_WORK_HOST' so work repos use the correct key.")
  fi
  printf '\n'

  if [[ ${#GITHUB_PERSONAL_OWNERS[@]} -eq 0 ]]; then
```
Replace with:
```bash
  if [[ -n "$identity_work" ]]; then
    info "Work identity    : $identity_work"
  else
    suggestions+=("Add SSH config for '$GITHUB_WORK_HOST' so work repos use the correct key.")
  fi
  printf '\n'

  info "Global default profile: ${GIT_SMART_GLOBAL_PROFILE:-"(unset)"}"
  if [[ -n "$GIT_SMART_GLOBAL_PROFILE" ]]; then
    expected_default_key="$(current_identity_for_host_config "$(profile_host "$GIT_SMART_GLOBAL_PROFILE")")"
    actual_default_key="$(current_identity_for_host_config "$GITHUB_DEFAULT_HOST")"
    info "Bare $GITHUB_DEFAULT_HOST identity   : ${actual_default_key:-"(unset)"}"

    if [[ -n "$expected_default_key" && "$(expand_path "$actual_default_key")" != "$(expand_path "$expected_default_key")" ]]; then
      suggestions+=("Bare '$GITHUB_DEFAULT_HOST' SSH identity does not match the global profile ('$GIT_SMART_GLOBAL_PROFILE'). Run 'git-smart global --profile $GIT_SMART_GLOBAL_PROFILE' to re-apply it.")
    fi

    expected_git_name="$(profile_git_name "$GIT_SMART_GLOBAL_PROFILE")"
    expected_git_email="$(profile_git_email "$GIT_SMART_GLOBAL_PROFILE")"
    actual_git_name="$(git config --global --get user.name 2>/dev/null || true)"
    actual_git_email="$(git config --global --get user.email 2>/dev/null || true)"
    info "Global git user.name    : ${actual_git_name:-"(unset)"}"
    info "Global git user.email   : ${actual_git_email:-"(unset)"}"

    if [[ -n "$expected_git_name" && "$actual_git_name" != "$expected_git_name" ]]; then
      suggestions+=("Global git user.name does not match the '$GIT_SMART_GLOBAL_PROFILE' profile. Run 'git-smart global --profile $GIT_SMART_GLOBAL_PROFILE' to re-apply it.")
    fi
    if [[ -n "$expected_git_email" && "$actual_git_email" != "$expected_git_email" ]]; then
      suggestions+=("Global git user.email does not match the '$GIT_SMART_GLOBAL_PROFILE' profile. Run 'git-smart global --profile $GIT_SMART_GLOBAL_PROFILE' to re-apply it.")
    fi
  else
    suggestions+=("No global default profile is set. Run 'git-smart global --profile work' (or personal) to make one profile the machine-wide default for tools outside git-smart.")
  fi
  printf '\n'

  if [[ ${#GITHUB_PERSONAL_OWNERS[@]} -eq 0 ]]; then
```

- [ ] **Step 3: Syntax check**

Run: `bash -n /Users/matt/Development/Personal/git-smart/git-smart`
Expected: no output, exit code 0.

- [ ] **Step 4: Functional test — unset, then applied, then drifted**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
mkdir -p "$SANDBOX/.ssh" "$SANDBOX/.config"

cat > "$SANDBOX/.ssh/config" <<EOF
Host github-work
  HostName github.com
  User git
  IdentityFile $SANDBOX/.ssh/id_ed25519_work
  IdentitiesOnly yes
Host github-personal
  HostName github.com
  User git
  IdentityFile $SANDBOX/.ssh/id_ed25519_personal
  IdentitiesOnly yes
EOF
touch "$SANDBOX/.ssh/id_ed25519_work" "$SANDBOX/.ssh/id_ed25519_personal"

cat > "$SANDBOX/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX/Personal"
GIT_SMART_WORK_DIR="$SANDBOX/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=()
GITHUB_WORK_OWNERS=()
GITHUB_PERSONAL_DEFAULT_OWNER=""
GITHUB_WORK_DEFAULT_OWNER=""
GIT_SMART_WORK_GIT_NAME="Test Work"
GIT_SMART_WORK_GIT_EMAIL="work@example.com"
EOF

echo "=== 1) before applying: expect (unset) + suggestion ==="
HOME="$SANDBOX" "$REPO/git-smart" doctor 2>&1 | grep -i "global"

echo "=== 2) after applying: expect no mismatch suggestions ==="
HOME="$SANDBOX" "$REPO/git-smart" global --profile work >/dev/null
HOME="$SANDBOX" "$REPO/git-smart" doctor 2>&1 | grep -i "global\|does not match"

echo "=== 3) after manual drift: expect mismatch suggestion ==="
HOME="$SANDBOX" git config --global user.email "someone-else@example.com"
HOME="$SANDBOX" "$REPO/git-smart" doctor 2>&1 | grep -i "does not match"

rm -rf "$SANDBOX"
```
Expected:
- Block 1: shows `Global default profile: (unset)` and a suggestion to run `git-smart global --profile work`.
- Block 2: shows `Global default profile: work`, matching identity/name/email lines, and **no** "does not match" suggestion lines.
- Block 3: prints a "Global git user.email does not match..." suggestion.

- [ ] **Step 5: Commit**

```bash
cd /Users/matt/Development/Personal/git-smart
git add git-smart
git commit -m "feat: report global-profile drift in git-smart doctor"
```

---

### Task 5: Wire the global-profile prompt into `setup`

**Files:**
- Modify: `git-smart:995-997` (local var declarations)
- Modify: `git-smart:1053-1056` (insert new prompt after SSH host config block)

- [ ] **Step 1: Add the `global_profile` local variable**

Find:
```bash
run_setup() {
  local personal_owner work_owner personal_dir work_dir personal_host work_host
  local personal_key work_key personal_current work_current
```
Replace with:
```bash
run_setup() {
  local personal_owner work_owner personal_dir work_dir personal_host work_host
  local personal_key work_key personal_current work_current
  local global_profile
```

- [ ] **Step 2: Add the prompt after the SSH host config block**

Find:
```bash
    if [[ "$DRY_RUN" -eq 0 ]]; then
      show_public_key_details "personal" "$personal_key"
      show_public_key_details "work" "$work_key"
    fi
  fi

  printf '\n'
  info "Next steps:"
```
Replace with:
```bash
    if [[ "$DRY_RUN" -eq 0 ]]; then
      show_public_key_details "personal" "$personal_key"
      show_public_key_details "work" "$work_key"
    fi
  fi

  global_profile="$(prompt "Global default profile for tools outside git-smart (personal/work, blank = skip)" "$GIT_SMART_GLOBAL_PROFILE")"
  case "$global_profile" in
    personal|work)
      apply_global_profile "$global_profile"
      ;;
    "")
      :
      ;;
    *)
      warn "Unknown profile '$global_profile'; skipping global default setup."
      ;;
  esac

  printf '\n'
  info "Next steps:"
```

- [ ] **Step 3: Syntax check**

Run: `bash -n /Users/matt/Development/Personal/git-smart/git-smart`
Expected: no output, exit code 0.

- [ ] **Step 4: Functional test — full interactive `setup` run in a sandbox**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
HOME="$SANDBOX" git config --global user.name "Test Work"
HOME="$SANDBOX" git config --global user.email "work@example.com"

printf '%s\n' \
  "U17Leetha" \
  "acme-work" \
  "$SANDBOX/Personal" \
  "$SANDBOX/Work" \
  "github-personal" \
  "github-work" \
  "y" \
  "" \
  "" \
  "y" \
  "y" \
  "work" \
  | HOME="$SANDBOX" "$REPO/git-smart" setup

echo "--- config file (global-profile fields) ---"
grep -E "GIT_SMART_GLOBAL_PROFILE|GIT_SMART_WORK_GIT_(NAME|EMAIL)" "$SANDBOX/.config/git-smart.conf"
echo "--- bare github.com stanza ---"
grep -A4 "^Host github.com$" "$SANDBOX/.ssh/config"

rm -rf "$SANDBOX"
```
The 12 piped lines answer, in order: personal owner, work owner, personal dir, work dir, personal SSH host alias, work SSH host alias, "yes" to configuring SSH hosts, blank (accept default personal key path), blank (accept default work key path), "yes" (generate the personal key — it doesn't exist in the sandbox), "yes" (generate the work key), and finally `work` for the new global-profile prompt.

Expected:
- `GIT_SMART_GLOBAL_PROFILE="work"`, `GIT_SMART_WORK_GIT_NAME="Test Work"`, `GIT_SMART_WORK_GIT_EMAIL="work@example.com"` all present (the git-identity fields come from the pre-seeded global git config picked up as defaults in Task 2's `load_config` change).
- The bare `Host github.com` block's `IdentityFile` is `$SANDBOX/.ssh/id_ed25519_work` (the work key path accepted during setup).

- [ ] **Step 5: Functional test — blank answer skips cleanly**

Repeat Step 4's command but change the final piped line from `"work"` to `""` (blank). Expected: `setup` completes without calling `apply_global_profile`; `grep GIT_SMART_GLOBAL_PROFILE` on the resulting config file shows `GIT_SMART_GLOBAL_PROFILE=""`, and there is no `Host github.com` block added to `$SANDBOX/.ssh/config` (only `github-personal` and `github-work`).

- [ ] **Step 6: Commit**

```bash
cd /Users/matt/Development/Personal/git-smart
git add git-smart
git commit -m "feat: prompt for global default profile during git-smart setup"
```

---

### Task 6: Dedup `run_init`/`run_clone` to use `write_repo_context`

**Files:**
- Modify: `git-smart:1105-1112` (`run_init`)
- Modify: `git-smart:1160-1166` (`run_clone`)

- [ ] **Step 1: Simplify `run_init`**

Find:
```bash
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$base_dir" "$target_dir"
    git -C "$target_dir" init -b main
    git -C "$target_dir" remote add "$REMOTE" "$remote_url"
    git -C "$target_dir" config --local git-smart.profile "$PROFILE"
    git -C "$target_dir" config --local git-smart.owner "$owner"
    git -C "$target_dir" config --local git-smart.sshHost "$(profile_host "$PROFILE")"
  fi
```
Replace with:
```bash
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$base_dir" "$target_dir"
    git -C "$target_dir" init -b main
    git -C "$target_dir" remote add "$REMOTE" "$remote_url"
    (cd "$target_dir" && write_repo_context "$PROFILE" "$owner" "$(profile_host "$PROFILE")")
  fi
```

- [ ] **Step 2: Simplify `run_clone`**

Find:
```bash
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$(dirname "$target_dir")"
    git clone "$clone_url" "$target_dir"
    git -C "$target_dir" config --local git-smart.profile "$resolved_profile"
    git -C "$target_dir" config --local git-smart.owner "$owner"
    git -C "$target_dir" config --local git-smart.sshHost "$(profile_host "$resolved_profile")"
  fi
```
Replace with:
```bash
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$(dirname "$target_dir")"
    git clone "$clone_url" "$target_dir"
    (cd "$target_dir" && write_repo_context "$resolved_profile" "$owner" "$(profile_host "$resolved_profile")")
  fi
```

- [ ] **Step 3: Syntax check**

Run: `bash -n /Users/matt/Development/Personal/git-smart/git-smart`
Expected: no output, exit code 0.

- [ ] **Step 4: Functional test — `init` still writes correct repo-local context**

```bash
SANDBOX="$(mktemp -d)"
REPO="/Users/matt/Development/Personal/git-smart"
mkdir -p "$SANDBOX/.config"
cat > "$SANDBOX/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX/Personal"
GIT_SMART_WORK_DIR="$SANDBOX/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=(acme)
GITHUB_WORK_OWNERS=(acme-work)
GITHUB_PERSONAL_DEFAULT_OWNER="acme"
GITHUB_WORK_DEFAULT_OWNER="acme-work"
EOF

HOME="$SANDBOX" PATH="/usr/bin:/bin" "$REPO/git-smart" init --profile personal my-test-repo

echo "--- repo-local git-smart config ---"
git -C "$SANDBOX/Personal/my-test-repo" config --local --get git-smart.profile
git -C "$SANDBOX/Personal/my-test-repo" config --local --get git-smart.owner
git -C "$SANDBOX/Personal/my-test-repo" config --local --get git-smart.sshHost

rm -rf "$SANDBOX"
```
Note: `PATH="/usr/bin:/bin"` deliberately hides `gh` so `init` doesn't prompt to create a real GitHub repo — this keeps the test fully offline and non-interactive (only the `Repository name` prompt would fire if `INIT_NAME` weren't passed positionally, which it is here: `my-test-repo`).

Expected:
```
personal
acme
github-personal
```
(Identical to what the old inline `git config --local` calls produced — this proves the dedup is behavior-preserving.)

- [ ] **Step 5: Commit**

```bash
cd /Users/matt/Development/Personal/git-smart
git add git-smart
git commit -m "refactor: reuse write_repo_context in run_init/run_clone instead of duplicating git config calls"
```

---

### Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add to "What it does"**

Find:
```markdown
- personal/work repo directory management
- SSH host alias management
- optional GitHub SSH key generation
- repo-local context storage
```
Replace with:
```markdown
- personal/work repo directory management
- SSH host alias management
- optional GitHub SSH key generation
- machine-wide default profile (SSH host + git identity) for tools outside git-smart
- repo-local context storage
```

- [ ] **Step 2: Add to "Main commands"**

Find:
```markdown
git-smart switch --profile work
git-smart doctor
```
Replace with:
```markdown
git-smart switch --profile work
git-smart global --profile work
git-smart doctor
```

- [ ] **Step 3: Add to the `setup` capabilities list**

Find:
```markdown
- generate missing personal and work SSH keys
- print the public keys you need to add to GitHub
```
Replace with:
```markdown
- generate missing personal and work SSH keys
- optionally set one profile as the machine-wide default (SSH + git identity)
- print the public keys you need to add to GitHub
```

- [ ] **Step 4: Add a new "Global default profile" section**

Find:
```markdown
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

## Dependencies
```
Replace with:
```markdown
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

## Global default profile

Repos managed by `git-smart` (via `init`/`clone`/`switch`/`push`) always resolve
their own SSH key and remote correctly, regardless of any global default.

Anything *outside* git-smart's control — a plain `git@github.com:...` clone,
`gh`, or any tool that doesn't go through this CLI — falls back to whatever the
bare `Host github.com` entry in `~/.ssh/config` and your global
`~/.gitconfig` say. `git-smart global` lets you pin that fallback to one
profile explicitly:

```bash
git-smart global --profile work
```

This updates the bare `github.com` SSH host to that profile's key, sets
`git config --global user.name`/`user.email` from
`GIT_SMART_WORK_GIT_NAME`/`GIT_SMART_WORK_GIT_EMAIL`, and remembers your
choice in `GIT_SMART_GLOBAL_PROFILE`. `git-smart doctor` reports drift if the
bare host or global git identity later stop matching. `git-smart setup` also
offers to configure this during onboarding.

## Dependencies
```

- [ ] **Step 5: Add the new fields to the config file example**

Find:
```markdown
GITHUB_PERSONAL_DEFAULT_OWNER="U17Leetha"
GITHUB_WORK_DEFAULT_OWNER="Strong-Crypto-Innovations"
```
```
Replace with:
```markdown
GITHUB_PERSONAL_DEFAULT_OWNER="U17Leetha"
GITHUB_WORK_DEFAULT_OWNER="Strong-Crypto-Innovations"

GIT_SMART_GLOBAL_PROFILE="work"
GIT_SMART_WORK_GIT_NAME="Matt Prater"
GIT_SMART_WORK_GIT_EMAIL="matt.prater@strongcrypto.com"
```
```

- [ ] **Step 6: Review the rendered file**

Run: `cat /Users/matt/Development/Personal/git-smart/README.md`
Expected: reads cleanly top to bottom, no broken code fences (check the fence count is even), new section appears between "Repo context" and "Dependencies".

- [ ] **Step 7: Commit**

```bash
cd /Users/matt/Development/Personal/git-smart
git add README.md
git commit -m "docs: document git-smart global and its config fields"
```

---

### Task 8: Apply on this machine and clean up `~/.ssh/config`

This task touches your **real** `~/.ssh/config` and global `~/.gitconfig` — not a sandbox. Each step shows you the diff before/after so you can confirm as you go.

**Files:**
- Modify (real, on this machine): `~/.ssh/config`
- Modify (real, on this machine): `~/.config/git-smart.conf` (via `git-smart global`)
- Modify (real, on this machine): `~/.gitconfig` (via `git-smart global`, values unchanged — already work identity)

- [ ] **Step 1: Back up the current SSH config**

```bash
cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S)
ls -la ~/.ssh/config.bak.*
```
Expected: a timestamped backup file now exists.

- [ ] **Step 2: Repoint `github-work` at the new key**

Edit `~/.ssh/config` by hand: in the `Host github-work` block, change
```
  IdentityFile ~/.ssh/id_ed25519_strongcrypto
```
to
```
  IdentityFile ~/.ssh/id_ed25519_github_axe
```

- [ ] **Step 3: Remove the redundant `github-strongcrypto` and `github-axe` stanzas**

Delete these two blocks entirely from `~/.ssh/config`:
```
Host github-strongcrypto
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_strongcrypto
  AddKeysToAgent yes
  UseKeychain yes
```
and
```
# AXE GitHub
Host github-axe
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github_axe
    AddKeysToAgent yes
    UseKeychain yes
```

- [ ] **Step 4: Verify the SSH config looks right**

Run: `cat ~/.ssh/config`
Expected: only `Host github.com` (still pointing at the old default key for now — Step 6 updates it), `Host github-work` (now pointing at `id_ed25519_github_axe`), and `Host github-personal` remain. No `github-strongcrypto` or `github-axe` blocks.

- [ ] **Step 5: Confirm `git-smart` resolves the new work key correctly**

Run: `ssh -G github-work | grep -i identityfile`
Expected: `identityfile ~/.ssh/id_ed25519_github_axe`

- [ ] **Step 6: Apply the global default**

Run: `/Users/matt/Development/Personal/git-smart/git-smart global --profile work`
Expected output includes lines like:
```
[*] Applying 'work' as the global default profile
[*] SSH default (Host github.com) -> ~/.ssh/id_ed25519_github_axe
[*] Global git user.name -> Matt Prater
[*] Global git user.email -> matt.prater@strongcrypto.com
[*] Global default profile is now 'work'.
```

- [ ] **Step 7: Verify the bare `github.com` host now uses the axe key**

Run: `ssh -G github.com | grep -i identityfile`
Expected: `identityfile ~/.ssh/id_ed25519_github_axe`

- [ ] **Step 8: Verify global git identity**

```bash
git config --global --get user.name
git config --global --get user.email
```
Expected: `Matt Prater` and `matt.prater@strongcrypto.com` (unchanged from before — this just confirms git-smart didn't disturb anything).

- [ ] **Step 9: Verify `git-smart doctor` reports no drift**

Run: `/Users/matt/Development/Personal/git-smart/git-smart doctor`
Expected: `Global default profile: work`, matching bare-host identity and git identity lines, and the suggestions list does not include any "does not match" entries for the global profile.

- [ ] **Step 10: Live SSH auth check**

Run: `ssh -T github.com`
Expected: a GitHub authentication success message (e.g. `Hi <username>! You've successfully authenticated...`) using the `github_axe` key.

- [ ] **Step 11: Clean up the backup once confirmed**

Only after Steps 7–10 all look correct: leave `~/.ssh/config.bak.*` in place for now (no action needed) — it's a small text file and costs nothing to keep as a rollback point. No commit for this task (it doesn't touch the git-smart repo).
