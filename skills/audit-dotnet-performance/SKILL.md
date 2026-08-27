---
name: audit-dotnet-performance
description: Use when measuring, profiling, costing, or planning performance work for a .NET repository without changing product code.
---

# Audit .NET Performance

Read-only audit: establish evidence and publish unresolved findings; remediation belongs to `remediate-dotnet-performance`.

## Scope and authority

Fully support libraries, ASP.NET Core services, workers, and CLI applications. Treat desktop/mobile projects and .NET Framework as survey or existing-benchmark support only.

Use either repository mode (inspect a target repository) or supplied-production-artifact mode (interpret only artifacts the user supplied). Production evidence is supplied-artifact-only: this audit never attaches to or collects diagnostics from live production, regardless of approval. Process dumps and GC dumps are outside v1, including controlled non-production processes. Never mutate the target repository: no edits, branches, commits, pushes, pull requests, deployments, configuration changes, resets, stashes, or cleanup.

An ephemeral harness or pinned diagnostic-tool install needs explicit approval immediately before it is created or installed. Use a newly created isolated temporary directory outside the target repository; never install globally or add a repository-local tool manifest. Keep raw artifacts outside that repository too, unless it already owns that benchmark-artifact convention.

## Audit flow

1. In repository mode, capture the repository root (`git rev-parse --show-toplevel`), HEAD (`git rev-parse HEAD`), branch (`git branch --show-current`), and exact `git status --short --branch --untracked-files=all` bytes before work; run `scripts/inventory-dotnet-performance.ps1 -RepositoryPath` before choosing measurement depth. Do not build, run, or install during inventory. If `projectInventoryComplete` is false, treat its stopping condition as `Incomplete` and stop before workload selection.
2. Choose a representative workload: prefer an existing benchmark, first checking its design; then an existing test or executable workload. In artifact mode, first establish provenance and whether the supplied artifacts can be interpreted safely. Without repository path and identity, analysis is contextual only and stops before a remediation manifest; actionable publication requires repository identity and preservation proof. Read [workload and measurement](references/workload-and-measurement.md) when selecting a workload or measuring it.
3. Obtain the approval above before any external harness or pinned temporary tool. Establish correctness and a baseline, then measure and attribute. Static best-practice observations are explicitly unmeasured hypotheses until linked to a workload and measurement plan; they are not optimisation recommendations.
4. For every measurable candidate, read [costing](references/costing.md) and report performance delta, measurement cost, engineering/operational cost, and commercial impact. Cost only supported evidence; currency remains unknown unless every required input was supplied.
5. Prepare classifications and draft report/manifest content using [the evidence contract](references/evidence-contract.md), including negative, neutral, and missing evidence; production evidence uses its exact `Production-correlated` classification. Recapture the same root, HEAD, branch, and exact status command, then byte-compare all four captures. Any tracked or meaningful untracked change makes the audit `Incomplete`: stop, preserve evidence, and never clean up the target. Only with identical preservation proof, read [the report contract](references/report-contract.md), validate, and atomically publish immutable external report and manifest files.

Stop and report rather than infer or continue when the build fails, the benchmark is unstable, no representative workload is safe, attribution is missing for a claimed bottleneck, supplied production artifacts cannot be safely interpreted, or the target tree changed. An audit only publishes or proposes experiments; hand implementation to `remediate-dotnet-performance`. Do not enter a target worktree or change product code or configuration during this audit, even with separate approval. Do not automatically commit, open a PR, deploy, or add a CI gate.
