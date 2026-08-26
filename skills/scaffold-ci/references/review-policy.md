# Review policy contract

Read this reference for `.gitignore`, review-policy guard, risk tiering, or CodeRabbit spend controls.

## `.gitignore` — keep the review policy addable

Ignore Claude's local scratch with a file glob, not a directory exclusion. Git cannot
re-include a file whose parent directory is excluded:

```gitignore
.claude/*
!.claude/review-policy.json
```

Verify addability rather than trusting the text:

```text
git add --dry-run .claude/review-policy.json
```

Success means the policy is addable. If it fails as ignored, then run
`git check-ignore -v .claude/review-policy.json` to identify the rule. Do not use verbose
`check-ignore` as the pass/fail test: for an untracked but re-included file it can print the
matching `!` rule even though the file is addable.

Agent tooling writes per-machine state into the repo it is pointed at, and every such
directory belongs in `.gitignore` or it surfaces as untracked work in a status sweep:

```gitignore
.semgrep/
```

`semgrep-guardian` writes `.semgrep/guardian.yml` into whichever repo it scans. It is
local config, regenerated on demand, never project source. Ignore the whole directory —
`.semgrep/guardian.yml` alone leaves the cache behind.

## `review-policy-guard.yml` — the control plane must not delete itself

`git add --dry-run` above verifies addability **once, at scaffold time**. The invariant
has to hold on every later commit too, because one `.gitignore` line re-excluding
`.claude/` makes the policy file vanish and silently reverts the whole repo to NORMAL —
and the PR making that change would be the last one reviewed properly.

**Copy the shipped assets; do not retype them from this page.** The guard delegates its
workflow assertions to a structural checker, and both must land in the repo:

```bash
mkdir -p .github/workflows .github/scripts
cp ~/.agents/skills/scaffold-ci/assets/review-policy-guard.yml .github/workflows/
cp ~/.agents/skills/scaffold-ci/assets/assert_workflow_hygiene.py .github/scripts/
```

The path is `~/.agents/skills/`, the canonical cross-CLI home — not any single runtime's
skills root, which would resolve only under that runtime.

This used to be an inlined two-check snippet, and the snippet had drifted: the shipped
asset additionally rejects an **empty** policy file, **invalid JSON**, a **missing `high`
array**, and a policy that has dropped `.claude/review-policy.json`, `.coderabbit.yaml`,
the guard workflow itself, or the hygiene checker from `high`, and it sets
`permissions: contents: read`. A repo scaffolded from the prose therefore got a guard
that passed on four of the states the asset was extended to catch. The guard and checker
are tiered HIGH because the required `Review policy intact` context is produced by the
PR's OWN copy of the workflow — a PR that replaced its assertion steps with `run: true`
would report green while asserting nothing, and only a HIGH tier puts that diff in front
of a reviewer. The asset's own comments record why: an automated rollout once emptied
the policy file across 21 repos, and the first version of the guard — the two-check
version — passed throughout, because an empty file is still tracked and still unignored.

Two details worth knowing rather than rediscovering:

- `--no-index` on `git check-ignore` is load-bearing. Without it `check-ignore` consults
  the index and never reports a **tracked** file as ignored, so that check passes
  unconditionally and guards nothing.
- The workflow runs on pushes to mainline and pull requests targeting mainline. Branch
  pushes are omitted because the pull-request event already covers them.

Where this workflow exists, `.gitignore` is NORMAL — do not also tier it HIGH.

### Workflow hygiene, asserted rather than reviewed

The guard's workflow assertions live in the checker script it invokes,
`.github/scripts/assert_workflow_hygiene.py` — a structural YAML parse, NOT a grep. The
line-anchored greps it replaced were bypassable by ordinary block-style YAML (a value on
the line after its key resolves identically but matches no key-anchored pattern), so
`permissions:` followed by an indented `write-all`, or a `uses:` split the same way,
both passed green. These assertions are what replaced `.github/workflows/**` in the
policy's `high` list on 2026-08-19 (rationale under *`.claude/review-policy.json`* below):

- **Third-party actions must be pinned to a full 40-character commit SHA** — a hard failure.
  A tag is mutable: whoever owns the action can change what `@v4` resolves to after review.
