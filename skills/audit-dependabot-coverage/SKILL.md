---
name: audit-dependabot-coverage
description: Use when checking whether Dependabot is actually FIXING the alerts it raises — reconciles open Dependabot alerts against open Dependabot PRs across an estate and reports alerts nothing is acting on. Triggers include /audit-dependabot-coverage, "is Dependabot keeping up", "any alerts without a PR", "Dependabot coverage check". Complements audit-ci, which checks that Dependabot is CONFIGURED correctly.
---

# Audit Dependabot Coverage

Answer one question per repository: is every open Dependabot alert either being fixed
by an open Dependabot PR, or old enough that its absence is itself a finding?

Read-only. Never dismisses an alert, opens a PR, or closes anything.

```
pwsh -File ~/.agents/skills/audit-dependabot-coverage/reconcile.ps1
```

## Why this is not a configuration check

`audit-ci` already checks whether Dependabot is set up correctly — `dependabot.yml`
shape, ecosystems, directories, private registries plus a Dependabot-store secret,
`vulnerability-alerts` returning 204, `automated-security-fixes` enabled and unpaused.

**Every one of those passed while a high-severity alert sat unfixed for four days.**
On 2026-08-08 a nanoid advisory opened on `your-repo`. Dependabot read
`postcss`'s `nanoid: "^3.3.16"` as a ceiling rather than a floor, concluded no
non-vulnerable version could be installed, and raised nothing. A three-line
lockfile-only bump to 3.3.18 under that unchanged constraint fixed it. Full write-up:
trap 16 in `~/.agents/notes/npm-publishing-traps.md`.

So this skill checks the **outcome**, which is a different axis from the
configuration. A repo can be config-perfect and outcome-broken at the same time, and
the failure mode is a confident wrong answer rather than silence — nothing surfaces
it. That matters more since the paid scanning products went off org-wide on
2026-08-04: Dependabot is now the only automated security signal on the private repos.

## Invariants

- **Read-only.** No dismissals, no PRs, no closes. A genuine "won't fix" is dismissed
  on GitHub by a human, which drops it from `state=open` naturally — so there is no
  ledger here, unlike `ai-findings-ledger`, whose surface has no dismiss API.
- **Never report unread as clean.** A repo whose alerts cannot be read (disabled, or
  the token lacks `security_events`) is listed under NOT CHECKED, never counted as
  having none. The summary states how many alerts were examined, so "no findings" and
  "saw nothing" cannot be confused.
- **Unmatched always reports.** A too-loose match suppresses the very finding this
  exists to surface. A too-strict one costs a human five seconds.
- **Never self-triage.** Every row goes to a human. Do not dismiss by severity, age,
  scope or rule family.
- **Repository list is derived live** from `gh repo list`, never hard-coded — a repo
  added later would otherwise be silently uncovered.

## How matching works

Alerts pair to PRs on the package name **anchored to the verb Dependabot writes** in
the PR body — `Bumps [pkg]`, `Bumps \`pkg\``, `Updates \`pkg\`` — in link, backticked
or bare form.

The body, not the branch. A grouped PR's branch carries only a hash
(`dependabot/npm_and_yarn/web/npm-minor-and-patch-eff5aeb2ab`) and names no package,
so branch parsing would miss every grouped fix while appearing to work. Its body
lists each one.

The verb anchor is load-bearing. Dependabot embeds release notes and changelogs that
name dozens of unrelated packages; an unanchored substring match would read those as
fixes and mark real alerts covered.

## Reading the output

Each row is an open alert with no open Dependabot PR naming that package. Dependabot
may have decided no fix exists — or decided that **wrongly**. Those are
indistinguishable from outside, which is why a human reads the row.

To tell them apart, the update-job log is the only evidence, and it has **no API**:
Insights → Dependency graph → Dependabot → the ecosystem row → *Last checked*.

Before accepting any "cannot update to a non-vulnerable version" verdict, read what
the parent actually declares:

```
grep -A3 '"node_modules/<parent>"' package-lock.json
```

A caret or tilde range spanning the patched version means a lockfile-only bump
resolves it, whatever the log claims.

## Options

| Flag | Purpose |
|---|---|
| `-Org` | Organisation(s) to enumerate. Default `<your-org>`. |
| `-Repo` | Explicit `owner/repo`, repeatable; skips enumeration. |
| `-GraceHours` | Age below which an alert is not reported. Default 48 — one weekly window plus queue time. |
| `-AlertState` | `open` (default), or `fixed`/`dismissed` to backtest against history. |
| `-Json` | Machine-readable output for a scheduled run. |

`-AlertState fixed` is how the emit path was validated against the real nanoid alert.
Note its limit: PR state is read as it is **now**, so a historical run cannot
reconstruct which PRs were open at the time — a since-merged PR shows as absent. It
proves the pipeline, not the historical pairing. The matcher's nanoid-versus-grouped-PR
case is pinned in `test/verify-matcher.ps1` instead.

## Cadence

Weekly, after the estate's Monday 06:00 Europe/London Dependabot window has had the
day to produce PRs. That turns a four-day miss into under one.

Not a SessionStart hook: 27 repos of API calls on every session start is the kind of
latency that gets a check switched off.

## Related

- `audit-ci` — the configuration axis. Run both; neither substitutes for the other.
- `audit-github-estate` — the full gated estate audit; calls this for its Dependabot
  section so there is one implementation.
- `~/.agents/notes/npm-publishing-traps.md` — trap 16 (the wrong verdict), trap 13
  (`npm ls` reads a stale tree), trap 15 (`audit fix --force` can propose a downgrade).
