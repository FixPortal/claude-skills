---
name: review-digest
description: Use when the user runs /review-digest or asks for a read-only intelligence report on PAST adversarial-review / reviewer-findings work across repos — 'review digest', 'what's already been reviewed', 'past review coverage', 'recurring review findings', 'what do the review batches tell us'. This harvests existing review output; it does NOT run new reviews (that's adversarial-review / review-sweep) and never edits CLAUDE.md or scaffolds.
---

# Review Digest

## Overview

Mine **past** review work — git remediation commits + vault adversarial-review
reports — across the repos under a folder into one dated markdown report. This
skill reads what `adversarial-review` / `review-sweep` already produced; it never
runs a review and never branches or commits to the scanned repos.

## Invocation

`/review-digest [path]`
- No arg -> scan all git repos directly under `<workdir>`.
- `path` arg -> scan that folder instead.
- A single repo name/path -> digest just that one repo.

## The spine

1. **Collect** — run `collect.ps1` to produce `digest-data.json` (deterministic).
2. **Classify** — match each finding against `themes.json`; append new themes.
3. **Join** — bucket each repo (git n vault / git - vault / vault - git / neither).
4. **Rank** — forward-looking risk score per repo (what is UNREVIEWED now).
5. **Delta** — diff against the most recent prior report in the Review Ledger folder.
6. **Write** — the dated digest report; **write back** themes.json.
7. **Hand-off** — write the sibling `<timestamp>-handoff.md` scope brief for another agent.

## 1. Collect

Resolve the directory containing this loaded `SKILL.md`, then run its sibling
`collect.ps1` once with `pwsh -NoProfile -File <skill-dir>\collect.ps1 -Path
<path>`
(defaults `-OutFile` to `%TEMP%\review-digest-data.json`). It exits non-zero on a
bad path or a folder with no git repos — STOP and report if so. Read the JSON;
each repo carries `git` (reviewCommits — each entry has `{ sha, date, subject,
fixerModel }`, lastReviewDate, batchMarkers
— strict numbered review batch/run identifiers from commit subjects or trailers, e.g.
`reviewer-findings batch 1` or `adversarial-audit run 2`),
`vault` (exists, reviewers = panel models, judge, date, reviewType, tally = found
C/H/M/L, `reviewTarget` / `reviewScope` = the report's `target:` / `scope:` fields, `isDocumentReview` = true when that
target is a document not a code tree), `hasGraphify` (a `graphify-out/` dir is present in the
repo), `hasTrackedSource` (tri-state: true/false for a verified probe — false means a docs/spec/CV
repo — and **null when the `git ls-files` probe itself failed**: that is UNKNOWN, never a
verified "no source"), and `outsideScanPath`.

**`isDocumentReview` — a document review is NOT code coverage.** When true (e.g. `resumes-cv`,
`target: your-cv.html` — a reviewed CV), the review confers zero coverage on any
code. Render such a row as reviewed-a-document, never as a reviewed (or unreviewed) code repo,
and never let it enter a bucket or the rank. The script warns these separately from genuine
unresolved rows.

**`hasTrackedSource` — voids the never-reviewed floor.** A never-reviewed repo with
`hasTrackedSource = false` has no code to review (docs/specs/playbooks/CVs — `engineering-system`,
`initiator`, `qa`, `personal-resumes`). It must NOT get the `100 + commits` floor (see §4) — that
floated four such repos above genuinely-unreviewed code across three prior digests. Report it as
"not code-reviewable", not as a review priority.

**Vault-folder resolution.** A vault folder name is NOT proof of a repo — it may name a
**subsystem** of one. Each vault-only folder is resolved to real code in priority order:
(1) its report's `file:///` links (walked up to the enclosing `.git`); (2) its `scope: <sha>..HEAD`
sha, tested with `git cat-file -e` against every in-path and `-RepoRoots` repo — the falsifiable
check that survives a prefix rename; (3) a normalised name search, exact then **suffix then
substring** (so `quickfixn` finds `quickfix-n` AND `budget-tracker` finds `personal-budget-tracker`).
Stages 2 and 3 resolve only on a **unique** candidate — a sha living in a fork/mirror/worktree, or
a name matching more than one repo, is warned about and left `unresolved` rather than silently
credited to whichever candidate enumerated first.
A vault folder that resolves to a repo **already scanned in-path** is a stale pre-rename duplicate
and is dropped (its own newer in-path row already covers it). Resulting fields:
- `resolvedPath` — the git repo whose tree the review actually covered. The git side
  (`sinceReview`, boundary, staleness) is computed against THIS path, so remediation on an
  `outsideScanPath` row is detectable rather than structurally invisible.
