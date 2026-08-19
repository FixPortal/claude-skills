# Review Sweep Runbook

## Discover and scope

Inspect top-level directories beneath the requested root. Keep roots where
`git -C <dir> rev-parse --is-inside-work-tree` succeeds. Require clean working
trees because uncommitted changes are invisible to an audit diff.

Verify each target is checked out at the approved merged mainline. Scope the
pass to one named subsystem. If a request spans subsystems or includes a whole
never-reviewed repository, stop and show the proposed narrower pass for one
approval.

## Panel pre-flight

Resolve the loaded `adversarial-review` skill directory and read its
`reviewers.json`. For each enabled reviewer:

1. Resolve `wrapper` through the manifest and confirm the sibling file exists.
2. Read the wrapper header and execute its exact `PREFLIGHT_COMMAND:`. Accept
   only its documented `PREFLIGHT_SUCCESS:`.
3. When the primary fails and declares `fallbackWrapper`, pre-flight that
   wrapper identically.
4. Record primary/fallback availability and any metered degradation.

Compute distinct available vendors. Below `minVendors` is a hard stop. Any
other degradation belongs in the approval message.

## Evidence-driven triage

Resolve `review-digest` and run its `collect.ps1` once for the parent path.
Join discovery to collector rows by canonical `resolvedPath`. Git fields are
nested under `.git`: `.git.boundarySha`, `.git.effectiveNeverReviewed`,
`.git.sinceReviewCount`, `.git.sinceReviewFiles`, `.git.sinceReviewIns`,
`.git.sinceReviewDel`, and `.git.daysSinceReview`; `hasTrackedSource` is a
top-level field.

Each discovered repo needs exactly one admissible row: `unresolved` and
`outsideScanPath` false, `vault.isDocumentReview` false, and `resolvedPath`
equal to the repo root. Missing, duplicate, unresolved, outside-scan, or
document-review matches are `UNKNOWN` with a reason and `STOP` before approval.
Vault-only rows never create targets.

`effectiveNeverReviewed` is authoritative. Do not use `.git.neverReviewed` or
recreate git-marker inference: a prose-only git marker is already emitted as
full-history `effectiveNeverReviewed = true` by `review-digest`.

| Evidence | Class | Action |
|---|---|---|
| `hasTrackedSource = false` | skip/void | Record not code-reviewable; do not audit |
| `hasTrackedSource` missing or unknown | UNKNOWN | STOP before approval |
| `hasTrackedSource = true`; `effectiveNeverReviewed = false`; boundary set; zero commits | skip | Record unchanged |
| `hasTrackedSource = true`; `effectiveNeverReviewed = false`; boundary set; later commits | drift | Review `<boundarySha>..HEAD` |
| `hasTrackedSource=true`; `effectiveNeverReviewed=true` | audit | Audit only the approved subsystem pathspec |

`sinceReviewFiles` is a file count, not a list. For drift candidates, run
`git -C <repo> diff --name-only <boundarySha>..HEAD`; docs/assets/brand-only
drift becomes skip. Size the total diff, including deletions and context, so
transport-heavy drift is visible before approval.

## Approval and runbook

In one message show the triage table, the single-subsystem chunk/pathspec plan,
any degradation, and the projected marginal cost of selected metered wrappers.
Read current pricing from the wrapper or linked primary documentation; unknown
rates remain unknown. Subscription-backed wrappers have zero marginal API cost.

After approval, write one durable plan/task item per drift review or audit
target plus consolidation. If the runtime has no durable plan facility, keep
the equivalent conversation checklist. Update it through compaction.

## Execute and consolidate

Invoke `adversarial-review` sequentially:

- drift: `<boundarySha>..HEAD`
- audit: `audit -- <approved subsystem pathspec>`

Let each invocation own chunking, synthesis, and vault persistence. Do not
report per target. At the end provide one row per repository with class,
Critical/High counts, contested findings, and notes. Include skipped repos and
their reasons. Never silently resolve contested findings.
