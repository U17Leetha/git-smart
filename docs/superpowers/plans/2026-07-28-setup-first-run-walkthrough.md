# Setup First-Run Walkthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a genuine first-time run of `git-smart setup` explain each concept (owner, directories, SSH keys, the global default) in plain English before asking for it, while a re-run (config file already exists) behaves exactly as it does today.

**Architecture:** One new local flag in `run_setup()`, `is_first_run`, set by checking whether `$CONFIG_FILE` exists before any prompts run. Seven `printf` blocks, each gated on that flag, inserted immediately before the existing prompt(s) they explain. No control-flow changes, no new prompts, no new config fields.

**Tech Stack:** Bash, matching the rest of `git-smart`'s conventions. No automated test suite in this repo — verification via sandboxed `HOME` runs (first-run vs. re-run, comparing output for the presence/absence of explanatory text).

---

### Task 1: Add the first-run walkthrough to `git-smart setup`

**Files:**
- Modify: `git-smart` (`run_setup`)

- [ ] **Step 1: Add first-run detection and the opening/owner/directory/SSH-alias explanatory blocks**

Find:
```bash
run_setup() {
  local personal_owner work_owner personal_dir work_dir personal_host work_host
  local personal_key work_key personal_current work_current
  local global_profile

  info "Interactive git-smart setup"
  printf '\n'

  personal_owner="$(prompt "Personal GitHub owner" "${GITHUB_PERSONAL_DEFAULT_OWNER:-U17Leetha}")"
  work_owner="$(prompt "Work GitHub owner" "${GITHUB_WORK_DEFAULT_OWNER:-}")"
  personal_dir="$(prompt "Personal repos directory" "$GIT_SMART_PERSONAL_DIR")"
  work_dir="$(prompt "Work repos directory" "$GIT_SMART_WORK_DIR")"
  personal_host="$(prompt "Personal SSH host alias" "$GITHUB_PERSONAL_HOST")"
  work_host="$(prompt "Work SSH host alias" "$GITHUB_WORK_HOST")"
```
Replace with:
```bash
run_setup() {
  local personal_owner work_owner personal_dir work_dir personal_host work_host
  local personal_key work_key personal_current work_current
  local global_profile
  local is_first_run=0

  [[ -f "$CONFIG_FILE" ]] || is_first_run=1

  info "Interactive git-smart setup"
  printf '\n'

  if [[ "$is_first_run" -eq 1 ]]; then
    printf 'git-smart helps you use two separate GitHub identities on this machine --\n'
    printf 'one for personal projects, one for work -- without having to remember which\n'
    printf 'SSH key or git config to use each time. This asks a handful of questions;\n'
    printf 'the default shown in [brackets] is almost always fine -- just press Enter.\n'
    printf '\n'
  fi

  if [[ "$is_first_run" -eq 1 ]]; then
    printf 'A GitHub "owner" is whoever a repo belongs to -- usually your own username,\n'
    printf 'but it can be an organization name (common for work repos).\n'
    printf '\n'
  fi
  personal_owner="$(prompt "Personal GitHub owner" "${GITHUB_PERSONAL_DEFAULT_OWNER:-U17Leetha}")"
  work_owner="$(prompt "Work GitHub owner" "${GITHUB_WORK_DEFAULT_OWNER:-}")"

  if [[ "$is_first_run" -eq 1 ]]; then
    printf '\nThese are the folders on your computer where git-smart will put new\n'
    printf 'personal and work repos, and where it looks to guess which profile a\n'
    printf 'repo belongs to.\n'
    printf '\n'
  fi
  personal_dir="$(prompt "Personal repos directory" "$GIT_SMART_PERSONAL_DIR")"
  work_dir="$(prompt "Work repos directory" "$GIT_SMART_WORK_DIR")"

  if [[ "$is_first_run" -eq 1 ]]; then
    printf '\nThese next two are internal nicknames git-smart uses in your SSH config\n'
    printf 'to tell your personal and work keys apart -- the defaults are fine, just\n'
    printf 'press Enter.\n'
    printf '\n'
  fi
  personal_host="$(prompt "Personal SSH host alias" "$GITHUB_PERSONAL_HOST")"
  work_host="$(prompt "Work SSH host alias" "$GITHUB_WORK_HOST")"
```

