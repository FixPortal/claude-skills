---
name: scaffold-ci
description: Use when adding or normalizing GitHub Actions CI/automation for a repo — creating ci.yml or mutation.yml, Dependabot configuration, GitHub security settings, or the house AI-review policy. Covers .NET, Vite/React, and hybrid repos.
---

# scaffold-ci

## Overview

Reconcile a repository with the house CI standard; do not overwrite working automation blindly. Before non-trivial CI or deploy work, read `~/.agents/notes/deploy-and-ci-traps.md`.

## Quick reference

Read only the references needed for the requested surface, then follow their contract exactly:

| Work | Reference |
|---|---|
| `ci.yml`, runners, deploy/publish jobs, CI Gate | [CI workflow](references/ci-workflow.md) |
| Stryker.NET and `mutation.yml` | [Mutation](references/mutation.md) |
| Dependabot, GitHub security settings, and secret scanning | [Dependencies and security](references/dependencies-and-security.md) |
| `.gitignore`, review guard, risk tiers, CodeRabbit | [Review policy](references/review-policy.md) |
| Final normalization | [Common mistakes](references/common-mistakes.md) |

Copy and adapt shipped files from `assets/` and `templates/`; do not retype them.

## Procedure

1. Identify the mainline, repo visibility, existing workflows, project roots, package scripts, deploy jobs, test projects, and local tool manifests.
2. Classify the repo as backend, frontend, or hybrid. Reconcile existing automation and preserve repo-specific deployment behavior.
3. Apply the relevant references. The ten control surfaces are `ci.yml`, `mutation.yml`, Dependabot, Stryker support files, GitHub security settings, Dependabot security settings, AI-review policy, `.gitignore`, `review-policy-guard.yml`, and secret scanning.
4. Actionlint is the first validation step after checkout in substantive build, test, publish, mutation, and deploy jobs. Zero-authority gate-control jobs such as `gate-coverage` and `ci-gate` are exempt; `ci-gate` deliberately has no checkout or network.
5. Keep Stryker outside per-commit CI: every mutation workflow has manual dispatch plus one staggered weekly UTC schedule.
6. Enforce the PR cost envelope: 30 seconds per test, 10 minutes per substantive required job, and a 15 aggregate runner-minute target. Route extended coverage to weekly/manual jobs capped at 45 minutes.
7. Do not mutate GitHub settings or create secrets without the user's approval. Paid Code Quality remains disabled unless current charges and exact repository scope were explicitly approved.

## Load-bearing checks

- No-deploy workflows cancel superseded branch runs but not main or tags; deploy workflows use `cancel-in-progress: false`.
- Backend CI is npm-free. Restore local tools and run `dotnet csharpier check .` before restore/build/test.
- End-to-end, stress/load/soak, repeated concurrency, slow packaging, and compatibility matrices never run in the required PR lane.
- `CI Gate` has `if: always()`, zero permissions, and needs every quality job. `Gate coverage` runs the shipped pure-stdlib Python asset; it has no PyYAML dependency.
- `review-policy-guard.yml` verifies the policy is tracked and uses `git check-ignore --no-index`.
- Secret gates pin the gitleaks install; sweeps use the reviewed TruffleHog detector allowlist.
- Dependency manifests are not HIGH. Registry, SDK, analyzer, workflow, auth, migration, and review controls are.

## Validation

Parse every changed YAML/JSON file, run actionlint locally when workflows changed, run the shipped tests, and verify `git add --dry-run .claude/review-policy.json`. For approved server-setting changes, verify the effective state afterward. Do not commit or push unless requested.
