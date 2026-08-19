---
name: quality-gate-review
description: 'Use when implementation and validation evidence are complete and the user asks for a merge/release verdict: "quality gate", "gate review", "should this merge", "is this ready to PR", "gate this", or /quality-gate-review. This skill classifies supplied evidence and known gaps; its only new-review exception is the required Ponytail simplicity check.'
---

# Quality Gate Review

Consume evidence, apply the committed policy, and issue `PASS`, `PASS WITH CONDITIONS`, or `FAIL`. Do not redo adversarial review or search the diff for additional defects.

## Required inputs

- Diff and changed files; PR/commit summary; current HEAD and author.
- Build, test, coverage, analysis, and relevant runtime results.
- Existing adversarial-review report, or an explicit absence.
- Repository standards and the relevant canonical traps note.
- Base-ref `.claude/review-policy.json` classifier result and current-HEAD reviewer/thread evidence.
- Composition review output from `composition-review`, or an explicit absence with reason. `N/A — no stateful or messaging path touched` is a permitted value here and is not a coverage gap.

Missing evidence is a named gap, never an implicit pass.

## Gate procedure

1. Classify supplied evidence across all eight domains in [the gate contract](references/gate-contract.md). Use `N/A — reason` where appropriate.
2. Apply the committed base-ref review policy mechanically; never self-classify or override it. No policy means `NORMAL`; unreadable policy or changed-file evidence means `UNCLASSIFIED` and `FAIL`.

   | Review Tier | Required current-HEAD evidence |
   |---|---|
   | `HIGH` | Gitar and CodeRabbit clean; no unresolved threads |
   | `NORMAL` | Gitar clean; CodeRabbit not requested; no unresolved Gitar threads |
   | `LOW` | AI review optional; any review that ran has no unresolved threads |

   Only dependency-bump PRs authored by `dependabot[bot]` or `renovate[bot]` are exempt from both AI reviewers, not from CI; control/config changes are not exempt. At any tier, a reviewer that ran must have no unresolved threads, and an explicit negative verdict blocks regardless of whether that reviewer was required. A missing, stale, skipped, rate-limited, or verdict-less required review is a **coverage gap** and blocks `PASS`.
3. Consume `adversarial-review` output using its owned contract: Phase 3 severity plus `[unanimous]`, `[majority]`, or `[contested]`; preserve any `mechanism refuted` re-rating. Record optional Phase 4 `CONFIRMED` / `REFUTED` / `INDETERMINATE` separately. There is no Dismissed bucket.
4. Delegate GitHub finding-versus-ledger disposition mechanics to `ai-findings-ledger`; do not duplicate them here.
5. Run `ponytail:ponytail-review`. `Lean already. Ship.` is clear. Otherwise preserve every finding and `net: -<N> lines possible.`; any reported finding **blocks PASS** until fixed or explicitly accepted by the user. If the plugin is unavailable, perform and label a manual simplicity check.
6. Consume `composition-review` output: five questions, each answered `finding`, `clear`, or `N/A`. Any composition finding **blocks PASS** until fixed or explicitly accepted by the user. An unanswered question, or a question answered without a mechanism, is a **coverage gap** and blocks PASS in the same way — an absence of analysis is not an all-clear. Where the input is `N/A — no stateful or messaging path touched`, there are no questions to answer and no gap.
7. Apply the verdict rules and output template in [the gate contract](references/gate-contract.md). Conditions must be specific and verifiable.

Never override the AR judge, infer clean reviewer silence, or issue `PASS` with an unclassified tier or required coverage gap.
