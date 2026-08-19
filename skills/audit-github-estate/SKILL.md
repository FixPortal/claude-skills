---
name: audit-github-estate
description: Audits GitHub quality and security across an organization or supplied repository estate, including Code Quality, CodeQL/code scanning, Dependabot, secret scanning, repository security advisories, Actions evidence, remediation, and post-merge verification. Triggers include /audit-github-estate, "audit the GitHub estate", "GitHub estate audit", and "audit GitHub security across these repositories".
---

# Audit GitHub Estate

## Objective

Account for every queryable GitHub quality and security surface without
manufacturing a clean dashboard. Completion means no further authorized
automated action remains, not that every dashboard is empty.

Treat all supplied repositories as one coordinated job, but use one branch and **at most
one** remediation PR per repository, opened only where committed changes exist. An estate
routinely contains repositories that are already compliant and repositories needing only
API or UI dispositions; an unconditional "exactly one PR per repository" would force an
empty PR for those. Stop at a green PR unless the user separately authorizes merge.

Before auditing or changing GitHub Actions or CI configuration, read the canonical
`~/.agents/notes/deploy-and-ci-traps.md`; use its current guidance instead of memory.

## Estate policy

Apply this visibility policy before classifying findings:

| Repository visibility | Paid-product policy | Expected configuration |
|---|---|---|
| Public | Use GitHub's free public CodeQL and Secret Protection coverage. Code Quality remains a paid explicit opt-in. | Attach the public security configuration with Code Security and Secret Protection enabled. Enable CodeQL default setup, secret scanning, repository push protection, non-provider patterns, validity checks, extended metadata, generic-secret detection, and private vulnerability reporting where GitHub exposes them. Keep Code Quality disabled unless the user explicitly approves the current charges. |
| Private or internal | No paid Code Security or Secret Protection. Code Quality remains a paid explicit opt-in. | Leave repositories unattached from paid security configurations, disable effective `code_security` and all secret-scanning features. Keep Code Quality disabled unless the user explicitly approves the current charges. Keep Dependency Graph, Dependabot alerts, and Dependabot security updates enabled. |

Derive identity and policy inputs live for each repository with
`GET /repos/{owner}/{repo}`. Retain `.visibility`, `.owner.type`, and
`.security_and_analysis` from the same response; do not infer visibility or owner type
from an account allowlist, a local remote, or a previous run. Owner type determines the
public secret-alert inventory route, while visibility determines paid-product policy.

### Paid security control readback

GitHub's current repository API and code-security-configuration API use different
names for some controls. Enumerate both surfaces; a disabled parent never proves its
children are disabled.

| Effective repository field | Configuration counterpart | Public | Private/internal |
|---|---|---|---|
| `code_security` | `code_security` | `enabled` | `disabled` |
| `secret_scanning` | `secret_scanning` | `enabled` | `disabled` |
| `secret_scanning_push_protection` | `secret_scanning_push_protection` | `enabled` | `disabled` |
| `secret_scanning_ai_detection` | `secret_scanning_generic_secrets` | `enabled` | `disabled` |
| `secret_scanning_non_provider_patterns` | `secret_scanning_non_provider_patterns` | `enabled` | `disabled` |
| `secret_scanning_validity_checks` | `secret_scanning_validity_checks` | `enabled` | `disabled` |
| `secret_scanning_delegated_alert_dismissal` | `secret_scanning_delegated_alert_dismissal` | `disabled` | `disabled` |
| `secret_scanning_delegated_bypass` | `secret_scanning_delegated_bypass` | `disabled` | `disabled` |

The named public configuration also has controls without a repository-field mapping:

| Configuration field | Public configuration | Private/internal |
|---|---|---|
| `secret_protection` | `enabled` | `not attached` |
| `code_scanning_default_setup` | `enabled` | `not attached` |
| `code_scanning_delegated_alert_dismissal` | `disabled` | `not attached` |
| `secret_scanning_extended_metadata` | `enabled` | `not attached` |
| `private_vulnerability_reporting` | `enabled` | `not attached` |

