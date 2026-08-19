# Dependencies and GitHub security contract

Read this reference for Dependabot or repository security-surface work.

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
      # Peer-locked toolchains must move together. This group is deliberately
      # above the minor/patch catch-all because first match wins.
      vite-toolchain:
        patterns: ["vite", "@vitejs/*", "vitest", "@vitest/*"]
        update-types: [major, minor, patch]
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

**Peer-locked toolchains:** when packages constrain each other through peer ranges, give the
family its own group above the minor/patch catch-all and admit `major`. For Vite that family
is `vite`, `@vitejs/*`, `vitest`, and `@vitest/*`; raising them separately can produce PRs
that cannot install.

**Private GitHub Packages:** Dependabot cannot read Actions secrets or NuGet credentials
from `nuget.config`. Add the token separately under *Settings → Secrets → Dependabot*, then
declare and reference the registry:

```powershell
gh secret set YOURORG_PACKAGES_TOKEN --app dependabot
```

```yaml
registries:
  your-github-packages:
    type: nuget-feed
    url: https://nuget.pkg.github.com/YourOrg/index.json
    username: <your-org>
    password: ${{secrets.YOURORG_PACKAGES_TOKEN}}

updates:
  - package-ecosystem: nuget
    directory: /
    registries:
      - your-github-packages
```

**CI restore from the private feed — the step that bites every new repo.** A workflow
restore authenticates with `GITHUB_PACKAGES_TOKEN: ${{ secrets.GITHUB_TOKEN }}` plus
`packages: read` on the job, but that token can read a package owned by a *different* repo
only when the package has explicitly granted the consuming repo access. The grant is
**web-UI only** (no API): package page → *Settings → Manage Actions access* → Add
Repository → the consuming repo, Role: **Read** (Role: **Write** on the package's own repo
when it publishes). Without it the first CI run fails restore with
`NU1301 … 403 (Forbidden)` from `nuget.pkg.github.com`. When scaffolding CI for any repo
that restores `YourOrg.*` packages, grant it on **<YourOrg.CodeStyle>** (every consumer
needs that one) plus any other `YourOrg.*` package it restores, *before* the first push.
See `~/.agents/notes/deploy-and-ci-traps.md` ("Private GitHub Packages NuGet 403").

## GitHub security surfaces — visibility policy

These are server settings, not committed workflows. Apply the same visibility policy as
`audit-github-estate`; resolve organization configurations live by name because IDs are not
durable policy.

| Visibility | Required state |
|---|---|
| Public | Enable free Code Security and CodeQL default setup, secret scanning, and push protection. Keep paid Code Quality disabled unless the user explicitly approves the current charges. |
| Private or internal | Disable paid Code Security and all secret scanning. Do not attach a paid security configuration. Keep paid Code Quality disabled unless the user explicitly approves the current charges. Keep Dependabot alerts and automated security fixes enabled. |

For a public repository, prefer attaching the existing public security configuration over
duplicating settings repository by repository. Configure CodeQL default setup headlessly:

```powershell
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
```

```powershell
gh api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured
```

Before any Code Quality change, inspect the organization's Code Quality **Repository
access** selection, enforcement, and displayed billing impact. A repository-level setup
call is not authorization: do not enable the product until the user explicitly approves
the current charges. The safe default is **No repositories** with **Enforce access** on.
When paid use is approved, use **Selected repositories** containing exactly the approved
repositories, again with **Enforce access** on. Treat `Let repositories decide`, a broader
selection, or enforcement off as drift unless the user explicitly approved that exact
scope. Keep Code Quality disabled by default at every visibility:

```powershell
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
```

```powershell
gh api -X PATCH "repos/$repo/code-quality/setup" -f state=not-configured
```

When that paid use is explicitly approved, enable only the authorized repository, keep
Code Quality AI findings disabled, and create no automatic Copilot review ruleset:

```powershell
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
```

```powershell
gh api -X PATCH "repos/$repo/code-quality/setup" -f state=configured -f ai_findings_option=disabled
```

For a private/internal repository, leave CodeQL unconfigured. Detach any paid security
configuration before disabling the effective repository Code Security setting; an attached
configuration can otherwise override the repository.

Never create a `codeql.yml` advanced-setup workflow merely to bypass the private paid-product
policy. Never create the generated `Code Quality Copilot review for default branch` ruleset.
If normalizing an existing repository, remove that ruleset only after verifying it contains
exactly the single `copilot_code_review` rule.

