---
name: review-worktree-pass
description: Use when selecting or implementing remediation actions for code-review findings, adversarial-review findings, cross-vendor review follow-ups, AI-findings, CodeQL, or Sonar. Do not use for read-only review, review-digest, or audit requests.
---

# Code-review pass workflow

Code-review-driven fix passes (reviewer findings, adversarial-review remediation,
cross-vendor review follow-ups) **must run in a dedicated review worktree**, not
in the primary project checkout, with one numbered branch per pass.

## Where to work

- Each review project has a single review worktree at
  `<project>\.claude\worktrees\reviewer-passes`. The `.claude` segment is
  literal **regardless of which agent** you are; this is a shared project
  location, not a per-runtime config directory, so there is no `.codex` or
  `.gemini` variant. **Read the project's own memory for its exact path and
  current lifecycle state**, then verify the path with `git worktree list`
  before using or recreating it. Do not assume a historical project example is
  still live.
- When the user asks to select or implement remediation actions for review
  findings, use `git worktree list` to choose one path:
  - **If the review worktree already exists** for an in-flight pass, `cd` into
    it and run `git fetch --prune` as a discrete command before any new branch
    choice. Resolve and verify the project mainline using the procedure below.
  - **If the review worktree is absent** after teardown, `cd` to the verified
    primary checkout (confirm it with `git worktree list`) and run
    `git fetch --prune` as a discrete command. Resolve and verify the project
    mainline from `origin/HEAD`, then select the next batch number and create the
    branch with
    `git worktree add -b reviewer-findings-batch<N> <review-worktree-path> <mainline-ref>`.
    This creates the dedicated worktree; it does not branch the primary
    checkout.

After fetching, resolve `<mainline-ref>` with
`git symbolic-ref --quiet --short refs/remotes/origin/HEAD`. If that symbolic
ref is absent, use `git ls-remote --symref origin HEAD` and accept only its
single advertised `refs/heads/<branch>` target as `origin/<branch>`. Verify the
result with `git rev-parse --verify --quiet "<mainline-ref>^{commit}"`; stop if
the remote HEAD is missing, ambiguous, or not present in the refreshed local
refs. Record that verified ref and use it throughout the pass.

**Why:** the primary checkout is where parallel feature work, dogfooding, and
manual exploration live. Letting a review pass land there overlaps with in-flight
work — stale local commits, untracked artefacts, the wrong branch checked out —
and makes merge cleanup unreliable.

## Branch numbering

Branches inside that worktree follow `reviewer-findings-batch<N>` (or the
project's established numbering). Increment monotonically — never reuse a number,
never start a new batch without merging or abandoning the prior one.

## Before you push

Run the repo's full local check suite **in this worktree** before the push that
opens or updates the PR — the *Build and test before pushing a PR* rule, whose
own rationale is written around exactly this workspace ("the whole point of a
worktree is to run exactly this check without disturbing the primary checkout").
For a TS/JS repo that is typecheck, lint, the full test run, and a build when an
SSR-rendered component was touched; elsewhere it is that repo's equivalent.

Push **once**, when the batch is finished. Every push re-spends review budget, so
fold review findings, lint fixes and nits into the same branch rather than
pushing per fix.

Once a batch's PR may have merged, never push follow-ups to that branch: with
auto-delete-on-merge the remote branch is already gone, and a later push silently
re-creates it as an orphan with no PR, so the commits never reach `main`. The
tell is `git push` printing `* [new branch]` for a branch you believed existed.
Start `reviewer-findings-batch<N+1>` instead — which the monotonic numbering rule
above already gives you.

## Teardown

The review worktree and its branch are **ephemeral** — they exist only while a
pass is in flight. Nothing should linger between passes: when a pass is done
(branch merged into the verified `<mainline-ref>`, repo clean, `origin` clean,
no pass running),
**remove both** the worktree and the `reviewer-findings-batch<N>` branch.
Recreate them from scratch (`git worktree add` + branch from the verified
`<mainline-ref>`) at
the start of the next review.

## Close the review artefact

Only after all findings are fixed, declined with reasoning, or explicitly deferred,
update the source run's `_index.md` from `disposition: reviewed` to
`disposition: remediated` and add `remediation-tip: <40-character mainline SHA>`.
Use the post-merge commit on the refreshed verified mainline, then run the review
producer's `validate-report.ps1 -Path <run-folder> -RepoPath <repo>`. Do not close
the artefact while any finding lacks a disposition. This machine closure supersedes
generated handoff prompts; historical ledger files remain immutable.

Stale-after-merge cleanup (pre-authorised post-merge tidy): before deleting the
branch, confirm it is genuinely merged using the rebase-merge fingerprint from
the *Pull request merge style* rule: **both** the remote branch is gone and the
local branch's commit titles match the rebased commits on the verified
mainline. An empty
`git diff <mainline-ref>..<branch>` is useful supplemental evidence, never a
substitute for either required check.

Because the branch is checked out in the worktree, first change the shell's
working directory to the verified primary checkout (or another safe directory
outside the review worktree). Then run `git worktree remove <path>`, which frees
the branch for `git branch -D reviewer-findings-batch<N>`. Do this as part of
finishing the pass — do not leave a parked worktree or merged branch behind.