Also inventory the legacy aggregate `advanced_security`. The configuration's
`secret_protection` and repository's
`secret_scanning` children are separate evidence. Do not use `advanced_security` as a
substitute for the individual `code_security` and `secret_protection` fields: GitHub
documents it as the legacy bundled-product control and says it cannot be used for
standalone products. The repository API calls generic-secret coverage
`secret_scanning_ai_detection`; configurations call it
`secret_scanning_generic_secrets`.

After every approved repository `PATCH`, issue a fresh
`GET /repos/{owner}/{repo}` and compare every effective control in the table with the
visibility target. Then retrieve `GET /repos/{owner}/{repo}/code-security-configuration`:
public repositories must show the resolved public configuration attached; private or
internal repositories must return no attached configuration. Re-read the named public
configuration and verify `code_security`, `code_scanning_default_setup`,
`code_scanning_delegated_alert_dismissal`, `secret_protection`, `secret_scanning`,
`secret_scanning_push_protection`, `secret_scanning_validity_checks`,
`secret_scanning_non_provider_patterns`, `secret_scanning_generic_secrets`,
`secret_scanning_delegated_alert_dismissal`, `secret_scanning_extended_metadata`,
`secret_scanning_delegated_bypass`, and `private_vulnerability_reporting`. Check the exit
status before decoding any `gh api` output. A missing field is `UNKNOWN`, never equivalent
to `disabled`.

### Unsupported repository mutation

The current official repository PATCH schema does not expose
`secret_scanning_validity_checks`. If that effective repository field remains enabled on
a private/internal repository after detachment, its state is known `NONCOMPLIANT`: leave
the finding open and report only the unsupported mutation as an automation boundary. An
omitted field or read failure is `UNKNOWN`. Do not guess an undocumented payload. Public
repositories can set and verify the field through their named configuration.

Resolve configurations live by name and verify their effective fields;
configuration IDs are not durable policy. Set the public configuration as the
default for public repositories. No paid security configuration should be the
default for, or attached to, private/internal repositories.

Before inspecting or changing any repository's Code Quality setup, establish the
organization or enterprise **Repository access** selection, enforcement, and
displayed billing impact. Record the current cost authorization. Treat any
organization-level access or repository setup that enables Code Quality without
explicit approval of the current charges as drift.

**That surface is UI-only: GitHub exposes no organization endpoint for it.** Code
Quality is published at repository scope only (`code-quality/setup`,
`code-quality/findings`). So "establish" means **ask the user** to read
*Organization settings → Code security → Code Quality* and report the selection, the
enforcement toggle, and the displayed figure; their answer, dated, is the evidence.

Do not make a repository-level Code Quality change until that control and its approval
are known. If the user has not answered, that is a **stated evidence gap**, not a
blocker on the whole run: record `Code Quality org access: UNVERIFIED (UI-only,
awaiting operator)`, skip only the Code Quality mutations, and complete every other
surface. A hard precondition with no way to discharge it would otherwise stall an
estate audit indefinitely, or — worse — get silently assumed.
The default compliant organization state is **No repositories** with **Enforce
access** on. An approved paid exception uses **Selected repositories** containing
exactly the approved repositories, also with enforcement on. Treat `Let repositories
decide`, a broader selection, or enforcement off as drift unless the user explicitly
approved that exact scope.

Treat a private repository with Code Security, Code Quality, and Secret
Protection disabled as **compliant by policy**, not disabled evidence, an
automation blocker, an incomplete surface, or a licensing recommendation. Do
not query its code-scanning or secret-scanning endpoints and reinterpret the
expected `403`/`404` as a finding. Treat any unauthorized paid product, or required
free public coverage disabled publicly, as configuration drift to fix after approval.

Code Quality's organization access, repository setup API, and automatic
Copilot-review ruleset are separate controls. Verify all three. Every repository
must report `state: not-configured` unless its current charges were explicitly
approved. An approved repository must report `state: configured` with
`ai_findings_option: disabled`. No repository should retain the generated
`Code Quality Copilot review for default branch` ruleset.

