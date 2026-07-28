# Bash Version Gate and Include-Based SSH Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refuse to run on bash < 4 with a clear error; make `UseKeychain` macOS-only; and move git-smart's SSH host blocks into a dedicated `Include`d file so they always take priority over anything else in the user's `~/.ssh/config`, closing a verified wrong-identity shadowing bug.

**Architecture:** A 5-line version check at the top of the script. A new dedicated file (`~/.ssh/config.d/git-smart`) that git-smart fully owns, referenced from `~/.ssh/config` via a single `Include` line placed first. `append_ssh_host_if_missing`/`update_ssh_host_identity`/the awk editor are replaced by one `write_git_smart_ssh_host()` that regenerates the whole dedicated file from git-smart's own known state every time. `current_identity_for_host_config` is repointed at the new file. `run_setup`/`apply_global_profile` are simplified accordingly, and `doctor` gains an effective-vs-intended identity check plus an Include-line-present check.

**Tech Stack:** Bash, matching existing conventions. No automated test suite in this repo — verification via sandboxed `HOME` runs, plus a fake `uname` shim (same technique as the fake-`gh` shim used for the `fork`/`pr` feature) to deterministically test the Darwin/Linux branch of `UseKeychain` without needing two physical machines. This machine's `/bin/bash` is itself the stock Apple 3.2 build, so the version-gate test runs against a real old bash, not a simulation.

---

### Task 1: Add the bash version gate

**Files:**
- Modify: `git-smart` (top of file)

- [ ] **Step 1: Add the version check**

Find:
```bash
#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="git-smart"
```
Replace with:
```bash
#!/usr/bin/env bash
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  printf '[!] git-smart requires bash >= 4 (found %s). On macOS: brew install bash\n' "$BASH_VERSION" >&2
  exit 1
fi

PROGRAM_NAME="git-smart"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 3: Functional test — modern bash still runs normally**

```bash
REPO="<your working directory>"
"$REPO/git-smart" help | head -3
```
Expected: normal usage output (`Usage:` / `  git-smart <command> [options]`), no version-gate message.

- [ ] **Step 4: Functional test — real bash 3.2 is refused with a clear message**

This machine's `/bin/bash` is itself the stock Apple build, which is bash 3.2 unless something has overridden it — confirm first, then use it directly:

```bash
/bin/bash --version | head -1
```
If that prints `version 3.2...`, continue:
```bash
REPO="<your working directory>"
/bin/bash "$REPO/git-smart" help
echo "exit code: $?"
```
Expected: `[!] git-smart requires bash >= 4 (found 3.2.57(1)-release). On macOS: brew install bash` (version string will match whatever `/bin/bash --version` reported), exit code `1`, and critically — no `bad substitution` or other raw bash error, confirming the gate fires before any bash-4-only syntax executes.

If `/bin/bash --version` on this machine is NOT 3.2 (i.e., something has already replaced the system bash), skip this exact step and instead note in your report that the real-3.2 test could not be run on this machine, and rely on Steps 2-3 (syntax check + normal-bash run) for verification.

- [ ] **Step 5: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "fix: refuse to run on bash < 4 instead of failing with a confusing mid-script error"
```

---

### Task 2: Replace SSH config editing with an Include-based dedicated file

