---
name: scaffold-ci
description: Use when adding or normalizing GitHub Actions CI/automation for a repo — creating .github/workflows/ci.yml or mutation.yml, a .github/dependabot.yml, enabling CodeQL, or aligning a repo with the house CI standard. Covers .NET backends, Vite/React frontends, and hybrid single-app repos.
---

# scaffold-ci

## Overview

Scaffolds the house GitHub Actions CI/automation standard onto a repo, adapting to its
shape (backend-only, frontend-only, or hybrid single-app). Sibling of `scaffold-dotnet`,
`scaffold-frontend`, `scaffold-tests`.

**Core principle: match the house standard, do not improvise.** A competent agent left
unaided produces *plausible* CI that diverges in the load-bearing places — cancelling
concurrency, stale action pins, missing actionlint, a different mutation config. The value
here is the exact house deltas, not generic best practice. Don't pad the scaffold with
non-standard extras (see "Not house standard" below).

**Before non-trivial CI/deploy changes, read `~/.claude/notes/deploy-and-ci-traps.md`** —
it catalogues the GitHub Actions / ACA / CodeQL gotchas (concurrency-cancel semantics,
CodeQL default-setup scope, stale action pins) that this scaffold's deltas exist to avoid.

## The five artifacts

| Artifact | What | When it applies |
|----------|------|-----------------|
| `.github/workflows/ci.yml` | build + test + lint per stack | always |
| `.github/workflows/mutation.yml` | Stryker.NET mutation testing | any repo with a .NET test project |
| `.github/dependabot.yml` | weekly grouped dependency PRs | always |
| `.config/dotnet-tools.json` + `stryker-config.json` + `scripts/summarize-stryker.ps1` | Stryker support files | with `mutation.yml` |
| CodeQL **default setup** | code scanning | always — a Security-tab toggle, **NOT a committed workflow file** |

Adapt the project/path/solution names to the target repo. Confirm the mainline branch
(`git symbolic-ref refs/remotes/origin/HEAD`) — it is not always `main`.