- `isSubsystem` / `subsystemPath` — true when the reviewed code is a sub-path of the host repo
  (`widgetservice` → `host-app` + `Framework\Services\WidgetService`). Every git query for such a row
  is **pathspec-scoped to `subsystemPath`**, so its counts are the subsystem's, not the host's.
  When describing one, name the HOST repo and the sub-path — never the vault folder alone. A
  mere name variance (`quickfixn` → `quickfix-n`) is not a subsystem: same tree, no sub-path.
- `unresolved` — true when nothing could be placed on disk. The script `Write-Warning`s these.
  **Never report an unresolved row's tally as outstanding.**

`git` also carries the **forward-looking scope fields** that drive the risk rank
and the hand-off report:
- `boundarySha` — sha of the last point a genuine ADVERSARIAL review saw the tree.
  Null when the repo was never reviewed.
- `boundarySource` — how the boundary was chosen: `vault-target` (a validated exact commit or
  `<base>..<tip>` in vault `target:` / `scope:` evidence; preferred), `vault-date` (last commit
  on/before the vault adversarial-review date),
  `vault-predates-history` (the vault review is older than the repo's earliest commit,
  e.g. an OSS re-init squash — the boundary is CLEARED and the repo is treated as
  never reviewed with full-history scope, because anchoring at the root commit would omit
  everything the squash introduced and report the tree as reviewed; flag it as a full-repo
  sweep), `git-marker` (no vault
  report — found a reachable review/remediation subject), `none` (never reviewed),
  `scoped-query-failed` / `scoped-no-history-before-review` (a subsystem could not establish a
  date boundary), or `unresolved-vault-folder` (a vault folder that could not be placed on disk
  — review state UNKNOWN, see `neverReviewed` below). Those eight are the only values
  `collect.ps1` ever assigns; a repo sitting outside
  the scanned path is flagged by the separate boolean `outsideScanPath`, not by this
  field. Web-quality
  sweeps (web-quality / a11y `reviewer-findings-batch1` commits) are
  deliberately excluded from boundary candidacy — they are NOT adversarial reviews and
  previously faked `sinceReview=0`.
- `vaultPredatesHistory` — true for the OSS-re-init case above.
- `neverReviewed` — true when there is no `boundarySha`. **One deliberate exception:** an
  `unresolved` row has a null `boundarySha` but `neverReviewed = false`, because a review
  demonstrably happened (`vault.exists`) — we just cannot place the code it covered. Its state
  is UNKNOWN, not "never". Flagging it `true` would assert a falsehood and score it
  `100 + commits`, floating an unknown to the top of the rank. Unresolved rows are excluded
  from ranking entirely instead.
- `effectiveNeverReviewed` — the collector's final eligibility decision. It is true for
  `neverReviewed`, for `vault-predates-history`, and for a `git-marker` without strict numbered
  review or adversarial-audit batch/run/trailer evidence; in the latter cases the false
  boundary is cleared and full history is the scope. Consumers
  must use this field rather than reproducing boundary inference.
- `sinceReview` — commits **since the last review** (`boundarySha..HEAD`), each
  `{ sha, date, subject }`. Empty for a never-reviewed repo (history is not
  dumped) and for a repo whose last commit *was* the review.
- `sinceReviewCount` — count of `sinceReview`; for a never-reviewed repo this is
  instead the **full-history** commit count (full-audit scope).
- `sinceReviewFiles` / `sinceReviewIns` / `sinceReviewDel` — `git diff
  --shortstat boundarySha..HEAD` (files changed, insertions, deletions).
- `daysSinceReview` — whole days between `lastReviewDate` and today; null if
  never reviewed.

## 2. Classify against themes.json