- **Tag-pinned `actions/*` is conformant, not a finding.** The house standard is the
  inverse of the third-party rule: first-party actions take the major tag, and `audit-ci`
  grades a SHA-pinned first-party action as drift. The checker counts first-party tag
  refs for the summary line and never fails them.
- **No `pull_request_target`, no `permissions: write-all`** — hard failures, and both were
  already at zero occurrences estate-wide when introduced.

**The job name `Review policy intact` is load-bearing.** It is a *required* status check on
mainline in nearly every estate repo, which is also what makes deleting this workflow safe to
leave un-reviewed: the required check simply never reports and the PR cannot merge. Renaming
the job silently detaches that requirement — the rule waits for a context that no longer
arrives — so rename it only alongside a deliberate ruleset update everywhere.

## PR review policy — `.claude/review-policy.json` + `.coderabbit.yaml`

Public repositories receive GitHub's free deterministic CodeQL coverage; Code Quality is a
separate paid, explicit opt-in at every visibility. The two AI reviewers are
separate products and are not equally scarce — which is why the repo declares a risk policy
instead of every PR getting identical ceremony:

- **CodeRabbit** meters reviews **per developer identity across every repo**, rolling 7-day
  window, degrading from 30 reviews/7d with no bypass once degraded. A review spent on a
  zero-risk PR is taken from the pool available to the next migration.
- **Gitar** publishes no review quota — manual `Gitar review` always works. Only its
  *automatic* processing is rationed, against seat headroom per billing period.

So Gitar is the routine reviewer and CodeRabbit is reserved for HIGH-risk changes. The
`pr-review-gate.sh` / `pr-review-watch.sh` hooks enforce this; they read the tier from the
repo's committed policy file.

### `.claude/review-policy.json`

Copy `~/.agents/skills/scaffold-ci/assets/review-policy.example.json` and **edit it for this repo**. Rules:
any changed file matching `high` ⇒ HIGH; *every* changed file matching `low` ⇒ LOW;
anything else ⇒ NORMAL. Omitting the file is safe and means everything is NORMAL.

The asymmetry is deliberate — HIGH needs one match, LOW needs unanimity — because an
unrecognised path is unknown risk, and unknown risk is not low risk.

- **`high`** is broadly portable: migrations, `infra/**`, `**/*.bicep`,
  `.github/dependabot.yml`, auth paths and money-ledger writes. Still trim it to globs the
  repo actually has.
- **`.github/workflows/**` is deliberately NOT HIGH, and must not be re-added.** Workflow
  hygiene is asserted mechanically; the measured review-budget rationale is in
  [provenance.md](provenance.md). `.github/dependabot.yml` stays HIGH because its semantic
  policy cannot be checked by the workflow parser.
- **Dependency manifests do NOT belong in `high`** — not `package.json`,
  `package-lock.json`, `Directory.Packages.props`, `**/*.csproj`. **Reversed 2026-07-29**;
  this list used to include them on supply-chain grounds. Dependency PRs are now out of AI
  code review on both vendors, so classing a manifest HIGH demands a reviewer that can never
  run — coverage on paper, none in fact. Registry, SDK and analyzer config stays HIGH
  (`nuget.config`, `global.json`, `.npmrc`, `Directory.Build.props`): a bot does not edit
  those, and a change to one redirects where dependencies come from.
- **The review control plane must be HIGH in every repo** — `.claude/review-policy.json`
  itself, `.coderabbit.yaml`, `.github/workflows/review-policy-guard.yml` and
  `.github/scripts/assert_workflow_hygiene.py`. Unlisted they classify as NORMAL, which
  means the single edit capable of disabling review across the repo would itself receive
  the lighter review. The guard and checker are on the list because the required
  `Review policy intact` context is produced by the PR's own copy of the workflow, so
  neutering its steps would otherwise pass unreviewed.
- **So must the merge barrier** — `.github/workflows/ci.yml`,
  `.github/workflows/review-policy-guard.yml`, `.github/scripts/assert_gate_coverage.py`,
  `.github/scripts/assert_workflow_hygiene.py`. These are named paths, not a restored
  broad workflow glob; adjust `ci.yml` when a repository uses another main workflow name.