Verify the organization access control and effective server state after every mutation.
Expected `403`/`404` responses from
private CodeQL or secret-scanning endpoints are not missing evidence: those surfaces are not
applicable by policy and should not be queried. Public repositories must show current,
successful CodeQL default-branch analyses before they are treated as configured.

## Secret scanning in CI

Applies to **private repositories only**. For a public repository, verify the live
`security_and_analysis.secret_scanning_push_protection.status` value is `enabled`; do not
infer it from visibility or policy. Enabled push protection blocks at push time — strictly
earlier than any CI gate — so scaffolding gitleaks then duplicates a control and doubles
the noise for no new coverage. A disabled or unavailable value is drift, not proof of
coverage.

```powershell
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
```

```powershell
gh api "repos/$repo" --jq '.security_and_analysis.secret_scanning_push_protection.status'
```

The visibility policy above disables secret scanning on private repositories as a cost
decision. That leaves those repositories with no secret detection of any kind. This section
is the compensating control.

### Use the release binary, not the action

Scaffold the **gitleaks release binary**. Do **not** use the gitleaks GitHub Action: it
requires a licence key for organizations, and its licence changed from MIT at v2.0.0. The
key is free, but obtaining it means a sign-up form and storing an encrypted organization
secret — creating a credential in order to hunt credentials. The CLI itself remains MIT.

Pin the version and verify the archive against a **reviewed sha256 hardcoded in the
workflow**, never against the release's own checksums file — a replaced release could swap
the archive and its `gitleaks_8.30.1_checksums.txt` together, and the check would still
pass. Bump version and hash in the same edit. Never fetch "latest" at run time.

### The gate

One `secrets` job in `ci.yml`, added to `ci-gate`'s `needs` like every other quality job.
**The gate blocks.** It is never scaffolded as advisory and never "flipped to blocking
later" — an advisory gate becomes permanently decorative.

Scan the pull request's commit range, not full history; history belongs to the sweep.
`--log-opts` is passed through to `git log -p`.

**The checkout must be unshallowed.** `actions/checkout` fetches a shallow clone by
default, which does not contain `base.sha`, so the range cannot be resolved and the scan
errors or silently examines nothing — a gate that passes because it scanned no commits is
worse than no gate. `fetch-depth: 0` is required and is not optional tuning:

```yaml
  secrets:
    name: Secrets
    runs-on: ubuntu-latest
    timeout-minutes: 10
    env:
      GITLEAKS_VERSION: 8.30.1
      # Reviewed sha256 of gitleaks_8.30.1_linux_x64.tar.gz — hardcoded, NOT the
      # release's own checksums file (a replaced release could swap both together).
      GITLEAKS_SHA256: 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
    steps:
      - uses: actions/checkout@v7
        with:
          # Required: base.sha..head.sha cannot resolve in the default shallow clone.
          fetch-depth: 0
          persist-credentials: false

      - name: Lint workflows (actionlint)
        uses: raven-actions/actionlint@3d39aea434753780c3b3d4a1a31c854b4dbf49d7 # v2
        with:
          shellcheck: true

      - name: Install gitleaks
        run: |
          set -euo pipefail
          archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
          curl --fail --silent --show-error --location --remote-name "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${archive}"
          echo "${GITLEAKS_SHA256}  ${archive}" | sha256sum --check --strict
          tar --extract --gzip --file "${archive}" gitleaks
          install -m 0755 gitleaks "$RUNNER_TEMP/gitleaks"

      - name: Scan the PR commit range for secrets
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
          HEAD_SHA: ${{ github.sha }}
        run: |
          set -euo pipefail
          "$RUNNER_TEMP/gitleaks" git -v --redact --log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}" .
```

### Pre-existing findings

Commit a `.gitleaksignore` holding one fingerprint per line for what already exists in the
repository. Generate it once, review it, commit it.

Use `.gitleaksignore` (`-i, --gitleaks-ignore-path`), **not** `--baseline-path`. They are
different mechanisms and not interchangeable: `--baseline-path` takes a JSON report, while
`.gitleaksignore` is one fingerprint per line and therefore diffs in a pull request. The
whole point of a baseline is that a reviewer can see what was accepted and when.

Do not remediate all findings before enabling the gate. That is unbounded work standing
between the repository and any protection at all. The sweep prioritises instead, by
reporting which pre-existing secrets are actually live.

### The sweep

