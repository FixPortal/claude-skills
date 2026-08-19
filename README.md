# Claude Code Skills

[![CI](https://github.com/FixPortal/fixportal-claude-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/FixPortal/fixportal-claude-skills/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/FixPortal/fixportal-claude-skills)](LICENSE)

A curated, sanitised subset of the authored [Claude Code](https://claude.com/claude-code)
skills I use day to day, published as a portfolio reference. These are the
genuinely reusable ones — scaffolding, review, audit, and session workflows —
with machine paths, client names, and personal vault locations replaced by
placeholders.

> These are extracted from a larger private working set. Paths like `~/.claude/...`,
> `<vault>`, `<workdir>`, and example values like `you@example.com` / `Acme` /
> `<your-org>` are placeholders — point them at your own locations before use.

## What's here

### Scaffolding — start a repo, or bring an existing one up to standard

| Skill | What it does |
|---|---|
| `scaffold-dotnet` | Create or normalise a .NET solution to a house standard (NodaTime at the boundaries, central package management, a thin `.editorconfig` with analyzer rules owned by a shared package). |
| `scaffold-tests` | Scaffold xUnit v3 + NSubstitute + AwesomeAssertions test projects, with references on async/timing determinism and CI test budgets. |
| `scaffold-frontend` | Vite + React + TypeScript scaffolding with ESLint (sonarjs), Vitest, and architecture tests. |
| `scaffold-minimal` | Convert ASP.NET controllers to minimal APIs with OpenAPI + Scalar. |
| `scaffold-ci` | GitHub Actions CI for .NET / Vite-React / hybrid repos, plus Dependabot, mutation testing, and the AI-review control plane. |
| `scaffold-doc` | Author structured markdown docs — READMEs, audit reports, ADRs, runbooks — in a consistent house style. |

### Review — find the defects, then remediate them safely

| Skill | What it does |
|---|---|
| `adversarial-review` | Cross-vendor code review as a five-reviewer panel spanning four vendors — two Anthropic models, GPT via the Codex CLI, Kimi via the Kimi Code CLI, and Gemini via Antigravity — which then cross-examine each other before a separate Opus judge adjudicates. The panel is data, not code: `reviewers.json` defines it and the driver enforces a minimum vendor-diversity invariant. |
| `review-sweep` | The same review across every repository under a parent folder, one subsystem at a time. |
| `review-worktree-pass` | Remediate review findings in a dedicated, ephemeral review worktree on a numbered batch branch, so the primary checkout is never disturbed. |
| `review-digest` | Mine *past* review work across a folder of repos into a dated intelligence report — coverage ledger, recurring-theme digest, risk ranking, and a paste-ready scope brief for the next pass. Read-only; runs no reviews. |
| `quality-gate-review` | A merge/release verdict from the evidence already gathered. Classifies what was verified and what is still a gap, rather than re-reviewing. |

### Audit — measure something against a standard, change nothing

| Skill | What it does |
|---|---|
| `audit-ci` | GitHub Actions CI/CD for one repo or a folder sweep, measured against a house standard — gaps, drift, cross-repo inconsistency, and a Docker layer-cache opportunity lens. Advisory; hands fixes to `scaffold-ci`. |
| `audit-tests` | Test quality and adequacy: what the suite actually proves, where the false confidence is, and how a prior audit reconciles against later code changes. |
| `audit-skills` | Audit authored agent skills across Claude Code, Codex, Kimi, and Antigravity for stale references, weak triggers, runtime incompatibility, and cross-home drift. |
| `audit-github-estate` | GitHub quality and security across an org or repository estate — code scanning, Dependabot, secret scanning, Actions evidence, and post-merge verification. |
| `audit-dotnet-estate` | Compare multiple .NET repositories against current house standards: scaffold drift, analyzer and formatter conformance, tests, docs, CI. |
| `audit-dotnet-analyzers` | Inventory the analyzer and code-style configuration actually in force across a solution or estate, and produce a portable remediation prompt. |
| `audit-dependabot-coverage` | Reconcile open advisories against the PRs Dependabot actually raised — the gap between "alerts exist" and "fixes were offered". |
| `azure-cost-sweep` | Reconcile live Azure spend against the code and IaC that require it. Ranked, risk-annotated, and strict about the difference between a saving applied and a saving *realised* — the latter needs committed IaC plus live verification after a deploy. |

### Session — cross a context boundary without losing the thread

| Skill | What it does |
|---|---|
| `recap` | "Where did we get to?" — a fast, multi-source, journalled recap of work done and what's next, per repo/branch. |
| `handoff` | Write the brief that survives the session: what is done, what is in flight, and exactly what the next agent must not re-derive. |

### Domain — depth in the stacks I actually work in

| Skill | What it does |
|---|---|
| `ef-core` | Entity Framework Core design and implementation — entity and `DbContext` shape, query shaping, migrations, value converters. |
| `composition-review` | Defects that only appear when stateful parts compose: restart-replay, idempotency, ordering, and outbox/inbox behaviour in messaging and persistence paths. |

## How skills work

Each folder is a skill: a `SKILL.md` with YAML frontmatter (`name`, `description`)
that Claude Code loads on demand when the description matches the task. Drop a
folder into `~/.claude/skills/` (global) or a repo's `.claude/skills/` (project)
and it becomes available.

Larger skills keep `SKILL.md` short and push detail into `references/`, so the
loaded context stays small until the detail is actually needed.

## A note on the adversarial-review skill

The whole value is that the reviewers come from **different vendors**. A panel
made only of Claude models is same-vendor self-review: its errors correlate, so
the second opinion mostly agrees with the first. Spanning Anthropic, OpenAI,
Moonshot, and Google is what makes one vendor's blind spot another's finding.

Two rules fall out of that and are enforced rather than documented: the active
reviewer set must span a minimum number of distinct vendors, and the judge is
never also a reviewer — an adjudicator that voted earlier is just its own
opinion, counted twice.

## Contributing

PRs only — `main` is protected (rebase-merge, no direct pushes). Keep each
skill self-contained under `skills/<name>/` with `SKILL.md` frontmatter
(`name` matching the folder, `description` ≤ 1024 chars) and no
machine-specific paths — see [AGENTS.md](AGENTS.md) for the full conventions.

CI runs three jobs: skill validation (actionlint over the workflows, then every
`skills/**/test/verify-*.ps1`), gate coverage, and a required `CI Gate`
check. `verify-collect.ps1` is excluded — it is an estate integration skeleton
with intentional `<repos-root>` placeholders that cannot run standalone.

Run the verifiers locally before pushing:

```powershell
Get-ChildItem skills -Recurse -Filter 'verify-*.ps1' |
  Where-Object Name -ne 'verify-collect.ps1' |
  ForEach-Object { & $_.FullName }
$global:LASTEXITCODE = 0
```

That last line is deliberate, and CI does the same. Several negative-path
verifiers run a child process that is *supposed* to fail and assert its exit
code; their own assertions pass, but the native status lingers, so a clean run
otherwise ends on a non-zero `$LASTEXITCODE`.

## Licence

MIT — see [LICENSE](LICENSE).
