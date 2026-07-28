# Fail-closed prompts, config injection fix, staged-index protection, remote-owner confirmation

## Problem

Four related High-severity findings from the independent audit, all in the same theme — git-smart silently proceeds with a dangerous or wrong action instead of stopping and asking:

1. **Fail-open prompts.** `prompt()`, `prompt_yes_no()`, and `resolve_profile_interactively()` don't check `read`'s exit status. On EOF/no-stdin (a non-interactive invocation, or — as demonstrated live during this session's migration step — running a command in a context where stdin closes immediately), `prompt_yes_no` silently uses its default answer (often "yes") and `prompt` proceeds with an empty value, rather than failing.
2. **Config injection.** `save_config` writes an unquoted heredoc with array values interpolated raw; any owner/name containing shell metacharacters corrupts the config or executes code when next `source`d. The file is also never `chmod`ed, and `load_config` sources it with no permission check.
3. **`push` destroys pre-existing staged changes.** Declining the commit confirmation runs a bare `git reset`, unstaging *everything* — including anything the user had staged before running git-smart, not just what git-smart itself staged.
4. **Silent remote-owner rewriting.** `rewrite_remote_if_needed` retargets the remote to a different repository whenever the resolved owner differs, with no distinction between "just the host alias changed" (safe) and "the owner changed" (could mean stored context has drifted from reality) — and no confirmation either way.

## Goals

- Every interactive prompt fails closed (dies, or returns "no") on EOF instead of silently proceeding with a default.
- `save_config` can't be corrupted or exploited by a value containing shell metacharacters; the config file is `chmod 600`; `load_config` refuses to source a group/world-accessible file.
- `push` refuses to run if the index already has staged changes, rather than risking destroying them later.
- Rewriting a remote to a *different owner* (not just a different host alias for the same owner) requires explicit confirmation.

## Non-goals

- No change to `prompt_yes_no`'s *default* answer values at existing call sites (still "y" where it was "y") — only EOF/read-failure handling changes.
- No general secrets-management or encryption for the config file — `chmod 600` + refusing insecure permissions is the full scope here.
- No `--yes`/`SKIP_CONFIRM` bypass for the new remote-owner confirmation — it's rare enough that requiring an explicit answer every time is acceptable; a bypass can be a separate future decision if it proves annoying.

## Design

### 1. Fail-closed prompts

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

resolve_profile_interactively() {
  local answer=""

  while true; do
    read -r -p "Use personal or work profile? [personal/work]: " answer || die "No input available (stdin closed). Pass --profile personal|work."
    case "${answer,,}" in
      personal|p) printf 'personal\n'; return ;;
      work|w) printf 'work\n'; return ;;
    esac
  done
}
```

### 2. Config injection fix

`save_config` rebuilt using `printf '%q'` for every scalar and array element, replacing the unquoted heredoc entirely, followed by `chmod 600 "$CONFIG_FILE"`. `load_config` gains a permission check before `source`, using `stat` in both BSD (`-f '%Lp'`) and GNU (`-c '%a'`) forms (git-smart already supports both macOS and Linux per `install.sh`):

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
  ...
```

**Related tightening:** the bash version gate (shipped earlier this session) moves from `BASH_VERSINFO[0] < 4` to requiring bash >= 4.4, since bash 4.0–4.3 still has the empty-array-expansion-under-`set -u` failure the audit flagged, and both the new `save_config` and pre-existing code (`owner_in_list`) hit exactly that pattern.

### 3. `push` refuses to run over a pre-existing staged index

In `run_push`, before staging:
```bash
if [[ "$DRY_RUN" -eq 0 ]] && ! git diff --cached --quiet; then
  die "You already have staged changes. Commit them yourself first, or run 'git-smart push --push-only' to push without staging/committing anything new."
fi
```

### 4. Confirm before rewriting a remote to a different owner

In `rewrite_remote_if_needed`, after computing `new_url` but before applying it:
```bash
if [[ -n "$REMOTE_OWNER" && "$TARGET_OWNER" != "$REMOTE_OWNER" ]]; then
  warn "The remote's current owner is '$REMOTE_OWNER', but git-smart is about to retarget it to '$TARGET_OWNER'."
  prompt_yes_no "Retarget $REMOTE from ${REMOTE_OWNER}/${REMOTE_REPO} to ${TARGET_OWNER}/${REMOTE_REPO}?" "n" \
    || die "Aborted. If '$REMOTE_OWNER' is correct, run 'git-smart switch --owner $REMOTE_OWNER' to fix the saved context instead."
fi
```
This only fires when the *owner* actually differs — a normal `git-smart switch --profile work` (no `--owner` override) resolves its target owner from the current remote's owner by default, so the common host-alias-only-change case is unaffected.

## Error handling

- All four fixes rely on the existing `die`/`warn` conventions — no new error-reporting mechanism.
- The config permission check's `stat` fallback chain (`-f` then `-c`) means an unrecognized `stat` variant (neither BSD nor GNU) results in `perms` being empty, which the `-n "$perms"` guard treats as "can't determine, skip the check" rather than a false positive — fails open only in the sense of "couldn't check," not "found insecure and ignored it."

## Testing

No automated test suite in this repo (established convention). Verification: sandboxed `HOME` runs confirming (a) `prompt_yes_no` returns "no" on `</dev/null` regardless of default, (b) `prompt`/`resolve_profile_interactively` die cleanly on EOF instead of hanging or looping, (c) a config value containing `$( )`/spaces/quotes round-trips correctly through `save_config`/`load_config` without corruption or execution, (d) a config file `chmod`ed group-writable is refused with a clear message, (e) `push` refuses when the index already has staged changes before git-smart runs, confirming nothing is touched, (f) the remote-owner-drift confirmation fires only when the owner actually differs, not on a normal profile-only switch.