**Files:**
- Modify: `git-smart` (new constants, near the top)
- Modify: `git-smart` (replace `append_ssh_host_if_missing`, `current_identity_for_host_config`, `update_ssh_host_identity`)
- Modify: `git-smart` (`run_setup`'s local declarations and SSH-writing block)
- Modify: `git-smart` (`apply_global_profile`'s local declarations and bare-host-writing block)
- Modify: `git-smart` (`run_doctor`'s local declarations and identity-reporting block)

- [ ] **Step 1: Add the new constants**

Find:
```bash
CONFIG_FILE="${HOME}/.config/git-smart.conf"
SSH_CONFIG_FILE="${HOME}/.ssh/config"
```
Replace with:
```bash
CONFIG_FILE="${HOME}/.config/git-smart.conf"
SSH_CONFIG_FILE="${HOME}/.ssh/config"
GIT_SMART_SSH_INCLUDE_DIR="${HOME}/.ssh/config.d"
GIT_SMART_SSH_INCLUDE_FILE="${GIT_SMART_SSH_INCLUDE_DIR}/git-smart"
```

- [ ] **Step 2: Replace `append_ssh_host_if_missing`, `current_identity_for_host_config`, and `update_ssh_host_identity` with the new functions**

Find (this is the exact, complete span of all three existing functions — replace the whole block):
```bash
append_ssh_host_if_missing() {
  local host_alias="$1"
  local key_path="$2"

  mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
  touch "$SSH_CONFIG_FILE"

  if grep -Eq "^Host[[:space:]]+${host_alias}$" "$SSH_CONFIG_FILE"; then
    info "SSH host '$host_alias' already exists in $SSH_CONFIG_FILE"
    return
  fi

  cat >> "$SSH_CONFIG_FILE" <<EOF

Host $host_alias
  HostName github.com
  User git
  IdentityFile $key_path
  AddKeysToAgent yes
  UseKeychain yes
  IdentitiesOnly yes
EOF
}

current_identity_for_host_config() {
  local host_alias="$1"
  local line

  if [[ ! -f "$SSH_CONFIG_FILE" ]]; then
    return 0
  fi

  line="$(awk -v host="$host_alias" '
    $1 == "Host" && $2 == host { in_block=1; next }
    $1 == "Host" && in_block { exit }
    in_block && $1 == "IdentityFile" { print $2; exit }
  ' "$SSH_CONFIG_FILE")"

  printf '%s\n' "$line"
}

update_ssh_host_identity() {
  local host_alias="$1"
  local key_path="$2"
  local tmp_file

  tmp_file="$(mktemp)"

  awk -v host="$host_alias" -v key="$key_path" '
    function flush_block() {
      if (!in_block) {
        return
      }

      if (!replaced) {
        if (last_line_empty == 0) {
          print "  IdentityFile " key
        } else {
          print "  IdentityFile " key
        }
      }

      in_block = 0
      replaced = 0
      last_line_empty = 0
    }

    $1 == "Host" {
      if (in_block) {
        flush_block()
      }
      if ($2 == host) {
        in_block = 1
        replaced = 0
      }
      print
      next
    }

    in_block && $1 == "IdentityFile" {
      print "  IdentityFile " key
      replaced = 1
      next
    }

    {
      print
      if (in_block) {
        last_line_empty = ($0 == "")
      }
    }

    END {
      if (in_block) {
        flush_block()
      }
    }
  ' "$SSH_CONFIG_FILE" > "$tmp_file"

  mv "$tmp_file" "$SSH_CONFIG_FILE"
}
```
Replace with:
```bash
current_identity_for_host_config() {
  local host_alias="$1"
  local line

  if [[ ! -f "$GIT_SMART_SSH_INCLUDE_FILE" ]]; then
    return 0
  fi

  line="$(awk -v host="$host_alias" '
    $1 == "Host" && $2 == host { in_block=1; next }
    $1 == "Host" && in_block { exit }
    in_block && $1 == "IdentityFile" { print $2; exit }
  ' "$GIT_SMART_SSH_INCLUDE_FILE")"

  printf '%s\n' "$line"
}

# Ensures ~/.ssh/config starts with an Include pointing at git-smart's own
# dedicated file. Placing it first means git-smart's blocks are always tried
# before anything else the user has configured -- ssh_config is first-match-
# wins, so this is what makes git-smart's identity choices authoritative
# instead of silently losing to an earlier Host * block.
ensure_ssh_include() {
  local include_line="Include ~/.ssh/config.d/git-smart"
  local tmp_file

  mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
  touch "$SSH_CONFIG_FILE"

  if grep -qF "$include_line" "$SSH_CONFIG_FILE"; then
    return 0
  fi

  tmp_file="$(mktemp "${SSH_CONFIG_FILE}.XXXXXX")"
  {
    printf '%s\n\n' "$include_line"
    cat "$SSH_CONFIG_FILE"
  } > "$tmp_file"
  mv "$tmp_file" "$SSH_CONFIG_FILE"
}

ssh_host_block() {
  local host_alias="$1"
  local key_path="$2"

  printf 'Host %s\n' "$host_alias"
  printf '  HostName github.com\n'
  printf '  User git\n'
  printf '  IdentityFile %s\n' "$key_path"
  printf '  AddKeysToAgent yes\n'
  printf '  IdentitiesOnly yes\n'
  if [[ "$(uname -s)" == "Darwin" ]]; then
    printf '  UseKeychain yes\n'
  fi
  printf '\n'
}

# Regenerates the entire dedicated file from git-smart's own known state
# (all three possible aliases), rather than surgically editing arbitrary
# text -- since git-smart fully owns this file, "update" is just "rewrite
# it correctly," which removes an entire class of parsing bugs.
write_git_smart_ssh_host() {
  local target_host="$1"
  local target_key="$2"
  local personal_key work_key default_key tmp_file

  personal_key="$(current_identity_for_host_config "$GITHUB_PERSONAL_HOST")"
  work_key="$(current_identity_for_host_config "$GITHUB_WORK_HOST")"
  default_key="$(current_identity_for_host_config "$GITHUB_DEFAULT_HOST")"

  case "$target_host" in
    "$GITHUB_PERSONAL_HOST") personal_key="$target_key" ;;
    "$GITHUB_WORK_HOST") work_key="$target_key" ;;
    "$GITHUB_DEFAULT_HOST") default_key="$target_key" ;;
  esac

  ensure_ssh_include

  mkdir -p "$GIT_SMART_SSH_INCLUDE_DIR"
  chmod 700 "$GIT_SMART_SSH_INCLUDE_DIR"
  touch "$GIT_SMART_SSH_INCLUDE_FILE"

  tmp_file="$(mktemp "${GIT_SMART_SSH_INCLUDE_FILE}.XXXXXX")"
  {
    if [[ -n "$personal_key" ]]; then
      ssh_host_block "$GITHUB_PERSONAL_HOST" "$personal_key"
    fi
    if [[ -n "$work_key" ]]; then
      ssh_host_block "$GITHUB_WORK_HOST" "$work_key"
    fi
    if [[ -n "$default_key" ]]; then
      ssh_host_block "$GITHUB_DEFAULT_HOST" "$default_key"
    fi
  } > "$tmp_file"
  chmod 600 "$tmp_file"
  mv "$tmp_file" "$GIT_SMART_SSH_INCLUDE_FILE"
}
```

**Important implementation note:** the `if [[ -n "$x" ]]; then ssh_host_block ...; fi` form is deliberate and must NOT be simplified to `[[ -n "$x" ]] && ssh_host_block ...`. Under this file's `set -euo pipefail`, a bare `cond && cmd` statement (not itself guarded by an enclosing `if`) that evaluates false aborts the entire script immediately — this exact class of bug was found and fixed twice earlier in this project's history (`apply_global_profile`'s dry-run path, and the same pattern in `ensure_ssh_include`'s `grep ... && return 0` if written that way instead of the `if` form shown above). Keep both as explicit `if` statements.

- [ ] **Step 3: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 4: Simplify `run_setup`'s local declarations**

Find:
```bash
  local personal_owner work_owner personal_dir work_dir personal_host work_host
  local personal_key work_key personal_current work_current
  local global_profile
```
Replace with:
```bash
  local personal_owner work_owner personal_dir work_dir personal_host work_host
  local personal_key work_key
  local global_profile
```

- [ ] **Step 5: Simplify `run_setup`'s SSH-writing block**

Find:
```bash
    personal_current="$(current_identity_for_host_config "$GITHUB_PERSONAL_HOST")"
    if [[ -n "$personal_current" && "$(expand_path "$personal_current")" != "$(expand_path "$personal_key")" ]]; then
      info "SSH host '$GITHUB_PERSONAL_HOST' currently uses $personal_current"
      if prompt_yes_no "Update '$GITHUB_PERSONAL_HOST' to use $personal_key?" "y"; then
        if [[ "$DRY_RUN" -eq 0 ]]; then
          update_ssh_host_identity "$GITHUB_PERSONAL_HOST" "$personal_key"
        else
          printf '[*] Dry run: update Host %s IdentityFile to %s\n' "$GITHUB_PERSONAL_HOST" "$personal_key"
        fi
      fi
    else
      if [[ "$DRY_RUN" -eq 0 ]]; then
        append_ssh_host_if_missing "$GITHUB_PERSONAL_HOST" "$personal_key"
      else
        printf '[*] Dry run: add Host %s with IdentityFile %s\n' "$GITHUB_PERSONAL_HOST" "$personal_key"
      fi
    fi

    work_current="$(current_identity_for_host_config "$GITHUB_WORK_HOST")"
    if [[ -n "$work_current" && "$(expand_path "$work_current")" != "$(expand_path "$work_key")" ]]; then
      info "SSH host '$GITHUB_WORK_HOST' currently uses $work_current"
      if prompt_yes_no "Update '$GITHUB_WORK_HOST' to use $work_key?" "y"; then
        if [[ "$DRY_RUN" -eq 0 ]]; then
          update_ssh_host_identity "$GITHUB_WORK_HOST" "$work_key"
        else
          printf '[*] Dry run: update Host %s IdentityFile to %s\n' "$GITHUB_WORK_HOST" "$work_key"
        fi
      fi
    else
      if [[ "$DRY_RUN" -eq 0 ]]; then
        append_ssh_host_if_missing "$GITHUB_WORK_HOST" "$work_key"
      else
        printf '[*] Dry run: add Host %s with IdentityFile %s\n' "$GITHUB_WORK_HOST" "$work_key"
      fi
    fi
```
Replace with:
```bash
    if [[ "$DRY_RUN" -eq 0 ]]; then
      write_git_smart_ssh_host "$GITHUB_PERSONAL_HOST" "$personal_key"
      info "SSH host '$GITHUB_PERSONAL_HOST' -> $personal_key"
    else
      printf '[*] Dry run: set Host %s IdentityFile to %s\n' "$GITHUB_PERSONAL_HOST" "$personal_key"
    fi

    if [[ "$DRY_RUN" -eq 0 ]]; then
      write_git_smart_ssh_host "$GITHUB_WORK_HOST" "$work_key"
      info "SSH host '$GITHUB_WORK_HOST' -> $work_key"
    else
      printf '[*] Dry run: set Host %s IdentityFile to %s\n' "$GITHUB_WORK_HOST" "$work_key"
    fi
```

- [ ] **Step 6: Simplify `apply_global_profile`'s local declarations**

Find:
```bash
  local host_alias key_path current_default host_exists git_name git_email
```
Replace with:
```bash
  local host_alias key_path git_name git_email
```

- [ ] **Step 7: Simplify `apply_global_profile`'s bare-host-writing block**

Find:
```bash
  info "Applying '$profile' as the global default profile"

  host_exists=0
  if [[ -f "$SSH_CONFIG_FILE" ]] && grep -Eq "^Host[[:space:]]+${GITHUB_DEFAULT_HOST}$" "$SSH_CONFIG_FILE"; then
    host_exists=1
  fi
  current_default="$(current_identity_for_host_config "$GITHUB_DEFAULT_HOST")"

  if [[ "$host_exists" -eq 0 ]]; then
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
```
Replace with:
```bash
  info "Applying '$profile' as the global default profile"

  if [[ "$DRY_RUN" -eq 0 ]]; then
    write_git_smart_ssh_host "$GITHUB_DEFAULT_HOST" "$key_path"
  else
    printf '[*] Dry run: set Host %s IdentityFile to %s\n' "$GITHUB_DEFAULT_HOST" "$key_path"
  fi
  info "SSH default (Host $GITHUB_DEFAULT_HOST) -> $key_path"
```

- [ ] **Step 8: Add local variables for `run_doctor`'s new checks**

Find:
```bash
  local current_url="" identity_personal="" identity_work="" repo_profile="" repo_owner="" repo_host=""
  local expected_default_key="" actual_default_key="" expected_git_name="" expected_git_email=""
  local actual_git_name="" actual_git_email=""
  local suggestions=()
```
Replace with:
```bash
  local current_url="" identity_personal="" identity_work="" repo_profile="" repo_owner="" repo_host=""
  local expected_default_key="" actual_default_key="" expected_git_name="" expected_git_email=""
  local actual_git_name="" actual_git_email=""
  local intended_personal="" intended_work=""
  local suggestions=()
```

- [ ] **Step 9: Add `doctor`'s effective-vs-intended check and Include-line check**

Find:
```bash
  identity_personal="$(identity_for_host "$GITHUB_PERSONAL_HOST")"
  identity_work="$(identity_for_host "$GITHUB_WORK_HOST")"

  if [[ -n "$identity_personal" ]]; then
    info "Personal identity: $identity_personal"
  else
    suggestions+=("Add SSH config for '$GITHUB_PERSONAL_HOST' so personal repos use the correct key.")
  fi

  if [[ -n "$identity_work" ]]; then
    info "Work identity    : $identity_work"
  else
    suggestions+=("Add SSH config for '$GITHUB_WORK_HOST' so work repos use the correct key.")
  fi
  printf '\n'
```
Replace with:
```bash
  identity_personal="$(identity_for_host "$GITHUB_PERSONAL_HOST")"
  identity_work="$(identity_for_host "$GITHUB_WORK_HOST")"
  intended_personal="$(current_identity_for_host_config "$GITHUB_PERSONAL_HOST")"
  intended_work="$(current_identity_for_host_config "$GITHUB_WORK_HOST")"

  if [[ -n "$identity_personal" ]]; then
    info "Personal identity: $identity_personal"
    if [[ -n "$intended_personal" && "$(expand_path "$identity_personal")" != "$(expand_path "$intended_personal")" ]]; then
      suggestions+=("SSH for '$GITHUB_PERSONAL_HOST' resolves to '$identity_personal', not the configured '$intended_personal' -- something earlier in $SSH_CONFIG_FILE may be shadowing it.")
    fi
  else
    suggestions+=("Add SSH config for '$GITHUB_PERSONAL_HOST' so personal repos use the correct key.")
  fi

  if [[ -n "$identity_work" ]]; then
    info "Work identity    : $identity_work"
    if [[ -n "$intended_work" && "$(expand_path "$identity_work")" != "$(expand_path "$intended_work")" ]]; then
      suggestions+=("SSH for '$GITHUB_WORK_HOST' resolves to '$identity_work', not the configured '$intended_work' -- something earlier in $SSH_CONFIG_FILE may be shadowing it.")
    fi
  else
    suggestions+=("Add SSH config for '$GITHUB_WORK_HOST' so work repos use the correct key.")
  fi

  if ! grep -qF "Include ~/.ssh/config.d/git-smart" "$SSH_CONFIG_FILE" 2>/dev/null; then
    suggestions+=("$SSH_CONFIG_FILE is missing 'Include ~/.ssh/config.d/git-smart'. Run 'git-smart setup' or 'git-smart global' again to fix it.")
  fi
  printf '\n'
```

- [ ] **Step 10: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 11: Build the shared sandbox fixture**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
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
mkdir -p "$SANDBOX/.ssh"
touch "$SANDBOX/.ssh/id_ed25519_personal" "$SANDBOX/.ssh/id_ed25519_work"
```

- [ ] **Step 12: Functional test — `setup` creates the Include line and dedicated file correctly**

```bash
HOME="$SANDBOX" git config --global user.name "Test Work"
HOME="$SANDBOX" git config --global user.email "work@example.com"
printf '%s\n' \
  "U17Leetha" "acme-work" "$SANDBOX/Personal" "$SANDBOX/Work" \
  "github-personal" "github-work" "y" \
  "$SANDBOX/.ssh/id_ed25519_personal" "$SANDBOX/.ssh/id_ed25519_work" \
  "none" \
  | HOME="$SANDBOX" "$REPO/git-smart" setup

echo "--- ~/.ssh/config (should start with the Include line) ---"
head -3 "$SANDBOX/.ssh/config"
echo "--- dedicated file (should have both blocks) ---"
cat "$SANDBOX/.ssh/config.d/git-smart"
```
Note: the piped key-path prompts use the pre-touched key files directly (not `~/.ssh/id_ed25519_github_personal` defaults) so `ensure_ssh_key` takes the "already exists" fast path and doesn't try to generate new keys.

Expected: `~/.ssh/config`'s first line is `Include ~/.ssh/config.d/git-smart`, followed by a blank line. `~/.ssh/config.d/git-smart` contains two `Host` blocks (`github-personal`, `github-work`) with correct `IdentityFile` paths, `AddKeysToAgent yes`, `IdentitiesOnly yes`, and (since this test runs on macOS) `UseKeychain yes`.

- [ ] **Step 13: Functional test — idempotency (running again doesn't duplicate the Include line)**

```bash
HOME="$SANDBOX" "$REPO/git-smart" global --profile work
grep -c "Include ~/.ssh/config.d/git-smart" "$SANDBOX/.ssh/config"
```
Expected: `1` (not 2) — confirms `ensure_ssh_include` correctly detects the line is already present and doesn't re-add it. Also confirm the bare `github.com` block was added to the dedicated file alongside the two existing ones:
```bash
grep -c "^Host " "$SANDBOX/.ssh/config.d/git-smart"
```
Expected: `3` (personal, work, and now the bare default).

- [ ] **Step 14: Functional test — the shadowing bug is actually fixed**

Fresh sandbox, this time pre-seeding a competing `Host *` block BEFORE running any git-smart command:

```bash
SANDBOX2="$(mktemp -d)"
mkdir -p "$SANDBOX2/.ssh" "$SANDBOX2/.config"
touch "$SANDBOX2/.ssh/wrong_key" "$SANDBOX2/.ssh/right_key"
cat > "$SANDBOX2/.ssh/config" <<EOF
Host *
  IdentityFile $SANDBOX2/.ssh/wrong_key
EOF
cat > "$SANDBOX2/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX2/Personal"
GIT_SMART_WORK_DIR="$SANDBOX2/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=(acme)
GITHUB_WORK_OWNERS=(acme-work)
GITHUB_PERSONAL_DEFAULT_OWNER="acme"
GITHUB_WORK_DEFAULT_OWNER="acme-work"
EOF

REPO="<your working directory>"
printf '%s\n' \
  "U17Leetha" "acme-work" "$SANDBOX2/Personal" "$SANDBOX2/Work" \
  "github-personal" "github-work" "y" \
  "$SANDBOX2/.ssh/right_key" "$SANDBOX2/.ssh/right_key" \
  "none" \
  | HOME="$SANDBOX2" "$REPO/git-smart" setup > /dev/null

echo "--- effective identity for github-personal (should be right_key, NOT wrong_key) ---"
ssh -F "$SANDBOX2/.ssh/config" -G github-personal | grep identityfile
```
Expected: `identityfile <path>/right_key` — NOT `wrong_key`. This is the direct, empirical proof the shadowing bug is fixed: even though `Host *` with the wrong key appears in the main config, git-smart's `Include`d block (processed first) wins.

- [ ] **Step 15: Functional test — `UseKeychain` is Darwin-only, verified via a fake `uname`**

```bash
SANDBOX3="$(mktemp -d)"
mkdir -p "$SANDBOX3/fakebin" "$SANDBOX3/.ssh" "$SANDBOX3/.config"
cat > "$SANDBOX3/fakebin/uname" <<'EOF'
#!/bin/sh
echo "Linux"
EOF
chmod +x "$SANDBOX3/fakebin/uname"
touch "$SANDBOX3/.ssh/pkey" "$SANDBOX3/.ssh/wkey"
cat > "$SANDBOX3/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX3/Personal"
GIT_SMART_WORK_DIR="$SANDBOX3/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=(acme)
GITHUB_WORK_OWNERS=(acme-work)
GITHUB_PERSONAL_DEFAULT_OWNER="acme"
GITHUB_WORK_DEFAULT_OWNER="acme-work"
EOF

REPO="<your working directory>"
printf '%s\n' \
  "U17Leetha" "acme-work" "$SANDBOX3/Personal" "$SANDBOX3/Work" \
  "github-personal" "github-work" "y" \
  "$SANDBOX3/.ssh/pkey" "$SANDBOX3/.ssh/wkey" \
  "none" \
  | PATH="$SANDBOX3/fakebin:$PATH" HOME="$SANDBOX3" "$REPO/git-smart" setup > /dev/null

grep -c "UseKeychain" "$SANDBOX3/.ssh/config.d/git-smart"
```
Expected: `0` — with `uname -s` faked to report `Linux`, no `UseKeychain` lines appear anywhere in the generated file. (This test only fakes `uname`; `git`/`ssh-keygen` etc. still run for real against the sandbox, same as every other test in this plan.)

- [ ] **Step 16: Functional test — `doctor` detects a shadowed identity after the fact**

Reuse `$SANDBOX2` from Step 14 (already correctly configured and verified). Now induce a mismatch by adding a new competing block that itself gets included *before* git-smart's Include line (simulating some other tool or manual edit adding a Host block ahead of it later):

```bash
REPO="<your working directory>"
cat > "$SANDBOX2/.ssh/config.tmp" <<EOF
Host github-personal
  IdentityFile $SANDBOX2/.ssh/wrong_key

EOF
cat "$SANDBOX2/.ssh/config" >> "$SANDBOX2/.ssh/config.tmp"
mv "$SANDBOX2/.ssh/config.tmp" "$SANDBOX2/.ssh/config"

HOME="$SANDBOX2" "$REPO/git-smart" doctor 2>&1 | grep -i "shadowing"
```
Expected: a suggestion line containing "may be shadowing it" for `github-personal` — confirming `doctor`'s new effective-vs-intended check fires correctly when something manages to get inserted ahead of git-smart's own Include line.

- [ ] **Step 17: Functional test — `doctor` detects a missing Include line**

```bash
SANDBOX4="$(mktemp -d)"
mkdir -p "$SANDBOX4/.config"
cat > "$SANDBOX4/.config/git-smart.conf" <<EOF
GIT_SMART_PERSONAL_DIR="$SANDBOX4/Personal"
GIT_SMART_WORK_DIR="$SANDBOX4/Work"
GITHUB_PERSONAL_HOST="github-personal"
GITHUB_WORK_HOST="github-work"
GITHUB_PERSONAL_OWNERS=()
GITHUB_WORK_OWNERS=()
GITHUB_PERSONAL_DEFAULT_OWNER=""
GITHUB_WORK_DEFAULT_OWNER=""
EOF
REPO="<your working directory>"
HOME="$SANDBOX4" "$REPO/git-smart" doctor 2>&1 | grep -i "Include"
```
Expected: a suggestion mentioning the missing `Include ~/.ssh/config.d/git-smart` line (since `$SANDBOX4/.ssh/config` doesn't exist at all in this fresh sandbox).

- [ ] **Step 18: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "fix: move SSH host blocks into an Included dedicated file so they always take priority, and make UseKeychain macOS-only"
```

---

### Task 3: Apply the migration on this machine

This task touches your **real** `~/.ssh/config` — not a sandbox. Your real config currently has git-smart-managed blocks written the old way (from earlier this session), which need migrating to the new approach.

**Files:**
- Modify (real, on this machine): `~/.ssh/config`
- Create (real, on this machine): `~/.ssh/config.d/git-smart`

- [ ] **Step 1: Back up the current SSH config**

```bash
cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S)
```

- [ ] **Step 2: Confirm the currently-installed git-smart has this fix**

```bash
grep -c "GIT_SMART_SSH_INCLUDE_FILE" /usr/local/bin/git-smart
```
Expected: nonzero (confirms Task 1/2 were merged and reinstalled before running this task — if this is `0`, stop and reinstall first: `cd <repo> && sudo ./install.sh`).

- [ ] **Step 3: Re-apply the global default profile to populate the new dedicated file**

```bash
git-smart global --profile work
```
Expected output includes the bare `github.com` block being written to the new location.

- [ ] **Step 4: Re-run switch (or push/pull once) on personal and work repos to populate their blocks**

Since `write_git_smart_ssh_host` regenerates from `current_identity_for_host_config`, and that now reads the *new* file (empty for personal/work until something writes them), the personal/work blocks need one write to populate. The simplest way: re-run `setup`'s SSH section, accepting existing key paths as defaults:

```bash
git-smart setup
```
Answer `y` to "Add or update SSH host entries", accept the existing key path defaults for both personal and work (they should already point at `id_ed25519_github_personal` and `id_ed25519_github_axe`), and answer `work` (or whatever's already configured) at the global-profile prompt.

- [ ] **Step 5: Verify the dedicated file has all three correct blocks**

```bash
cat ~/.ssh/config.d/git-smart
```
Expected: three `Host` blocks (`github-personal`, `github-work`, `github.com`), each with `IdentityFile` matching what was configured before this migration (`id_ed25519_github_personal`, `id_ed25519_github_axe`, `id_ed25519_github_axe` respectively), each with `UseKeychain yes` (this machine is Darwin).

- [ ] **Step 6: Remove the old inline blocks from `~/.ssh/config`**

```bash
cat ~/.ssh/config
```
Confirm the file now has the `Include ~/.ssh/config.d/git-smart` line at the top (added automatically by Step 3/4), followed by the *old* `Host github.com` / `Host github-work` / `Host github-personal` blocks still further down (these are now redundant duplicates, shadowed-but-inert since the Include'd blocks are processed first). Manually edit `~/.ssh/config` to remove those old blocks, leaving only the `Include` line (and anything else unrelated to git-smart, if present).

- [ ] **Step 7: Verify with `ssh -G` and `git-smart doctor`**

```bash
ssh -G github-personal | grep identityfile
ssh -G github-work | grep identityfile
ssh -G github.com | grep identityfile
git-smart doctor
```
Expected: each alias resolves to the correct key path, and `doctor` reports no shadowing/missing-Include suggestions.

- [ ] **Step 8: Live auth check**

```bash
ssh -T github-personal
ssh -T github-work
```
Expected: both print a successful GitHub authentication message for the correct respective account.