- [ ] **Step 2: Add the SSH-key explanatory block**

Find:
```bash
  save_config
  info "Wrote config to $CONFIG_FILE"

  if prompt_yes_no "Add or update SSH host entries in $SSH_CONFIG_FILE?" "y"; then
```
Replace with:
```bash
  save_config
  info "Wrote config to $CONFIG_FILE"

  if [[ "$is_first_run" -eq 1 ]]; then
    printf '\nGitHub uses an SSH key to know it is really you connecting, instead of\n'
    printf 'typing a password every time. If you do not already have separate keys\n'
    printf 'for personal and work, git-smart can generate them now.\n'
    printf '\n'
  fi
  if prompt_yes_no "Add or update SSH host entries in $SSH_CONFIG_FILE?" "y"; then
```

- [ ] **Step 3: Add the "how to add this key to GitHub" instructions after each key is printed**

Find:
```bash
    if [[ "$DRY_RUN" -eq 0 ]]; then
      show_public_key_details "personal" "$personal_key"
      show_public_key_details "work" "$work_key"
    fi
  fi

  global_profile="$(prompt "Global default profile for tools outside git-smart (personal/work/none)" "$GIT_SMART_GLOBAL_PROFILE")"
```
Replace with:
```bash
    if [[ "$DRY_RUN" -eq 0 ]]; then
      show_public_key_details "personal" "$personal_key"
      if [[ "$is_first_run" -eq 1 ]]; then
        printf '\n  To add this key to GitHub:\n'
        printf '    1. Copy the public key printed above\n'
        printf '    2. Go to https://github.com/settings/ssh/new\n'
        printf '    3. Give it a memorable title, e.g. "personal key"\n'
        printf '    4. Paste the key into the "Key" field and click "Add SSH key"\n'
      fi
      show_public_key_details "work" "$work_key"
      if [[ "$is_first_run" -eq 1 ]]; then
        printf '\n  To add this key to GitHub:\n'
        printf '    1. Copy the public key printed above\n'
        printf '    2. Go to https://github.com/settings/ssh/new\n'
        printf '    3. Give it a memorable title, e.g. "work key"\n'
        printf '    4. Paste the key into the "Key" field and click "Add SSH key"\n'
      fi
    fi
  fi

  if [[ "$is_first_run" -eq 1 ]]; then
    printf '\nOne more thing: your computer has a single "default" GitHub identity for\n'
    printf 'tools that do not go through git-smart (like a plain "git clone" or the\n'
    printf 'gh tool from GitHub). Setting one here makes that default match one of\n'
    printf 'your profiles instead of being left unset.\n'
    printf '\n'
  fi
  global_profile="$(prompt "Global default profile for tools outside git-smart (personal/work/none)" "$GIT_SMART_GLOBAL_PROFILE")"
```

- [ ] **Step 4: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 5: Functional test — first run shows all 7 explanatory blocks**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
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
  | HOME="$SANDBOX" "$REPO/git-smart" setup > "$SANDBOX/output.txt" 2>&1

echo "--- checking for all 7 explanatory phrases ---"
grep -c "helps you use two separate GitHub identities" "$SANDBOX/output.txt"
grep -c "A GitHub \"owner\" is whoever" "$SANDBOX/output.txt"
grep -c "where git-smart will put new" "$SANDBOX/output.txt"
grep -c "internal nicknames git-smart uses" "$SANDBOX/output.txt"
grep -c "GitHub uses an SSH key to know" "$SANDBOX/output.txt"
grep -c "https://github.com/settings/ssh/new" "$SANDBOX/output.txt"
grep -c "single \"default\" GitHub identity" "$SANDBOX/output.txt"

