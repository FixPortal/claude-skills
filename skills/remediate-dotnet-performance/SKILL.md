---
name: remediate-dotnet-performance
description: Use when running exactly one explicitly approved, measured remediation experiment for an unresolved .NET performance audit finding.
---

# Remediate .NET Performance

Run one causal experiment only after the user explicitly approves its exact unresolved `PERF-NNN` finding and proposed change. A sweep, urgency, or approval of another finding is not approval. Do not commit, push, open a PR, merge, deploy, or alter a CI gate without separate authority.

Before any target-repository mutation, run `../audit-dotnet-performance/scripts/test-performance-manifest.ps1 -Mode Finding` for the chosen ID. Confirm its repository identity and audited HEAD. If HEAD, dependencies, runtime, configuration, workload, or the attributed mechanism drifted, stop for re-baselining or a fresh audit decision.

Use only `<repo>\.claude\worktrees\performance-experiments` on a branch such as `performance/perf-001-short-slug`. Inspect `git worktree list` and that worktree's status first. If it is occupied or has uncommitted work, stop until that experiment is completed or explicitly abandoned; never create a second performance-experiment worktree.

Read [the experiment runbook](references/experiment-runbook.md) before changing product code. Read [the change-record templates](references/change-record.md) when recording evidence or an accepted result. Keep Git operations explicit and reversible. Run `../audit-dotnet-performance/scripts/test-managed-product-boundary.ps1` on the candidate diff; it must pass before acceptance.

After the candidate's focused correctness checks, A/B workload, and boundary check, run the repository's applicable normal build, test, lint, and analyzer gates. Record every command and result. Any failure makes the result non-accepted; do not waive or weaken a normal gate for performance.

Accepted product code uses only supported public managed APIs and existing approved managed dependencies. Do not accept `unsafe`, runtime intrinsics, native/interop paths, or new native dependencies. When EF Core is involved, invoke `ef-core`. For stateful, concurrent, or messaging paths, invoke `composition-review` before acceptance.
