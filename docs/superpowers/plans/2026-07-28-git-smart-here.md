# git-smart here Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `git-smart here [--profile personal|work] [--owner OWNER] [--dry-run]` command that bootstraps the current directory into a tracked personal/work repo in place — `git init`s if needed, wires up the remote, and saves repo-local context — for the case where there's no remote configured yet (errors out pointing at `switch` if one already exists).

**Architecture:** One new function, `run_here()`, that's essentially `run_init()`'s owner-resolution/remote-building/context-saving logic minus "create a new directory elsewhere," plus a guard against operating inside an already-remoted repo or a nested repo. It reuses `ensure_profile_for_creation`, `profile_default_owner`, `build_remote_url`, `write_repo_context`, `profile_host` — no new helpers, no new config fields.

**Tech Stack:** Bash, same conventions as the rest of `git-smart` (`set -euo pipefail`, `info`/`warn`/`die`, `--dry-run` support throughout). No automated test suite in this repo — verification is via sandboxed `HOME`/temp-directory runs, matching the project's established convention.

---

### Task 1: Implement `git-smart here`

**Files:**
- Modify: `git-smart` (`usage`)
- Modify: `git-smart` (add `usage_here`, between `usage_clone` and `usage_push`)
- Modify: `git-smart` (`parse_global_args`)
- Modify: `git-smart` (`parse_common_option`)
- Modify: `git-smart` (`parse_command_args`)
- Modify: `git-smart` (add `run_here`, between `run_clone` and `show_repo_context`)
- Modify: `git-smart` (`main`)

