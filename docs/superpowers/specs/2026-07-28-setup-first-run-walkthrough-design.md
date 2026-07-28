# First-run walkthrough for `git-smart setup`

## Problem

`git-smart setup` currently assumes the person running it already understands git/GitHub concepts: it asks for a "GitHub owner," an "SSH host alias," offers to generate SSH keys, and prints a public key with no explanation of what any of that means or why it's needed. That's fine for the tool's original author, but per the broader adversarial review of this tool, it's a real barrier for anyone less experienced. This is the first of several improvements identified in that review; the others (guarding `push`, translating common errors, PR/fork support) are separate, independent pieces of work.

## Goals

- A genuine first-time run of `git-smart setup` explains each concept (owner, directories, SSH keys, the global default) in plain English before asking for it, and gives explicit numbered steps (with the exact GitHub URL) for adding a generated SSH key.
- A re-run (config file already exists) behaves exactly as it does today — no explanations, same terse prompts. No flag to remember.
- No change to `setup`'s actual logic/control flow, only to what gets printed before existing prompts. `--dry-run` is unaffected.

## Non-goals

- No changes to any command other than `setup`.
- No interactive "explain mode" toggle/flag — first-run detection is automatic and is the only mechanism (per your explicit choice during brainstorming).
- No restructuring of `run_setup()` into a data-driven/table-based step list — plain inline blocks, consistent with the rest of the file's imperative style (see design doc rationale below).

## Design

### First-run detection

```bash
local is_first_run=0
[[ -f "$CONFIG_FILE" ]] || is_first_run=1
```
Computed as the very first statement in `run_setup()`, before any prompts and before `save_config` (which creates the file) runs.

### Explanatory blocks

Seven blocks, each `printf`'d only when `is_first_run -eq 1`, inserted immediately before the existing prompt(s) they relate to. Exact text (final, not placeholder):

1. **Opening** (right after the existing `info "Interactive git-smart setup"` / blank line):
   > git-smart helps you use two separate GitHub identities on this machine --
   > one for personal projects, one for work -- without having to remember which
   > SSH key or git config to use each time. This asks a handful of questions;
   > the default shown in [brackets] is almost always fine -- just press Enter.

2. **Before the owner prompts**:
   > A GitHub "owner" is whoever a repo belongs to -- usually your own username,
   > but it can be an organization name (common for work repos).

3. **Before the directory prompts**:
   > These are the folders on your computer where git-smart will put new
   > personal and work repos, and where it looks to guess which profile a
   > repo belongs to.

4. **Before the SSH host alias prompts**:
   > These next two are internal nicknames git-smart uses in your SSH config
   > to tell your personal and work keys apart -- the defaults are fine, just
   > press Enter.

5. **Before the "Add or update SSH host entries?" prompt**:
   > GitHub uses an SSH key to know it is really you connecting, instead of
   > typing a password every time. If you do not already have separate keys
   > for personal and work, git-smart can generate them now.

6. **After each key is printed** (once for personal, once for work, right after the existing `show_public_key_details` call for that key):
   > To add this key to GitHub:
   >   1. Copy the public key printed above
   >   2. Go to https://github.com/settings/ssh/new
   >   3. Give it a memorable title, e.g. "personal key" (or "work key")
   >   4. Paste the key into the "Key" field and click "Add SSH key"

7. **Before the global-default-profile prompt**:
   > One more thing: your computer has a single "default" GitHub identity for
   > tools that do not go through git-smart (like a plain "git clone" or the
   > gh tool from GitHub). Setting one here makes that default match one of
   > your profiles instead of being left unset.

The existing "Next steps" summary at the end of `run_setup` is left unchanged — it's a reasonable recap either way and doesn't need first-run-specific content once block 6 has already walked through the GitHub-side steps inline.

### Why inline blocks, not a data-driven step list

Considered restructuring `run_setup()` into an array of step definitions (prompt function + optional explanation), driven by one loop. Rejected: bash doesn't have first-class functions, so this would mean function-name-array indirection, which is harder to read than the current plain imperative style and inconsistent with the rest of the file (no other command uses this pattern). Inline blocks, gated by one boolean, is the smallest change that achieves the goal and matches the codebase's existing conventions.

## Error handling

None of this changes control flow — it's purely additional `printf` output gated on a boolean computed once at the top of the function. No new failure modes. `is_first_run` has no effect on `DRY_RUN`, `save_config`, or any SSH/git mutation.

## Testing

No automated test suite in this repo (established convention). Verification: run `setup` in a sandboxed `HOME` with no existing config file and confirm all 7 explanatory blocks appear in the right places; run it again in the same sandbox (config file now exists) and confirm zero explanatory text appears and prompts/defaults are identical to the pre-change behavior.