Copy `assets/secret-sweep.yml`. It runs full history through trufflehog with
`--results=verified`, so a finding is a credential that works right now rather than a
string that looks like one. Its reviewed `--include-detectors` allowlist is the complete
default; do not replace it with TruffleHog's unconstrained detector set or an exclusion for
one known-bad detector. Add a provider only after reviewing that detector's matching and
verification behavior.

Triggers are `workflow_dispatch` plus one **staggered weekly UTC schedule**, the same rule
mutation workflows follow: choose a repository-specific weekday and time, and do not copy
one cron value across the estate.

Verification calls the issuing provider's API to test whether each candidate is live. That
is outbound traffic carrying suspected secrets out of a private repository, to the provider
that issued them. It is how verification works at all, and it is an accepted trade-off
rather than an oversight — but say so when scaffolding it, rather than letting a repository
acquire the behaviour silently.

## Dependabot security settings

Enable both repository settings; a correct `dependabot.yml` does not imply either is on:

```powershell
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
```

```powershell
gh api -X PUT "repos/$repo/vulnerability-alerts"
```

```powershell
gh api -X PUT "repos/$repo/automated-security-fixes"
```

Verify `GET repos/{owner}/{repo}/vulnerability-alerts` returns HTTP 204; HTTP 404 means
disabled. Verify `GET repos/{owner}/{repo}/automated-security-fixes` returns HTTP 200 with
`enabled: true` and `paused: false`; HTTP 404, `enabled: false`, or `paused: true` is
non-compliant. Record an explicit exception when a repository has no dependency ecosystem
rather than silently skipping the check.

### Public CodeQL gating and triage policy

Enabling the scan is half the job; the other half is deciding what blocks merge and how
alerts get triaged. Apply this only where CodeQL is enabled by the visibility policy:

- **Make the CodeQL check required, but gate only on error + high/critical severity.**
  Repo → Settings → Code security → "Protection rules" / "Check failures": set the
  PR-blocking threshold to **high or higher**. Medium/low stay advisory (visible, not
  blocking). Gating *every* severity on day one just trains rubber-stamp dismissals.
- **Every alert gets a decision before merge:** fix it (push to the same branch — the alert
  auto-resolves when the dataflow path is gone), or **dismiss with a reason**
  (false positive / used in tests / won't fix) and a one-line justification. A dismissal
  with no rationale is worthless to future-you.

  **Who does this, and how it is observable.** Nothing enforces it: medium/low alerts are
  advisory by the bullet above, so an untriaged one blocks nothing and leaves no trace.
  The actor is the **PR author**, at PR time, and the evidence is the alert's own state —
  every alert on the PR's head SHA must be `fixed` or `dismissed` **with** a
  `dismissed_reason` and a non-empty `dismissed_comment`. Check it, rather than believing
  the check row:

  ```powershell
  $repo = gh repo view --json nameWithOwner --jq .nameWithOwner
  ```

  ```powershell
  $pr = gh pr view --json number --jq .number
  ```

  ```powershell
  gh api "repos/$repo/code-scanning/alerts?ref=refs/pull/$pr/head&state=open" --jq '.[] | "\(.number) \(.rule.security_severity_level // .rule.severity) \(.rule.id)"'
  ```

  A non-empty result is the untriaged set. If you are not going to enforce that, say the
  triage is advisory too — a mandatory-sounding rule that nothing observes is unfalsifiable
  compliance, and it teaches the reader that the other rules here are optional as well.
- **Prefer dashboard dismissal over inline `// codeql[rule-id]` suppression.** Reserve inline
  suppression for structural false positives that will recur.
- **Don't merge with "fix it later" intentions** — once merged, the alert detaches from PR
  context and rots in the backlog. Triage at PR time.

### Reading public alert state needs the `security_events` scope

The default `gh auth login` token (`repo, workflow, read:org, gist`) **cannot read the
Code Scanning API** — `gh api .../code-scanning/alerts` 403s and the repo looks like CodeQL
is *disabled* even when it's scanning fine (see `deploy-and-ci-traps.md`). To list/triage
alerts from the CLI, the user must add the scope:

```powershell
gh auth refresh -h github.com -s security_events
```

Hand this to the user to run (it's an interactive browser flow). Verify free CodeQL default
setup through its own endpoint; Code Quality uses the same `CodeQL` workflow name, so an
Actions workflow entry is ambiguous. `GET repos/{owner}/{repo}/code-scanning/default-setup`
must return `state: configured`:

```powershell
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
```

```powershell
gh api "repos/$repo/code-scanning/default-setup" --jq '{state,languages,query_suite,updated_at}'
```