- **`.gitignore` is deliberately NOT HIGH, and must not be re-added.** It was removed
  on 2026-08-02 and replaced by `review-policy-guard.yml` (below). Tiering it HIGH does
  work, but it bills a CodeRabbit review — metered per developer across the whole
  estate — for every trivial ignore edit, because the policy hook tiers by path glob
  and cannot tell "re-excludes `.claude/`" from "ignores a scratch directory". The
  guard asserts the invariant directly instead: deterministic and free.
  `~/.agents/skills/scaffold-ci/assets/review-policy.example.json` carries the same instruction —
  do not re-add `.gitignore` to `high` without first removing the guard.
- **`low` is the dangerous list and is repo-specific fact.** A path belongs there only if
  it is provably unreachable from **every deploy path in this repo** — which a generic hook
  cannot determine. Worked example: a `.dockerignore` is LOW in a repo whose frontend ships
  via npm + `static-web-apps-deploy` and whose CI only pulls a postgres service container,
  because nothing deployed is built from a Dockerfile. In a repo that ships a container
  image, the same file is NORMAL. **Never copy a `low` list between repos** without
  re-checking it against that repo's actual deploy jobs.
- Markdown is the usual `low` trap: `**/*.md` is genuinely low-risk in a service repo, but
  NOT in a repo that *publishes* its markdown (docs sites, content-driven frontends,
  skill/prompt repos where a `.md` file is the shipped artefact).

The file is committed, so classification rules get scrutinised once in a PR rather than
re-argued per PR by an agent. Agents must never self-classify or work around a tier.

### `.coderabbit.yaml`

Minimum house content — this is spend control, not review configuration:

```yaml
reviews:
  auto_review:
    # LABEL-TRIGGERED, not automatic. `enabled: false` WITH a `labels` list means a
    # positive label match still triggers a review — the label is the TRIGGER, not an
    # exclusion filter. pr-review-gate.sh applies `review-high` at PR-create time when
    # the tier is HIGH.
    enabled: false
    labels: ["review-high"]
    drafts: false
    # Still load-bearing under label triggering: once a PR carries the label, every
    # later push re-reviews it. Default 5; CodeRabbit's own docs suggest 1-2.
    auto_pause_after_reviewed_commits: 2
    # Dependency PRs are out of AI code review on both vendors; Gitar's bot review is
    # switched off too. CodeRabbit already declines bot authors ("Review skipped: bot
    # user not eligible for review"), so this states the intent rather than leaving it
    # incidental to a vendor behaviour that can change.
    ignore_usernames:
      - "dependabot[bot]"
      - "renovate[bot]"
```

**`enabled: false` on its own is NOT the house standard, and is worse than leaving
auto-review on.** Without the `labels` list the hook's `review-high` label is inert, so no
CodeRabbit check ever registers — and `pr-review-watch.sh` reads a persistently absent
check as "CodeRabbit is not installed in this repo" and stops gating on it. A HIGH-tier PR
then merges unreviewed while every signal looks clean. The two settings go together or not
at all.

- **Keep `auto_pause_after_reviewed_commits: 2`.** It is *not* dead config under label
  triggering: a labelled PR re-reviews on every subsequent push, and each one spends from
  the same pool.
- **`ignore_title_keywords` is a trap, not a saving.** `"chore:"` looks harmless and
  matches this estate's Dependabot titles verbatim (`chore: Bump X from 1.0 to 1.1`) —
  several repos were silently skipping every dependency PR through it without meaning to.
  Decide what gets skipped by **path** (`review-policy.json`) and by **author**
  (`ignore_usernames`), never by a title, which can lie about what a PR touches.
- **`ignore_usernames` was the opposite before 2026-07-29** — an explicit instruction NOT
  to ignore the dependency bots, on supply-chain grounds. Normalizing an older repo you
  will find that comment; replace it, or the file keeps arguing against its own settings.
- The matching Gitar setting is dashboard-only: Settings → Scope → **Allowed bots**, which
  must be **empty**.
- Keep `base_branches` in a repo whose mainline is not the GitHub default branch (a fork):
  it defaults to the default branch only, which in such a repo is never PR'd into.