echo "--- confirming functional outcome still correct ---"
grep -E "GIT_SMART_GLOBAL_PROFILE|GIT_SMART_WORK_GIT_(NAME|EMAIL)" "$SANDBOX/.config/git-smart.conf"

rm -rf "$SANDBOX" 2>/dev/null || true
```
The 12 piped lines answer, in order: personal owner, work owner, personal dir, work dir, personal SSH host alias, work SSH host alias, "yes" to configuring SSH hosts, blank (accept default personal key path), blank (accept default work key path), "yes" (generate the personal key), "yes" (generate the work key), and `work` for the global-profile prompt — this is the exact same answer sequence `setup` has always accepted; the new explanatory text doesn't add or remove any prompts.

Expected: every `grep -c` returns `2` for the two "To add this key to GitHub" blocks (personal + work) worth of `https://github.com/settings/ssh/new` occurrences, and `1` for every other phrase (each appears exactly once). `GIT_SMART_GLOBAL_PROFILE="work"` and the git-identity fields are present and correct in the config file, confirming the explanatory output didn't disturb the underlying logic.

- [ ] **Step 6: Functional test — re-run shows zero explanatory text**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
HOME="$SANDBOX" git config --global user.name "Test Work"
HOME="$SANDBOX" git config --global user.email "work@example.com"

# First run to create the config file (silently discard output, we already tested this path above).
printf '%s\n' \
  "U17Leetha" "acme-work" "$SANDBOX/Personal" "$SANDBOX/Work" \
  "github-personal" "github-work" "y" "" "" "y" "y" "work" \
  | HOME="$SANDBOX" "$REPO/git-smart" setup > /dev/null 2>&1

echo "--- second run (config file now exists) ---"
printf '%s\n' \
  "U17Leetha" "acme-work" "$SANDBOX/Personal" "$SANDBOX/Work" \
  "github-personal" "github-work" "n" "work" \
  | HOME="$SANDBOX" "$REPO/git-smart" setup > "$SANDBOX/output2.txt" 2>&1

echo "--- checking NONE of the 7 explanatory phrases appear ---"
grep -c "helps you use two separate GitHub identities" "$SANDBOX/output2.txt" || true
grep -c "A GitHub \"owner\" is whoever" "$SANDBOX/output2.txt" || true
grep -c "where git-smart will put new" "$SANDBOX/output2.txt" || true
grep -c "internal nicknames git-smart uses" "$SANDBOX/output2.txt" || true
grep -c "GitHub uses an SSH key to know" "$SANDBOX/output2.txt" || true
grep -c "https://github.com/settings/ssh/new" "$SANDBOX/output2.txt" || true
grep -c "single \"default\" GitHub identity" "$SANDBOX/output2.txt" || true

rm -rf "$SANDBOX" 2>/dev/null || true
```
Note the second run answers `"n"` to the SSH-host-config prompt (keys already exist from the first run, no need to regenerate) followed directly by `"work"` for the global-profile prompt — 8 lines total instead of 12, since skipping the `y` branch skips its 4 sub-prompts.

Expected: every `grep -c` returns `0` (or the command exits 1 with no output, which `|| true` tolerates) — no explanatory text anywhere in the second run's output, confirming re-run behavior is unchanged from before this feature.

- [ ] **Step 7: Functional test — `--dry-run` still shows explanations on a first run**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"

printf '%s\n' \
  "U17Leetha" "acme-work" "$SANDBOX/Personal" "$SANDBOX/Work" \
  "github-personal" "github-work" "n" "none" \
  | HOME="$SANDBOX" "$REPO/git-smart" setup --dry-run > "$SANDBOX/output3.txt" 2>&1

grep -c "helps you use two separate GitHub identities" "$SANDBOX/output3.txt"

rm -rf "$SANDBOX" 2>/dev/null || true
```
Expected: `1` — explanatory text is not gated on `DRY_RUN`, only on `is_first_run`, so it still appears.

- [ ] **Step 8: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "feat: add first-run walkthrough explanations to git-smart setup"
```
