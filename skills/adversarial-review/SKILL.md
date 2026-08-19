---
name: adversarial-review
description: Use when the user requests an adversarial, cross-vendor, or multi-model code review, now or deferred, or runs /adversarial-review. Reviews a branch, diff, pull request, module, or whole-repository audit inside Git; for multi-repository sweeps use review-sweep.
---

# Adversarial Review

Run a multi-vendor panel whose value is uncorrelated error: blind findings,
anonymous cross-examination, separate adjudication, and live-code verification.
Always invoke this skill for its trigger phrases. Never substitute a panel of
general-purpose same-host workers.

Read `reviewers.json` every run; do not name a remembered panel. Pass files
under `briefs/` verbatim. Canonical contracts below says which file owns what.

## Usage

```text
/adversarial-review [<target>] [-- <pathspec>…]
```

- no target: current branch and working tree against the default-branch base;
- PR number: `gh pr diff`; pathspecs are rejected because that transport cannot
  apply them;
- ref/range: Git diff against that revision/range;
- `audit -- <pathspec>`: current state against the empty tree.

Whole-repository audits are split into cohesive subsystem pathspecs, never one
giant diff. Exclude generated/migration/build outputs where appropriate.

## Pre-flight

1. Require a Git worktree and read the active manifest.
2. Resolve each enabled primary wrapper and execute the exact
   `PREFLIGHT_COMMAND:` from its header; accept only `PREFLIGHT_SUCCESS:`. Try a
   declared `fallbackWrapper` identically and disclose metered/degraded use.
   **Host step — `run-review.ps1` does not parse those headers**; skipping it moves
   auth failures into a paid parallel round. A wrapper declaring no
   `PREFLIGHT_COMMAND:` is unverified, not passing.
3. Stop if available vendors fall below `minVendors`.
4. For a dirty target, include the working-tree diff deliberately or stop;
   never imply uncommitted work was reviewed when it was invisible. This is
   **enforced, not advisory**: `run-review.ps1` checks `git status --porcelain`
   before resolving the target. A bare branch/SHA target picks the working tree up
   anyway, but an `audit` shape and an explicit `A..B` range are tree-to-tree and
   exclude it silently — for those, the driver stops unless the omitted paths are
   recorded in `status.json` and in the judge packet.

## Procedure

### 0. Resolve and size

Resolve the target exactly as Usage states. Capture the diff, added/total lines,
and estimated tokens. Repo-blind reviewers receive compact diffs when the driver
crosses its transport gate; routing comes from each manifest entry's
`repoAccess`, never hardcoded IDs.

Before choosing a repository-aware Codex route, read the canonical
`~/.agents/notes/model-routing-traps.md`; its current repository-awareness
constraints control that mode.

### 1–2. Blind review and cross-examination

Run the driver once per approved chunk. It passes
`briefs/phase1-review.txt` (with the relevant audit/system preamble) to enabled
reviewers, pools and anonymises findings, then passes
`briefs/phase2-cross-examine.txt` with the pooled set.

Phase 1 and Phase 2 must each retain `minVendors`; zero output or a diversity
collapse stops before metrics or a judge packet. Wrapper failures are visible,
and only manifest-declared fallbacks may replace them.

### 3. Adjudicate

Use `roles.judge` from the manifest with `briefs/phase3-adjudicate.txt` and the
driver's judge packet. Measure consensus by vendor, not reviewer headcount.
Preserve contested findings, correct factually refuted mechanisms, and inspect
the repository when a repo-blind limitation leaves a mechanism unsettled.

### 3.5. Optional judge audit

Only when requested or required by the run's risk policy, select from
`roles.judgeAudit.pool` and pass `briefs/phase3.5-judge-audit.txt` verbatim.
This checks the adjudicator for dropped/misrated findings; it does not replace
verification.

**Fold every `Correction:` into `report.md` before Phase 4 and record what was
folded.** Phase 4 verifies findings *in the report*, so an unfolded `DROPPED`
finding is invisible to it and the audit produces no engineering outcome. A
finding restored or promoted to High by a correction enters Phase 4 like any other.

### 4. Verify