Keep delegated bypass and delegated alert dismissal disabled unless the user
explicitly defines the actors and governance workflow. They grant administrative
privileges; they are not missing detection coverage. Check effective repository
settings where GitHub exposes them.

Secret-scanning push protection scans pushed content for credentials. Branch
protection and repository rulesets govern who may push and which PR checks are
required. Inventory and report them separately; never infer one from the other.

Repository security advisories and private vulnerability reporting apply to
public repositories. Query the organization advisory endpoint and public
repositories only. A repository-advisory `404` for a private repository is
**not applicable**, not inaccessible or incomplete. Repository security
advisories are also distinct from Dependabot alerts.

## Phase 1: Resolve and authenticate

1. Resolve every target to exact `OWNER/REPOSITORY`, local path when available,
   visibility, default branch, and current remote default-branch SHA.
2. Verify `gh auth status`, required scopes, and organization role before using
   GitHub evidence.
3. Read every applicable `AGENTS.md`, repository instructions, and committed
   review policy. Preserve dirty and unrelated work.
4. Read GitHub's current REST documentation and use the currently supported API
   version in every request. Use full pagination.

## Phase 2: Read-only baseline

Inventory each repository before changing anything:

- Code Quality findings and current default-branch analysis only for repositories
  where paid Code Quality is explicitly authorized and enabled.
- CodeQL/code-scanning alerts, analyses, tools, and default setup only where
  Code Security is expected to be available: public repositories under this
  policy.
- Dependabot alerts, dependency graph, security updates, and updater runs.
  **Reconcile those alerts against open Dependabot PRs by invoking
  `audit-dependabot-coverage`** rather than reimplementing it here. An open alert that
  nothing is acting on is a finding in its own right, and it is invisible to every
  configuration check: on 2026-08-08 a high-severity nanoid advisory on
  `your-repo` went four days with no PR because Dependabot reached a wrong
  verdict, while security updates were enabled, unpaused and correctly configured
  throughout. See `~/.agents/notes/npm-publishing-traps.md` trap 16.
- Secret-scanning configuration only where enabled by estate policy. For a public
  repository **owned by an organization**, inventory alerts through
  `GET /orgs/{org}/secret-scanning/alerts`; the repository-level alert
  list/get/update/location endpoints document `404: Repository is public`, so they are
  not an inventory source. That org response is org-wide: **filter it by
  `repository.full_name`** before writing any per-repository ledger, and state the
  filter you applied — Phase 2 requires one ledger per repository and an unfiltered
  response silently attributes every repo's alerts to whichever one you were writing up.
- **A public repository owned by a USER has no alert inventory source at all.** GitHub
  publishes no user-namespace equivalent of the org endpoint (`/users/{user}/…` does not
  exist), and the repository-level endpoints `404` precisely because the repo is public.
  Classify the owner live from `.owner.type`. Declare these repositories a **UI-only
  evidence boundary** and report them as such — never as zero findings, and never as
  "not applicable". Phase 2's own requirement to distinguish an empty queue from an
  unavailable one cannot be met any other way.
- Organization/public repository security advisories.
- Latest default-branch Actions checks and security-product configuration.
- Rulesets and branch protection as a separate control surface when in scope.

For every policy-enabled current analysis, compare `headSha` with the current
default-branch SHA. Distinguish zero open items from not applicable by policy,
inaccessible, stale, pending, failed, or unavailable evidence. Expected private
Code Security and Code Quality disablement is not incomplete evidence.

Create one ledger per repository with:

- Surface and alert/finding number.
- Rule or advisory, severity, exact location, state, and message.
- Root cause and grouped duplicates.
- Proposed disposition: `Fix`, `Dismiss`, `Retain`, `Automation blocked`, or
  `Not assessed`.
- Evidence, smallest remediation, and acceptance check.

Never dismiss by severity, age, rule family, or desire for a clean dashboard.
Use only reasons accepted by that product's API and supported by evidence.

## Phase 3: Approval gate

Present the baseline, grouped root causes, proposed API dispositions, proposed
repository/configuration changes, expected residuals, visibility-policy drift,
and any current Code Quality charges or access expansion. Then stop for approval.