**Greenfield vs normalize.** If the repo already has workflows, reconcile against them
(rename/align, don't blind-overwrite) rather than scaffolding fresh. Before wiring frontend
steps, confirm the UI's `package.json` actually defines `lint` / `test` / `build` scripts;
before choosing a Stryker `test-runner`, note that a `test-case-filter` will not work under
`mtp` — scoping comes from the working directory instead (see below).

## Non-negotiable house rules for `ci.yml`

These are the deltas an unaided agent gets wrong. Get them right:

1. **Concurrency depends on whether the repo deploys.**
   - **Repo WITH a deploy job:** `cancel-in-progress: false`, always. A second push while a
     deploy is mid-flight must NOT kill the deploy — the house accepts redundant runs to
     protect deploy integrity.
   - **Library / tool / no-deploy repo:** there is nothing to protect, so a superseded
     feature-branch run is just wasted minutes. Use `cancel-in-progress: ${{ github.ref !=
     'refs/heads/main' }}` — cancel redundant branch runs, never cancel on `main` or tags.
     (Reviewers flagged a flat `false` here across the library repos in the sweep; matching
     the concurrency policy to the repo's actual risk is the fix.)
2. **Triggers:** `push` to `['**']` (all branches) + tags `v*`, `pull_request` to mainline,
   and a bare `workflow_dispatch:`. Not just `push: [main]`. Add an `environment` choice
   input to `workflow_dispatch` **only when the repo has a real deploy job** that reads
   `${{ inputs.environment }}` — otherwise the dropdown is dead and misleads a manual trigger
   (a footgun that recurred across library repos in the sweep). See the Deploy section.
3. **actionlint is the first validation step of every job**, immediately after
   `actions/checkout` (`raven-actions/actionlint`, SHA-pinned, `shellcheck: true`) — it
   needs the repo on disk, so it cannot precede checkout.
4. **Current action pins** (see table). An unaided agent defaults to stale `@v4`.
5. **Backend job is npm-free.** The frontend build runs only on `dotnet publish`
   (gated by an MSBuild target), so ordinary `build`/`test` never invokes npm. Do NOT add
   Node setup or a publish step to the backend CI job. The frontend has its own job.
6. **C# formatting is a separate, read-only gate.** In every .NET backend job, restore
   repository-local tools and run `dotnet csharpier check .` immediately after .NET setup,
   before NuGet restore/build/test. CSharpier is pinned by `scaffold-dotnet`; merge its
   entry into an existing tool manifest rather than replacing Stryker. CI checks only—it
   never runs `format`. Publish/deploy jobs depend on the backend gate and do not repeat it.

### Pinned action versions (current house standard)

| Action | Pin |
|--------|-----|
| `actions/checkout` | `v7` |
| `actions/setup-dotnet` | `v6` |
| `actions/setup-node` | `v7` |
| `actions/upload-artifact` | `v7` |
| `raven-actions/actionlint` | `3d39aea434753780c3b3d4a1a31c854b4dbf49d7` (`v2`) |

.NET: `10.0.x`. Node: `24`.

**First-party `actions/*` take the major tag; third-party actions take a full commit
SHA.** `raven-actions/actionlint` is third-party, so pin the SHA with a trailing `# v2`
comment — a floating tag there trips the semgrep
`third-party-action-not-pinned-to-commit-sha` rule that runs as a local edit hook, so a
tag-pinned scaffold gets flagged the moment it is written. Re-resolve the SHA before
scaffolding rather than trusting this table (`gh api repos/raven-actions/actionlint/git/ref/tags/v2
--jq '.object.sha'`); dependabot bumps it in-repo and this doc lags.

That SHA pins the **action**, not the **actionlint binary** it downloads. Those are
separate knobs: the action's `version:` input is actionlint's own semver and defaults to
`latest`, so a SHA-pinned action still fetches a floating linter. The house default is to
omit `version:` and accept that — a new actionlint release surfacing a new lint is
usually what you want from a linter. Set an explicit semver only where a reproducible
binary matters more than current rules.

### `ci.yml` skeleton (hybrid; drop the job you don't need)

```yaml
name: CI

on:
  push:
    branches: ['**']
    tags: ['v*']
  pull_request:
    branches: [main]          # <- mainline branch of THIS repo
  # Bare manual trigger. Add an `environment` choice input ONLY if this repo has a
  # deploy job that reads ${{ inputs.environment }} (see the Deploy section); a
  # dropdown no step consumes is a dead footgun.
  workflow_dispatch:

# Concurrency: this no-deploy skeleton cancels superseded branch runs but never
# cancels main/tags. A repo WITH a deploy job must instead pin `cancel-in-progress:
# false` to protect mid-flight deploys (see house rule 1).
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
  backend:
    name: Backend (.NET)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: Lint workflows (actionlint)
        uses: raven-actions/actionlint@3d39aea434753780c3b3d4a1a31c854b4dbf49d7 # v2
        with:
          shellcheck: true
      - name: Set up .NET
        uses: actions/setup-dotnet@v6
        with:
          dotnet-version: '10.0.x'
      - name: Restore local tools
        run: dotnet tool restore
      - name: Check C# formatting
        run: dotnet csharpier check .
      - name: Restore
        run: dotnet restore YourSolution.sln
      - name: Build
        run: dotnet build YourSolution.sln --configuration Release --no-restore
      - name: Test
        run: dotnet test YourSolution.sln --configuration Release --no-build --logger "trx;LogFileName=test-results.trx" --results-directory ./TestResults
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: test-results
          path: ./TestResults/*.trx
          if-no-files-found: ignore

  frontend:
    name: Frontend (UI)
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: src/your-ui   # <- the UI subfolder, if not repo root
    steps:
      - uses: actions/checkout@v7
      - name: Lint workflows (actionlint)
        uses: raven-actions/actionlint@3d39aea434753780c3b3d4a1a31c854b4dbf49d7 # v2
        with:
          shellcheck: true
      - name: Set up Node.js
        uses: actions/setup-node@v7
        with:
          node-version: '24'
          cache: 'npm'
          cache-dependency-path: src/your-ui/package-lock.json
      - name: Install
        run: npm ci
      # - name: Generate types        # only if a generate:*-types script exists
      #   run: npm run generate:rest-types
      - name: Lint
        run: npm run lint
      - name: Test
        run: npm run test
      - name: Build (typecheck + bundle)
        run: npm run build
```

**Has a deploy target?** This skeleton is the no-deploy default (bare `workflow_dispatch:`,
ref-gated `cancel-in-progress`). When a real deploy target lands: add the `environment`
choice input to `workflow_dispatch` (see Deploy section), wire deploy jobs that read
`${{ inputs.environment }}`, and switch `cancel-in-progress` to a flat `false` to protect
mid-flight deploys. Never list environments that no step consumes.

**Conditional backend extras** — add only where the repo actually has them: Bicep lint
(`az bicep build`), an EF idempotent-migration generate + apply-to-fresh-DB precondition
(needs a `sqlserver` service container), and contract-snapshot artifact uploads. Don't add
empty placeholders.

### Deploy (optional, documented pattern — not boilerplate)

Where a repo has a deploy target, add the `environment` choice input back to
`workflow_dispatch` (the skeleton omits it) so a manual deploy can pick a target:

```yaml
  workflow_dispatch:
    inputs:
      environment:
        description: 'Which environment to manually deploy to'
        type: choice
        required: true
        default: <repo-dev-env>
        options:
          - <repo-dev-env>
          - <repo-prod-env>
```

and switch `cancel-in-progress` to a flat `false` (house rule 1). Then `ci.yml` calls a
reusable `_deploy.yml` / `_deploy-ui.yml`
via `uses: ./.github/workflows/_deploy.yml` with `secrets: inherit` and
`permissions: { id-token: write, contents: read }`. Deploy jobs are **ref-gated**:
`workflow_dispatch` is `main`-only (the env-scoped OIDC federated cred is branch-agnostic at
the token layer, so without a ref check anyone could deploy a feature branch), and tag
pushes (`refs/tags/v*`) fire prod. The infra/targets are repo-specific — point at this
pattern, don't fabricate Bicep or environments that don't exist.

### Job naming — CI dashboard lane contract

The house CI dashboard sorts workflow **jobs** into board lanes — **Deploys**
and **Packages** — by a case-insensitive substring match on the **job `name:`**.
Names that break this contract mis-lane (a deploy rendered as a package) or
vanish from the board entirely (a job whose name matches no pattern, e.g.
`build-and-push` → neither lane). Always set an explicit job `name:` — never rely
on the job id — and follow:

- **Deploy job** → `Deploy (<target>)` — e.g. `Deploy (production)`,
  `Deploy (staging-ui)`, `Deploy (Azure Container Apps)`. Must contain `deploy`;
  `<target>` must NOT contain a package term (below).
- **Publish/package job** → `Publish <Artifact> (<location>)` — e.g.
  `Publish Image (GHCR)`, `Publish Image (ACR)`, `Publish Package (NuGet)`,
  `Publish Package (npm)`. Must contain a package term; must NOT contain `deploy`.
- **One job = one lane.** A job that builds/pushes an image **and** deploys must
  be **split** into a `Publish Image (...)` job and a `Deploy (...)` job — a
  single job cannot carry both lane identities, and naming it for one silently
  drops the other from the board.

The runtime half of this contract is `JobLanes` in the dashboard's
`appsettings.json`:
- deploys patterns: `["deploy"]`
- packages patterns: `["publish","package","docker","image","release","ghcr"]`

Keep job names matching these. If you change a lane or pattern there, update this
section so scaffold and classifier stay in sync.

## `mutation.yml` (Stryker.NET) — a SEPARATE workflow

Not part of `ci.yml`. Mutation score is informational, but execution and report failures
are real failures. Use `break: 0`; never use job- or step-level `continue-on-error` to
hide restore failures, tool crashes, invalid baselines, or missing reports.

### Measured cadence policy

1. A new, repaired, or materially changed mutation workflow starts **manual-only**.
2. Collect three-to-five valid runs that execute Stryker and produce the report.
3. At or below 10 minutes: enable change-driven execution. Prefer a path-filtered PR
   trigger or proven diff mode such as `--since`; otherwise use push-to-main.
4. Above 10 minutes: retain manual dispatch and add a staggered nightly UTC schedule.
   Choose an estate-specific slot rather than copying a cron value from another repo.
5. Reassess using the latest three-to-five valid runs after scope or tool changes. Do not
   blend fast failed/skipped history into the runtime.

The manual-only skeleton below is the safe starting point. Add the measured trigger after
the first valid sample. Use per-ref concurrency to cancel a superseded manual/scheduled run.

```yaml
name: mutation

on:
  workflow_dispatch:

concurrency:
  group: mutation-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  stryker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: actions/setup-dotnet@v6
        with:
          dotnet-version: 10.0.x
      - name: Restore solution
        run: dotnet restore YourSolution.sln
      - name: Restore local tools
        run: dotnet tool restore
      # working-directory is load-bearing: from the repo root Stryker runs EVERY test project
      # that references the project under test. See "Keeping slow tests out of the mutation
      # lane" below. StrykerOutput lands beside the test project, hence the paths that follow.
      - name: Run Stryker
        working-directory: tests/Your.Project.Tests
        run: dotnet stryker --config-file ../../stryker-config.json
      - name: Summarize mutation report
        if: always()
        shell: pwsh
        run: |
          $latest = Get-ChildItem tests/Your.Project.Tests/StrykerOutput -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
          if (-not $latest) { throw "No StrykerOutput directory found." }
          $report = Join-Path $latest.FullName 'reports/mutation-report.json'
          $jsonSummary = Join-Path $latest.FullName 'reports/mutation-summary.json'
          $mdSummary = Join-Path $latest.FullName 'reports/mutation-summary.md'
          .\scripts\summarize-stryker.ps1 -ReportPath $report -JsonOutputPath $jsonSummary -MarkdownOutputPath $mdSummary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append
      - name: Upload mutation summary
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: mutation-summary
          path: tests/Your.Project.Tests/StrykerOutput/**/reports/mutation-summary.*
      - name: Upload mutation report
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: mutation-report
          path: tests/Your.Project.Tests/StrykerOutput/**
          if-no-files-found: error
```

**Support files** (copy from `templates/`, then adapt names):
- `.config/dotnet-tools.json` — pins `dotnet-stryker` and CSharpier with
  `rollForward: false`. If a manifest already exists, merge missing tools into it rather
  than overwriting. `scaffold-dotnet` owns the CSharpier version and repository config;
  this skill consumes it for CI.
- `stryker-config.json` (repo root) — house defaults: `test-runner: mtp`,
  `mutation-level: Standard`, `concurrency: 4`, `coverage-analysis: perTest` (Stryker's own
  default), `thresholds: { high: 80, low: 70, break: 0 }` (break 0 = never fail the run).
  Set `project` to the project under test. Deliberately **no** `solution`, **no**
  `test-projects` and **no** `test-case-filter` — see the section below; scoping comes from
  the working directory, not from those keys.
  `coverage-analysis: perTest` is right *once the lane is unit-only*, and actively harmful
  before that: it runs the tests that COVER each mutant, so with integration tests in the
  lane it selects exactly the expensive ones. Measured on one API repo: ~39s per mutant with
  a mixed lane, ~0.4s with a unit-only lane. Fix the lane, then this setting does what it is
  meant to.
- `scripts/summarize-stryker.ps1` — shipped verbatim; renders the run into a step summary.

### Keeping slow tests out of the mutation lane: structure, not filters

**Do not rely on `test-case-filter`, and do not rely on `test-projects`.** Neither does what
it appears to. The house pattern is: a unit-only test project, and Stryker invoked from that
project's directory (see the `working-directory` line in the skeleton above). `StrykerOutput/`
then lands beside the test project — update the summary step, both artifact paths, and
`.gitignore` accordingly.

Two mechanisms fail silently here, and each cost about a week:

**`test-projects` does not restrict execution.** From the repository root, Stryker discovers
every test project referencing the project under test and runs all of them against every
mutant, whatever the config says. Only the working directory scopes it. Measured on one repo:
246 tests vs 133 on the same config; >55 min vs ~40 seconds.

**`test-case-filter` is silently ignored under `test-runner: mtp`.** In Stryker's own source
(4.16.0), `TestCaseFilter` appears only under `src/Stryker.TestRunner.VsTest/**`; the MTP
runner project, `src/Stryker.TestRunner.MicrosoftTestPlatform/`, has no reference to it.
Stryker emits no warning — the config parses, the run proceeds, and the filter does nothing.
A repo sits at an acceptable runtime for months, then one feature adds a dozen
`WebApplicationFactory` tests and the nightly falls off a cliff — and the symptom points at
mutant count, not at a setting that never worked.

**Do not "fix" this by switching to `vstest`.** It honours the filter and produces **invalid
results**: against xunit.v3 built as an MTP executable, Stryker's VSTest runner executes tests
but never attributes a failure to a mutant. Measured: **0 of 19** mutants killed on a class
with dedicated unit tests, and on a larger set `Killed: 0, Survived: 224, Timeout: 194` with a
plausible "46.41%" score that was purely timeouts (Stryker scores a timeout as a kill).
Coverage capture fails under the same runner. **Always sanity-check `Killed:` is non-zero on
code you know is tested** — a config that runs fast and prints a number is not the same as one
that works.

**How to check a repo in one line.** Stryker's initial test run prints the count it will use:

```text
[INF] Number of tests found: 133 for project .../Your.Project.csproj. Initial test run started.
```

Compare it against `dotnet test --filter "Category!=Integration"`. Equal means the scoping
works; the full-suite number means it does not. Check this first whenever a mutation run's
runtime jumps.

**And consider whether the whole project should be mutated at all.** Mutating everything is
the default, not a decision. A surviving mutant in DI wiring, a read-only endpoint or a
string builder does not change an engineering decision; one in currency conversion,
idempotency keys or an auth filter does. Scoping `mutate` to those surfaces took one repo
from 1529 mutants (>55 min, timing out) to 418 (~20 min) while making the score mean more,
not less. Expect the score to *drop* when you do this — uncovered scoped mutants report
`NoCoverage` — and read that as information about the unit suite, not as a regression.

**`mtp` prerequisite:** `test-runner: mtp` (Microsoft.Testing.Platform) requires the test
project to build as an MTP executable. For **xunit.v3** the house mechanism is
**`<OutputType>Exe</OutputType>`** AND
**`<UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>`** in the test
`.csproj` — `OutputType=Exe` alone only enables Test-Explorer integration; the MTP
command-line runner/host that `dotnet test`/CI actually invokes needs the
`UseMicrosoftTestingPlatformRunner` property too (see `scaffold-tests`, corrected 2026-07-18,
M-6 adversarial drift review). Keep `Microsoft.NET.Test.Sdk` +
`xunit.runner.visualstudio` alongside it so `dotnet test` (VSTest) still drives CI — the two
runners coexist. Confirm before defaulting to `mtp`: if the test project has neither
property (i.e. it runs purely as a VSTest library), either add both or fall back to
`test-runner: vstest`.

## `dependabot.yml`

Canonical = the richer house variant: weekly, Monday 06:00 Europe/London, PR limits, commit
prefixes (`chore` for deps, `ci` for actions, `include: scope`), and fine-grained nuget
groups. Include the ecosystems the repo actually uses.

```yaml
version: 2

updates:
  - package-ecosystem: nuget
    directory: /
    schedule:
      interval: weekly
      day: monday
      time: "06:00"
      timezone: Europe/London
    open-pull-requests-limit: 10
    commit-message:
      prefix: chore
      include: scope
    groups:
      microsoft-extensions:
        patterns: ["Microsoft.Extensions.*"]
      aspnetcore:
        patterns: ["Microsoft.AspNetCore.*"]
      ef-core:
        patterns: ["Microsoft.EntityFrameworkCore", "Microsoft.EntityFrameworkCore.*"]
      xunit:
        patterns: ["xunit", "xunit.*", "xunit.v3", "xunit.v3.*"]
      testing:
        patterns: ["NSubstitute", "NSubstitute.*", "AwesomeAssertions", "AwesomeAssertions.*", "Microsoft.NET.Test.Sdk", "coverlet.*"]
      nodatime:
        patterns: ["NodaTime", "NodaTime.*"]
      serilog:
        patterns: ["Serilog", "Serilog.*"]
      azure-sdk:
        patterns: ["Azure.*", "Microsoft.Azure.*"]

  # npm: only if the repo has a frontend. The directory MUST point at the
  # folder containing package.json (often a subfolder, NOT repo root).
  - package-ecosystem: npm
    directory: /src/your-ui
    schedule:
      interval: weekly
      day: monday
      time: "06:00"
      timezone: Europe/London
    open-pull-requests-limit: 10
    commit-message:
      prefix: chore
      include: scope
    groups:
      npm-minor-and-patch:
        update-types: [minor, patch]

  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
      day: monday
      time: "06:00"
      timezone: Europe/London
    open-pull-requests-limit: 5
    commit-message:
      prefix: ci
      include: scope
    groups:
      actions:
        patterns: ["*"]
```

Keep the full nuget group set even if some families (serilog, nodatime, azure-sdk…) aren't
yet dependencies — Dependabot ignores empty groups, and the file won't need editing when
those packages appear later.

Lighter fallback (simulator repos): a single grouped `nuget-minor-and-patch` /
`npm-minor-and-patch` group + `github-actions`, weekly, no time/limit/prefix detail. Use the
richer variant by default.

## CodeQL — default setup, not a file

The house standard is GitHub **default setup** (Security tab → Code scanning → CodeQL →
Default setup), enabled per repo or org. It is a settings toggle, **not** a committed
workflow. Do NOT scaffold a `codeql.yml` / `github/codeql-action` advanced-setup workflow —
that diverges from house practice and double-scans.

Enable it headless:

```
gh api -X PATCH /repos/{owner}/{repo}/code-scanning/default-setup -f state=configured
```

Default setup auto-detects languages (C#, JS/TS for a hybrid repo). Surface this as a
required step and confirm it's enabled — don't silently skip it because there's no file.

**Not available on a private repo without GitHub Code Security (ex-GHAS).** The PATCH
above then returns `403 "Code scanning is not enabled for this repository"`, which reads
like a scope problem. It is often the licence gate — but work the causes below before
concluding that, because missing admin and org policy return the same 403.

Separate the causes before concluding anything, cheapest first:

1. **Admin on the target?** `gh api repos/{owner}/{repo} --jq .permissions` — the PATCH
   needs write/admin. Rule this out first; it is the one cause a token swap *can* fix.
2. **Credential able to read code-scanning at all?** Run the same token against a
   **public** repo. Any HTTP 200 is a pass — the endpoint answered, so the credential
   reaches code-scanning. Do not require `state: configured`: that reports whether *that*
   repo has CodeQL on, which is a different question, and a `not-configured` 200 clears
   the check just as well. A pass shows the credential works *on that repo* — it does NOT
   prove access to the private target, which is why step 1 comes first.
3. **Policy, if the repo is org-owned.** An org or enterprise policy can disable Code
   Security and yields the same 403 — a licensed org still 403s when policy forbids it.
   Check the org's code-security configuration before concluding the licence is missing.
   Not applicable to a personal-account repo, which has no such policy layer.
4. **Licence gate.** Admin confirmed, public read clean, policy permissive (or no org) and
   the private repo still 403s → the gate. Only here is it true that no
   `gh auth refresh -s security_events` or PAT swap will move it. Saying that earlier
   talks you out of step 1 — the one cause a credential change actually fixes.

**A personal account cannot buy its way out.** GitHub Code Security is sold only against a
**Team or Enterprise organization** plan; personal accounts (Free or Pro) cannot purchase
a licence at all. So on a private personal-account repo the routes are making the repo
public, or **transferring it to an eligible org** — not paying as-is. Record CodeQL as
blocked rather than burning a session on the credential.
*(Seen on two private .NET+React repos under a personal account — admin confirmed, public
control read clean, no org policy layer, so genuinely the gate and un-enableable where
they sat.)*

### Gating & triage policy (house standard)

Enabling the scan is half the job; the other half is deciding what blocks merge and how
alerts get triaged. Apply this per repo:

- **Make the CodeQL check required, but gate only on error + high/critical severity.**
  Repo → Settings → Code security → "Protection rules" / "Check failures": set the
  PR-blocking threshold to **high or higher**. Medium/low stay advisory (visible, not
  blocking). Gating *every* severity on day one just trains rubber-stamp dismissals.
- **Every alert gets a decision before merge:** fix it (push to the same branch — the alert
  auto-resolves when the dataflow path is gone), or **dismiss with a reason**
  (false positive / used in tests / won't fix) and a one-line justification. A dismissal
  with no rationale is worthless to future-you.
- **Prefer dashboard dismissal over inline `// codeql[rule-id]` suppression.** Reserve inline
  suppression for structural false positives that will recur.
- **Don't merge with "fix it later" intentions** — once merged, the alert detaches from PR
  context and rots in the backlog. Triage at PR time.

### Reading alert state needs the `security_events` scope

The default `gh auth login` token (`repo, workflow, read:org, gist`) **cannot read the
Code Scanning API** — `gh api .../code-scanning/alerts` 403s and the repo looks like CodeQL
is *disabled* even when it's scanning fine (see `deploy-and-ci-traps.md`). To list/triage
alerts from the CLI, the user must add the scope:

```
gh auth refresh -h github.com -s security_events
```

Hand this to the user to run (it's an interactive browser flow). Verify CodeQL is actually
*on* via the Actions API instead (`workflow` scope suffices):
`gh api repos/{owner}/{repo}/actions/workflows --jq '.workflows[] | {name,path,state}'` —
an active `dynamic/github-code-scanning/codeql` workflow means default setup is enabled.

## Not house standard — do not add unprompted

An unaided agent tends to reach for these. They are NOT part of the house standard; add only
if explicitly asked:
- A committed CodeQL/`codeql-action` workflow (use default setup instead).
- `actions/dependency-review-action` PR gate.
- A separate `tsc --noEmit` step (the `build` script already type-checks via `tsc -b`).
- `--collect:"XPlat Code Coverage"` / coverage gating in `ci.yml`.
- Node setup or a publish-verify step in the backend job.
- An unconditional `cancel-in-progress: true` (it cancels `main`/tags too) — gate it on
  `github.ref != 'refs/heads/main'`, and use flat `false` only on a deploy repo.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Flat `cancel-in-progress: false` on a no-deploy repo | `${{ github.ref != 'refs/heads/main' }}`; flat `false` only when a deploy job needs protecting. |
| `cancel-in-progress: true` unconditionally | Cancels main/tags too. Gate on `github.ref != 'refs/heads/main'`. |
| Dead `workflow_dispatch` `environment` input | Bare `workflow_dispatch:` unless a deploy job reads `${{ inputs.environment }}`. |
| Believing `version:` on `raven-actions/actionlint` is invalid | It is valid — actionlint's own semver, defaulting to `latest`. The action-ref SHA pins the *action*, not the actionlint *binary*. Omit it to take the default, or set an explicit semver if you want the binary reproducible too. |
| `push: [main]` only | `['**']` + tags `v*` + `pull_request` + `workflow_dispatch`. |
| Stale `@v4` pins | checkout@v7, setup-dotnet@v6, setup-node@v7, upload-artifact@v7. |
| Tag-pinning `raven-actions/actionlint` | Third-party — pin the full commit SHA with a `# v2` comment; semgrep's edit hook flags a floating tag. |
| No actionlint step | First validation step of every job, immediately after `actions/checkout`. |
| Node added to backend job | Backend CI is npm-free; frontend build is publish-only. |
| No CSharpier gate, or CI runs `format` | After .NET setup run `dotnet tool restore`, then `dotnet csharpier check .`; never mutate source in CI. |
| Formatting repeated in publish/deploy | Make those jobs depend on the backend gate; check once. |
| Stryker as a `ci.yml` job or an unmeasured per-PR gate | Separate `mutation.yml`; start manual-only, then apply the measured cadence. |
| Job/step `continue-on-error` to keep score informational | Remove it and use `break: 0`; execution/report failures must be red. |
| Missing report only warns | Make the summary throw and set report upload `if-no-files-found: error`. |
| Copying another repo's mutation cron | Stagger nightly UTC slots across the estate. |
| `dotnet stryker` run from the repo root | It then runs EVERY test project referencing the target. Set `working-directory` to the unit test project. |
| `test-runner: mtp` alongside a `test-case-filter` | The filter is silently ignored under MTP. Split the slow tests into a project Stryker does not run, not a filter. Verify with "Number of tests found". |
| Assuming `coverage-analysis: perTest` is faster | It selects the tests that COVER each mutant. Where those are the slow integration tests it is far slower. Measure per repo. |
| Mutating a whole project because it is the default | Scope `mutate` to surfaces where a surviving mutant would change a decision (money, auth, persistence). Wiring and read endpoints buy nothing. |
| Diagnosing a slow mutation run from mutant count alone | Read "Number of tests found" first — tests-per-mutant is the other multiplier, and the one that fails silently. Multiply by a MEASURED per-mutant cost before concluding. |
| npm dependabot `directory: /` | Point at the actual package.json folder. |
| Committing a `codeql.yml` | Enable default setup via the Security tab / `gh api`. |
| PR base `branches: [main]` when mainline differs | Check `git symbolic-ref refs/remotes/origin/HEAD`. |

## After scaffolding

Validate before committing: run actionlint locally if available, or push to a branch and
confirm the run is green. Confirm CodeQL default setup is enabled (it has no file to verify
in-repo). Then commit per the repo's conventions.