Every High and every contested finding is verified against live code by a fresh
worker selected from `roles.verifier.pool`, rotating vendors. Prefer a vendor
other than the one that raised the finding; `briefs/phase4-verify.txt` requires
the verifier to reach its own verdict regardless, so a same-vendor check is a
weaker result, not an invalid one — say which it was. Use that brief verbatim.
Record `CONFIRMED`, `REFUTED`, or `INDETERMINATE` with file/line evidence. Never
publish a High solely because a blind reviewer sounded confident.

**Honour each pool member's own `repoAccess`** — declared per member, not per role.
A member whose wrapper has no per-invocation read-only mode is `false`: give it the
diff and context files, or a **detached-commit `git worktree`**, never `-RepoPath` on
the live tree. Otherwise a verifier can write to the tree it is verifying.

### 5. Synthesize and persist

For multi-chunk audits, use `roles.synthesis` and `briefs/synthesis.txt` to
deduplicate, reconcile severity, preserve contention, and surface cross-cutting
themes. Do not re-review during synthesis.

Write the final report additively to
`<vault>\Claude\Adversarial Review\<repo>\<RunId>\` (`RunId` = `yyyyMMddTHHmmssZ`).
**The per-run folder is required.** Consumers scan `<repo>\<run-folder>\_index.md`
(`review-digest/collect.ps1`, `state-of-play`); writing into `<repo>\` leaves
`vault.exists` false, so the report is never discovered and successive runs collide.
Contents:

- `_index.md` — `project`, `review-type`, `date`, `target`, `reviewers`, `judge`,
  severity tally, and `subsystem: <pathspec>` when the target was
  `audit -- <pathspec>`. Omitting `subsystem` makes a one-subsystem pass establish a
  **repo-wide** boundary, and every unexamined subsystem then reads as reviewed;
- `report.md` — target, manifest-derived participants, findings, vendor consensus,
  Phase 4 evidence, chunk coverage;
- `working/` — per-phase transcripts and the judge packet.

Resolve `<vault>` from the runtime's active user instructions; do not hardcode a
drive letter, then gate the run folder with `validate-report.ps1`; fix and re-run
until clean. The chat response leads with Critical/High findings, contested items,
evidence gaps, and the report path.

Review is read-only. Remediation is a separate approved pass in the dedicated
review worktree.

## Telemetry

Use wrapper sidecars when available. Where a selector is a moving alias,
`run-review.ps1` resolves the actual invoked model and current prices from the
canonical model registry; when that cannot be resolved, record unknown/zero
transport cost with `costUnknown=true`, rendered as `UNKNOWN`, rather than a
stale estimate or a displayed zero.

`IssuesAccepted` credits only a vendor's own Phase-1 findings that survive
adjudication and verification. Derive provenance from the pooled map, never
from consensus tags; accepted cannot exceed raised. Subscription-backed calls
have zero marginal API spend, while a declared API fallback is metered and must
be disclosed.

**Who emits.** Multi-chunk runs emit via `aggregate-and-emit.ps1`. A **single-chunk**
run has no aggregator: the host calls `emit-review-telemetry.ps1` after Phase 4, once
per participant plus the judge, with the work directory's `-RunId`. The Observatory
upserts on `(runId, reviewer, role)` — a repeated `Role` overwrites, an omitted one is
a swallowed HTTP 400. Skip this and a single-chunk run never reaches the dashboard.

## Canonical contracts

| Contract | Source |
|---|---|
| Panel/roles/access/fallbacks | `reviewers.json` |
| Phase prompts | `briefs/*.txt` |
| Deterministic Phase 1/2 driver | `run-review.ps1` |
| Multi-chunk driver/aggregation | `batch-review.ps1`, `aggregate-and-emit.ps1` |
| Telemetry emission (one row per participant) | `emit-review-telemetry.ps1` |
| Design rationale | `docs/METHODOLOGY-v2.md` |

Do not mirror prompt bodies or roster/model facts here. Change the canonical
file and its contract tests instead.

## Stop

- Available vendors below `minVendors` in either review round.
- A **run-level** collapse: no reviewer produced usable output in a round. One
  reviewer going quiet is not a stop — the driver warns, marks it unavailable and
  continues while diversity holds.
- PR pathspec requested.
- A remembered model/wrapper is about to override the manifest.
- A report would call unverified Highs confirmed or silently erase contention.