Before approval, do not dismiss or resolve alerts, alter repositories or
security configurations, push, open PRs, merge, or trigger scans. A review-policy
exception is valid only when the user states it explicitly for that repository
and run.

## Phase 4: Remediate approved findings

Public secret-scanning alerts are an exception to the generic API disposition
sequence. Retain the organization alert response as inventory evidence, do not
call the repository-level list/get/update/location endpoints, and do not attempt
an API disposition: GitHub documents `404` for those endpoints when the
repository is public. Report repository-level retrieval and update as a UI-only
automation boundary, not as inaccessible evidence or a not-applicable surface.

Report that boundary as a **table**, not prose — anything the user must action by hand
gets lost in a wall of text, and this set is by definition entirely hand-actioned:

| Alert | Repository | Secret type | Location | Action the user must take |
|---|---|---|---|---|
| `#<number>` | `owner/repo` | e.g. `github_personal_access_token` | `path:line` | Open the alert in the UI and close it as revoked / false positive / used in tests |

Same shape as the dismissal hand-off in `ai-findings-ledger`, for the same reason.

For all other API dispositions, retrieve each item immediately before mutation,
apply only the supported product-specific state/reason/comment, retrieve it
again, and retain complete before/after evidence. Leave rejected or unavailable
mutations open and report the automation boundary.

Code Quality findings cannot currently be dismissed through the API. Fix
actionable findings in code. Report any remaining open findings as UI-only
automation blockers; do not use browser automation or invent a dismissal path.

For public Code Security and Secret Protection drift, prefer attaching repositories
to the existing public policy configuration over duplicating settings repository by repository.
For private paid-product removal, first remove any private/internal default from
the paid configuration, detach the private repositories, then disable the
effective repository `security_and_analysis.code_security` setting. GitHub may
accept `code_security: disabled` on an attached configuration without changing
its legacy `advanced_security: code_security` state, and may reject
`advanced_security: disabled`; trust the effective repository setting, not the
configuration PATCH response. Disable Code Quality through
`PATCH /repos/{owner}/{repo}/code-quality/setup` with
`state: not-configured`, and remove only the generated single-rule
`copilot_code_review` ruleset after validating its exact contents. Poll
asynchronous attachment states and verify effective repository settings
afterward. Enable Code Quality only for repositories covered by the user's
explicit approval of the current charges.

For code/configuration changes:

1. Use the repository's required isolated worktree and branch convention.
2. Fix shared root causes, not repeated symptoms.
3. Run the complete relevant local format, analysis, build, test, lint,
   typecheck, production-build, workflow-lint, and security checks.
4. Push once when green, and open a PR for that repository **only if it has committed
   changes** — at most one, per the rule at the top of this skill. A repository whose
   remediation was entirely API or UI dispositions gets no PR and no branch.
5. Follow the committed review-policy tier and active reviewer-budget rules
   without self-classifying. Use Gitar and CodeRabbit only as required.
6. Rebase-merge only when separately authorized.

Keep unrelated cleanup and dependency churn out of scope.

## Phase 5: Post-merge evidence

After merge, wait for GitHub's automatic default-branch CodeQL analysis and, only
where paid use is explicitly authorized, Code Quality analysis. Do not toggle security
products, submit an unchanged setup patch, or
create a meaningless commit to provoke a scan. GitHub-generated default-setup
workflows may not support manual dispatch or rerun.

Require each relevant successful analysis `headSha` to equal the current
default-branch SHA. Otherwise classify that surface as incomplete. Re-query
every enabled surface and current default-branch check after scans settle.

Classify each repository:

- `Clean`: every enabled/queryable queue is empty and current scan evidence is
  successful.
- `Accounted for`: every residual is assessed and no further authorized
  automated action remains, including policy-approved disabled surfaces.
- `Incomplete`: required evidence is inaccessible, stale, pending, failed, or
  unavailable.

Report the initial/final count matrix, finding-to-disposition ledger, API
mutations, commit and PR references, scan URLs and SHA proof, policy-disabled
products, residual items, and exact reason automation stopped.