Read `themes.json` beside this loaded `SKILL.md`. For each repo's
review commits + vault report findings,
match the described bug-classes against theme `aliases` (case-insensitive,
substring). Record which themes each repo exhibits. For a genuinely-new recurring
class not covered, ADD a new theme entry (`aliases`, a suggested `home`,
`seen: [repo]`). Merge `seen` repos by set-union: append any repos not already
listed to the existing `seen` array, deduplicate, order does not matter.

## 3. Join (the four buckets)

Classify each repo by what evidence was found — **git** = remediation commits in
the repo, **vault** = a review report in the vault:

- **git n vault** — found and fixed; both model sides known.
- **git - vault** — fixed, no vault report -> flag.
- **vault - git** — reviewed, no remediation commits here. If `outsideScanPath`,
  note "reviewed, lives outside <path>" (NOT a gap). Else: unremediated -> flag.
- **neither** — no git fingerprint AND no vault report -> **coverage gap**.

## 4. Rank (forward-looking risk)

Score each in-path repo by **what is unreviewed now** — NOT by historical
findings. A repo that surfaced many Highs but was fully remediated is low risk;
a repo with 30 commits and no review since is high risk. The vault tally is
shown for context but **does not feed the score**.

Per repo:

```
eligible = !outsideScanPath && !isDocumentReview && !unresolved   # reviewed elsewhere / not code / unplaceable
effectiveNeverReviewed = git.effectiveNeverReviewed

score =
  !eligible ? VOID
  : (hasTrackedSource -eq null) ? UNKNOWN                         # probe failed — never score, never void
  : (effectiveNeverReviewed && !hasTrackedSource) ? VOID          # no code to review — not a priority
  : effectiveNeverReviewed ? (100 + sinceReviewCount)             # never reviewed floats to the top
  : sinceReviewCount * (1 + daysSinceReview / 30)                 # unreviewed work, aged by staleness
  + deferredBacklogCount * 5                                      # still-open deferred items
```

**The `hasTrackedSource` guard is not optional.** A never-reviewed repo with no tracked source
(`git ls-files` for source extensions is empty — docs/spec/playbook/CV repos) is **not
code-reviewable**: void its score, list it separately as "not code-reviewable (0 tracked source)",
and never let the `100 + commits` floor rank it. Missing this floated `engineering-system`, `qa`,
`initiator` and `personal-resumes` into the top-10 across three prior digests. **`hasTrackedSource`
= null is a third state — the probe failed, so the truth is UNKNOWN**: do not void it as
not-code-reviewable and do not score it; surface it as unknown (the review-sweep runbook STOPs on
this row). A `git-marker`
without strict numbered review or adversarial-audit batch/run/trailer evidence is already emitted as
`git.effectiveNeverReviewed` — use that value.

`deferredBacklogCount` = the repo's harvested "out of scope / future batch" items
(same source as the backlog section). Round to a whole number. Rank descending.
A reviewed repo with `sinceReviewCount = 0` scores ~0 → "nothing new" tier.

**Render the component values next to the score** (commits-since, days-stale,
deferred-count, never-reviewed flag) so the rank is auditable, not a black box.

## 5. Delta