(Anchor every edit on the "Find:" code blocks below, not on line numbers — they'll shift slightly as earlier edits land.)

- [ ] **Step 1: Add `here` to the usage banner**

Find:
```bash
  init      Create a new repo in the correct personal/work directory
  clone     Clone a repo into the correct personal/work directory
  push      Commit and push using the repo's saved context
```
Replace with:
```bash
  init      Create a new repo in the correct personal/work directory
  clone     Clone a repo into the correct personal/work directory
  here      Attach the current directory to a profile (bootstrap the remote)
  push      Commit and push using the repo's saved context
```

- [ ] **Step 2: Add `usage_here`**

Find:
```bash
usage_clone() {
  cat <<'EOF'
Usage: git-smart clone [options] <owner/repo> [destination]

Options:
  --profile personal|work|auto
  --dry-run

If --profile is omitted, git-smart will infer from owner or ask interactively.
EOF
}

usage_push() {
```
Replace with:
```bash
usage_clone() {
  cat <<'EOF'
Usage: git-smart clone [options] <owner/repo> [destination]

Options:
  --profile personal|work|auto
  --dry-run

If --profile is omitted, git-smart will infer from owner or ask interactively.
EOF
}

usage_here() {
  cat <<'EOF'
Usage: git-smart here [options]

Options:
  --profile personal|work
  --owner OWNER
  --dry-run

Attaches the current directory to a profile: runs git init if needed,
adds the remote (the GitHub repo must already exist), and saves repo
context. Fails if a remote is already configured -- use 'git-smart
switch' for that case instead.
EOF
}

usage_push() {
```

- [ ] **Step 3: Accept `here` as a command**

Find:
```bash
    setup|init|clone|push|pull|status|where|open|switch|global|doctor)
      COMMAND="$1"
      shift
      ;;
```
Replace with:
```bash
    setup|init|clone|here|push|pull|status|where|open|switch|global|doctor)
      COMMAND="$1"
      shift
      ;;
```

- [ ] **Step 4: Route `-h`/`--help` for `here`**

Find:
```bash
        init) usage_init ;;
        clone) usage_clone ;;
        push) usage_push ;;
```
Replace with:
```bash
        init) usage_init ;;
        clone) usage_clone ;;
        here) usage_here ;;
        push) usage_push ;;
```

- [ ] **Step 5: Accept `--owner` for `here`**

Find:
```bash
      switch)
        case "$1" in
          --owner)
            [[ $# -ge 2 ]] || die "--owner requires a value"
            INIT_OWNER="$2"
            shift
            ;;
          *)
            break
            ;;
        esac
        ;;
      pull|status|where|open|global|doctor)
        break
        ;;
```
Replace with:
```bash
      switch)
        case "$1" in
          --owner)
            [[ $# -ge 2 ]] || die "--owner requires a value"
            INIT_OWNER="$2"
            shift
            ;;
          *)
            break
            ;;
        esac
        ;;
      here)
        case "$1" in
          --owner)
            [[ $# -ge 2 ]] || die "--owner requires a value"
            INIT_OWNER="$2"
            shift
            ;;
          *)
            break
            ;;
        esac
        ;;
      pull|status|where|open|global|doctor)
        break
        ;;
```

- [ ] **Step 6: Implement `run_here`**

Find:
```bash
show_repo_context() {
```
Replace with:
```bash
run_here() {
  local repo_name owner remote_url toplevel

  ensure_profile_for_creation

  repo_name="$(basename "$PWD")"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    toplevel="$(git rev-parse --show-toplevel)"
    if [[ "$toplevel" != "$PWD" ]]; then
      die "This directory is inside an existing repo at $toplevel. Run 'git-smart here' from a directory that isn't nested inside another repo."
    fi
  else
    if [[ "$DRY_RUN" -eq 0 ]]; then
      git init -b main
    else
      printf '[*] Dry run: git init -b main\n'
    fi
  fi

  if git remote get-url "$REMOTE" >/dev/null 2>&1; then
    die "Remote '$REMOTE' is already configured for this repo. Run 'git-smart switch --profile $PROFILE' instead."
  fi

  owner="$INIT_OWNER"
  if [[ -z "$owner" ]]; then
    owner="$(profile_default_owner "$PROFILE")"
  fi
  if [[ -z "$owner" ]]; then
    owner="$(prompt "GitHub owner for this repo")"
  fi

  remote_url="$(build_remote_url "$owner" "$repo_name" "$PROFILE")"

  info "Profile   : $PROFILE"
  info "Owner     : $owner"
  info "Repo dir  : $PWD"
  info "Remote URL: $remote_url"
  printf '\n'

  if [[ "$DRY_RUN" -eq 0 ]]; then
    git remote add "$REMOTE" "$remote_url"
    write_repo_context "$PROFILE" "$owner" "$(profile_host "$PROFILE")"
  else
    printf '[*] Dry run: git remote add %s %s\n' "$REMOTE" "$remote_url"
  fi

  info "Attached $repo_name to profile '$PROFILE'."
  info "Remote set to $remote_url"
  info "Done."
}

show_repo_context() {
```

- [ ] **Step 7: Dispatch `here` in `main`**

Find:
```bash
    init) run_init ;;
    clone) run_clone ;;
    push) run_push ;;
```
Replace with:
```bash
    init) run_init ;;
    clone) run_clone ;;
    here) run_here ;;
    push) run_push ;;
```

- [ ] **Step 8: Syntax check**

Run: `bash -n git-smart`
Expected: no output, exit code 0.

- [ ] **Step 9: Functional test — fresh directory, no repo yet**

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

mkdir -p "$SANDBOX/somewhere/my-project"
cd "$SANDBOX/somewhere/my-project"
HOME="$SANDBOX" "$REPO/git-smart" here --profile personal

echo "--- git-smart context ---"
git config --local --get git-smart.profile
git config --local --get git-smart.owner
git config --local --get git-smart.sshHost
echo "--- remote ---"
git remote get-url origin

cd /
rm -rf "$SANDBOX" 2>/dev/null || true
```
Expected:
```
personal
acme
github-personal
```
and remote `git@github-personal:acme/my-project.git` (repo name taken from the directory name `my-project`, owner defaulted from `GITHUB_PERSONAL_DEFAULT_OWNER` since `--owner` wasn't passed).

- [ ] **Step 10: Functional test — directory is already a repo (no remote)**

Same as Step 9 but before running `git-smart here`, run `git init -b main` yourself first in `my-project`. Expected: `here` does NOT error or re-init (no "Reinitialized" message), and produces the same correct context/remote as Step 9.

- [ ] **Step 11: Functional test — remote already exists**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
mkdir -p "$SANDBOX/proj"
cd "$SANDBOX/proj"
git init -b main >/dev/null
git remote add origin git@github.com:someone/proj.git

HOME="$SANDBOX" "$REPO/git-smart" here --profile personal --owner acme
echo "exit code: $?"

cd /
rm -rf "$SANDBOX" 2>/dev/null || true
```
Expected: `[!] Remote 'origin' is already configured for this repo. Run 'git-smart switch --profile personal' instead.` printed to stderr, exit code 1.

- [ ] **Step 12: Functional test — nested repo**

```bash
SANDBOX="$(mktemp -d)"
REPO="<your working directory>"
mkdir -p "$SANDBOX/outer/inner"
cd "$SANDBOX/outer"
git init -b main >/dev/null
cd "$SANDBOX/outer/inner"

HOME="$SANDBOX" "$REPO/git-smart" here --profile personal --owner acme
echo "exit code: $?"

cd /
rm -rf "$SANDBOX" 2>/dev/null || true
```
Expected: a `[!] This directory is inside an existing repo at .../outer...` message printed to stderr, exit code 1. (The exact toplevel path in the message will include the SANDBOX path — just confirm the message shape and exit code, not an exact string match.)

- [ ] **Step 13: Functional test — `--dry-run` makes no changes**

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
mkdir -p "$SANDBOX/dry-project"
cd "$SANDBOX/dry-project"

HOME="$SANDBOX" "$REPO/git-smart" here --profile personal --dry-run | grep -i "dry run"

[[ -d ".git" ]] && echo "FAIL: .git was created" || echo "PASS: no .git created"

cd /
rm -rf "$SANDBOX" 2>/dev/null || true
```
Expected: dry-run messages printed (`Dry run: git init -b main`, `Dry run: git remote add origin ...`), and `PASS: no .git created`.

- [ ] **Step 14: Commit**

```bash
cd <your working directory>
git add git-smart
git commit -m "feat: add git-smart here to attach the current directory to a profile"
```

---

### Task 2: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add to "What it does"**

Find:
```markdown
- machine-wide default profile (SSH host + git identity) for tools outside git-smart
- repo-local context storage
```
Replace with:
```markdown
- machine-wide default profile (SSH host + git identity) for tools outside git-smart
- attach an existing directory to a profile in place
- repo-local context storage
```

- [ ] **Step 2: Add to "Main commands"**

Find:
```markdown
git-smart init
git-smart clone owner/repo
git-smart push
```
Replace with:
```markdown
git-smart init
git-smart clone owner/repo
git-smart here --profile personal
git-smart push
```

- [ ] **Step 3: Add a short "Attaching an existing directory" section**

Find:
```markdown
## Global default profile
```
Replace with:
```markdown
## Attaching an existing directory

If you `cd` into a directory that has no git repo yet (or has one but no
remote configured) and want to bind it to a profile:

```bash
git-smart here --profile personal
```

This runs `git init` if needed (skipping it if the directory is already a
repo rooted there), adds the remote (the GitHub repo must already exist --
`here` doesn't create it for you), and saves the same repo-local context
`switch` does. If a remote is already configured, `here` refuses and points
you at `git-smart switch` instead, which is the right tool for rebinding an
already-remoted repo.

## Global default profile
```

- [ ] **Step 4: Review the rendered file**

Run: `cat README.md`
Expected: reads cleanly, code fences balanced (`grep -c '^```' README.md` even), new section appears between "Main commands"-adjacent content and "Global default profile".

- [ ] **Step 5: Commit**

```bash
cd <your working directory>
git add README.md
git commit -m "docs: document git-smart here"
```
