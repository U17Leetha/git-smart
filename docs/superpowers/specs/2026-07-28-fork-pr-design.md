# `git-smart fork` and `git-smart pr`

## Problem

Per the broader adversarial UX review of this tool, the single most common "contribute to someone else's project" flow — fork, clone, branch, open a PR — isn't supported at all today. `git-smart` has commands for repos you own (`init`, `clone`, `here`, `switch`) but nothing for repos you don't, and nothing to actually submit work back.

## Goals

- `git-smart fork <owner/repo>` forks a repo on GitHub, clones the fork into the correct personal/work directory using git-smart's own SSH-alias remote (consistent with every other command), and adds a read-only `upstream` remote pointing at the original.
- `git-smart pr` opens a PR for the current branch via `gh pr create` (delegating the actual interactive flow to `gh`, which already does this well).
- `git-smart pr --status` shows the PR tied to the current branch, if one exists, via `gh pr view`.

## Non-goals

- No management of `gh`'s own authentication/account switching. Forking always goes to whichever GitHub account `gh` is currently authenticated as; `--profile` on `fork` only controls the *local* side (target directory, SSH host alias for the fork's own remote).
- No `--dry-run` for `pr` (it doesn't mutate any local git-smart-managed state itself — it delegates directly to `gh`), matching the existing precedent set by `open`.
- No reimplementation of `gh pr create`'s interactive title/body/base-branch flow — `git-smart pr` execs straight into it.
- No `gh pr status`-style multi-repo dashboard — `pr --status` is scoped to the current branch's PR only (`gh pr view`), matching what was actually asked for ("status of the PR for the current branch, if one exists").

## Design

### Shared: `require_gh()`

```bash
require_gh() {
  command -v gh >/dev/null 2>&1 || die "This command requires the gh CLI. Install it from https://cli.github.com and run 'gh auth login'."
}
```

### `git-smart fork <owner/repo> [--profile personal|work] [--dry-run]`

1. `require_gh`.
2. Resolve profile via `ensure_profile_for_creation` (prompts if `--profile` omitted), same pattern as `init`.
3. Parse `owner/repo` from the positional argument (same validation regex `init`/`clone` already use).
4. `gh repo fork "$owner/$repo" --clone=false` (respecting `--dry-run`: print what would run instead).
5. Determine the fork's owner: `gh api user --jq .login` (your currently-authenticated `gh` account).
6. `target_dir="$(profile_base_dir "$PROFILE")/$repo"` (same pattern as `init`/`clone`).
7. `clone_url="$(build_remote_url "$fork_owner" "$repo" "$PROFILE")"` — reuses the existing helper, so the fork's `origin` remote uses git-smart's own SSH host alias like every other repo.
8. `git clone "$clone_url" "$target_dir"`.
9. `git -C "$target_dir" remote add upstream "https://github.com/$owner/$repo.git"` — plain HTTPS, no SSH key needed (you typically don't have push access to upstream, which is the reason you forked).
10. `write_repo_context "$PROFILE" "$fork_owner" "$(profile_host "$PROFILE")"` in the new directory (same pattern as `init`/`clone`).
11. Print a summary (profile, fork owner, target dir, origin URL, upstream URL).

### `git-smart pr [--status]`

- `require_gh`, `ensure_repo`.
- No flag: `exec gh pr create` (replaces the current process — `gh` fully owns the interactive flow, no wrapping needed).
- `--status`: `exec gh pr view` (shows the PR for the current branch, or `gh`'s own "no pull requests found" message if none exists — no need to reinvent that).

Using `exec` (rather than a plain call) is deliberate: once we've confirmed prerequisites (`gh` present, inside a repo), there's nothing git-smart itself needs to do after `gh` finishes, so handing off the process directly avoids an unnecessary wrapper layer and lets `gh`'s own exit code/signal handling pass through untouched.

## Error handling

- Missing `gh`: `die` with an install pointer, for both commands.
- `fork`'s positional arg validation: reuse the exact `owner/repo` regex check `run_clone` already uses, same error message shape.
- If `gh repo fork` itself fails (network, already forked, no access), its own error output surfaces directly — no attempt to reinterpret `gh`'s errors (out of scope; `gh`'s own error messages are already reasonably clear for these API-level failures).

## Testing

No automated test suite in this repo (established convention). `fork` cannot be tested fully offline (forking is a real GitHub API call) — verification will be structural: `bash -n`, dry-run output inspection, and confirming the local-side logic (target directory, `build_remote_url` usage, `upstream` URL construction, repo-context writing) is correct by reading the code and cross-checking against `run_clone`'s already-verified equivalent logic, plus (if the user is willing) one real manual fork of a small test repo to confirm end-to-end. `pr` is a thin `exec` wrapper with no independent logic to unit-test beyond the prerequisite checks (`gh` present, inside a repo) and correct flag routing (`create` vs `view`), verifiable via `bash -n` and inspecting the exact `gh` invocation without actually running it against a real PR.
