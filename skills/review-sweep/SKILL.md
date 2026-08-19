---
name: review-sweep
description: Use when asked for an adversarial or cross-vendor code-review sweep across several Git repositories under one parent folder. For one repository use adversarial-review; for GitHub-estate, ruleset, workflow, or configuration audits use audit-github-estate.
---

# Review Sweep

Orchestrate the installed `adversarial-review` skill across approved targets.
Never substitute host-native reviewers: cross-vendor diversity is the point.
The active `reviewers.json` owns the roster, wrappers, and vendor threshold.

Read [references/runbook.md](references/runbook.md) before starting.

## Quick Reference

| Stage | Gate |
|---|---|
| Discover | Top-level Git repos only; clean, merged mainline |
| Scope | One named subsystem per pass; wider requests stop for approval |
| Pre-flight | Every enabled primary/fallback wrapper; preserve `minVendors` |
| Triage | `skip`, `drift`, `audit`; ambiguous evidence is `UNKNOWN` + STOP |
| Approve | One message: targets, chunks, degradation, metered cost |
| Execute | Sequential `adversarial-review` invocations; no per-repo check-ins |
| Finish | One cross-repo summary; per-repo reports remain in the vault |

## Contract

Resolve and invoke both `adversarial-review` and `review-digest` through the
active runtime. Run the configured wrapper preflights exactly as documented by
`PREFLIGHT_COMMAND:` and `PREFLIGHT_SUCCESS:`; honour `fallbackWrapper` and
`minVendors`. Never name remembered reviewers or models.

Before triage, verify every target is on the approved merged mainline and the
pass covers one named subsystem. Stop for explicit approval if either cannot be
proved or the request is broader.

Use `review-digest`'s `.git.effectiveNeverReviewed` directly:
`hasTrackedSource=false` is skip/void, and unknown source evidence means unknown is STOP.

Present the complete evidence-driven plan once. After approval, record units in
the runtime's durable plan and run them to completion in the agent loop. Reviews
are read-only; remediation worktrees and change-oriented quality gates are out
of scope.

## Stop

- Panel vendor diversity is below `minVendors`.
- A discovered repository lacks exactly one admissible collector row.
- Target state is dirty, not merged mainline, or scope spans subsystems without
  explicit approval.
- Execution would replace `adversarial-review` with same-host workers.