Look in `<vault>\Claude\Review Ledger\` for the newest prior digest
(`*.md`, excluding `*-handoff.md`). If one exists, compute what changed since: new batches, new
themes, newly-closed deferred items, newly-reviewed repos, new gaps. First run ->
omit the delta header.

## 6. Write the report

Name the output with the current UTC timestamp:
`<vault>\Claude\Review Ledger\<YYYY-MM-DDTHH-mm-ss.fffffffZ>.md`
(`Get-Date -Format` with that pattern, from `[DateTime]::UtcNow`). A bare date
(`yyyy-MM-dd`) collides on a same-day re-run and silently overwrites the first
run's report. Create the exact path with `New-Item -ItemType File -ErrorAction Stop`
before writing; if it already exists, use a newly captured UTC timestamp.
Never overwrite or force-write an older run's file. Sections, in order:

1. **Since <last date>** (omit on first run).
2. **Review-priority** — repos ranked worst-first by the §4 risk score, with the
   component columns (score | commits-since | days-stale | deferred | never-reviewed?).
   Link to the hand-off file (§7) for the per-repo scope and agent prompt.
3. **Coverage ledger** — repo | reviewed? | latest batch (raw marker) | fixed date | fixer model | panel models | join bucket.
4. **Severity & maturity** — found C/H/M/L (vault tally) vs batches landed (git); note "Highs drying up" where a repo has many batches.
5. **Recurring themes** — per theme: name | count | repos seen | severity skew | prevention-home.
6. **Deferred-findings backlog** — per repo, harvested "out of scope / future batch" items with source sha.
7. **Coverage gaps** — neither-bucket repos; plus a sub-list of `outsideScanPath` repos.
8. **Prevention candidates** — recurring theme -> suggested home. **PROPOSE-ONLY.**

Then write the merged `seen` values and any new themes back to that same
`themes.json`.

## 7. Hand-off scope report

Write a **sibling** file `<vault>\Claude\Review Ledger\<timestamp>-handoff.md`,
where `<timestamp>` is the SAME UTC timestamp used for the §6 digest file (so a
digest and its hand-off pair off by name, and a same-day re-run can never
overwrite an earlier pair).
This is the file you (or the user) hand to **another agent** that holds the
`adversarial-review` skill — it tells that agent exactly what to review and over
what scope, so it spends its tokens reviewing, not rediscovering scope.

Header: generated date, scanned path, and a one-line "hand this file to an agent
with the adversarial-review skill" note.

Then one block per in-path repo, **ordered by the §4 risk rank, worst first**.
Skip a repo whose `sinceReviewCount = 0` and is already reviewed — list those at
the foot under **Nothing new since review** (no prompt). For each ranked repo:

- **Heading** — `repo` — rank #, risk score, `never reviewed` flag if set.
- **Last review** — `lastReviewDate` · latest batch marker · panel models · `daysSinceReview`d stale.
- **Scope** — `boundarySha..HEAD` — `sinceReviewCount` commits, `sinceReviewFiles` files, +`sinceReviewIns`/−`sinceReviewDel`. For a never-reviewed repo say "full repo — never reviewed (`sinceReviewCount` commits total)".
- **Commits since the last review** — the `sinceReview` list as `sha7 — date — subject`, capped at ~40 with a "+N more" line.
- **Recurring weak spots** — the themes whose `seen` array (in `themes.json`) includes this repo. Tells the reviewer where this repo has bled before.
- **Agent prompt** — a fenced, paste-ready block, e.g.:

````
```
Run /adversarial-review on <repoPath>.
Scope: the diff <boundarySha>..HEAD — <N> commits since the last review
  (<batch marker>, <lastReviewDate>).
graphify-out/ present: <hasGraphify>. If yes, run /graphify first and query it
  for the subsystems these commits touch before reviewing.
Recurring weak spots in this repo: <themes>. Probe these first.
```
````

For a **never-reviewed** repo the scope line becomes the whole repo (HEAD) with a
"never reviewed — full audit" note instead of a `boundarySha..HEAD` range.

The hand-off report is **propose / READ-ONLY** like the digest: it names what an
agent *should* review; it runs no review and touches no scanned repo.

## Rendering rules for partial vault data

`collect.ps1` returns `vault.exists=true` even for older PROSE-format `_index.md`
files that have no YAML frontmatter — in that case `reviewers`/`judge`/`date`/`tally`
come back null. Render these honestly:
- Empty `reviewers` with `exists=true` -> panel-models cell = "unknown (prose-format report)", NOT blank.
- Null or partial `tally` -> severity cell = "not available" (or show only the severities that parsed), NEVER "0".
- A blank panel-models cell is reserved for `vault.exists=false` only.

## Hard boundaries

- READ-ONLY on the scanned repos — never branch, commit, or edit their code.
- NEVER auto-edit CLAUDE.md or scaffolds. The prevention candidates are a proposal you action by hand.
- The ONLY file this skill mutates as state is its own `themes.json`. The two
  vault files (`<timestamp>.md` digest, `<timestamp>-handoff.md` scope brief) are outputs,
  created fresh per run with the §6 never-overwrite rule.
- The hand-off report is **propose-only**: it tells another agent what to review;
  it never runs `adversarial-review` itself.
- Do NOT run a review — if the user wants one, that's `adversarial-review` /
  `review-sweep`.
