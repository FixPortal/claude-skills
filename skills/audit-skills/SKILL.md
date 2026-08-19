---
name: audit-skills
description: Use when the user wants their authored agent skills audited across Claude Code, Codex, Kimi Code, or Antigravity for relevance, stale references, weak triggers, runtime incompatibility, or cross-home drift.
---

# Audit Skills

## Overview

Sweep the skills the user **authors and can edit**, and produce a candid,
trend-aware findings report across four axes: **reach** (trigger reliability),
**implementation** (structure against the house skill-writing conventions),
**correctness of references** (every path/file/command/package/constant the
skill names actually resolves today, plus adherence to the user's own active
runtime instructions), and **utility** (evidence that the skill still earns its
place in the active inventory).

**Report only. Never edit a skill body.** Editing a skill is a separate,
deliberate act governed by the skill-writing Iron Law (a skill edit needs a RED
test first). A blind fix here would violate that.

**The core differentiator — and the thing agents reliably skip — is that the
audit VERIFIES references itself.** Baseline testing showed even strong agents
eyeball the prose and hand verification back ("verify that path exists on your
machine") instead of running the check. That is the failure this skill exists to
prevent.

Use the rubric in `audit-brief.md`. Use the runtime's native parallel-agent
capability when available; it is not a portability requirement. Audit
sequentially when the runtime cannot delegate.

## When to Use

- User asks to audit / sanity-check / quality-check their skills, or suspects
  skill rot (a path moved, a package was renamed, a trigger stopped firing).
- After a batch of skill edits, a tooling/path change, or a convention change in
  `CLAUDE.md`, to catch what drifted.

**When NOT to use:**
- Documenting/inventorying skills → `current-skills`.
- Assessing the user's *workflow* maturity → `reflect`.

## The Iron Law

```
EVERY referenced path, file, command, package, and constant is VERIFIED on disk.
NEVER hand a verification back to the user.
```

Writing "verify X exists" in a finding is the failure, not the finding. If you
named it, you check it — with the runtime's filesystem search, `Test-Path`, a
shell existence check, or an authoritative package lookup — and report it as
RESOLVED or BROKEN with the evidence. No exceptions:
not for "probably fine", not for "it's the user's machine", not for "out of
scope". You have the tools. Use them.

## Procedure

**Phase 0 — Assemble the rubric (main thread).**
- Discover the owned-skill set across **all five runtime surfaces** — never
  hardcode the list:
  - `~/.claude/skills/*/SKILL.md` (Claude Code home)
  - `~/.agents/skills/*/SKILL.md` (Codex and Kimi shared home)
  - `~/.kimi-code/skills/*/SKILL.md` (Kimi-native overlays)
  - `~/.gemini/config/skills/*/SKILL.md` (Antigravity IDE global home)
  - `~/.gemini/antigravity-cli/skills/*/SKILL.md` (Antigravity CLI global home)
- All five homes are folder-form. The Antigravity CLI root is **not** flat
  Markdown — globbing `*.md` there returns only its CLI-native router skill and
  hides every canonical skill junctioned into it, so the audit reports false
  absences. Most entries in the Claude Code and both Antigravity roots are
  directory junctions onto `~/.agents/skills/<skill>`; a junction is the same
  bytes as its target, so it can never diverge from canonical. Resolve each
  entry's shape before treating a same-named pair as two copies to diff.
- Decide ownership per skill by reading the YAML frontmatter of every discovered
  `SKILL.md`. The `owner: <your-org>` marker is the source of truth for
  your-org-owned skills:
  - **`owner: <your-org>` present** → owned; include in the deep audit.
  - **No `owner: <your-org>`** → not owned; include only in the full inventory
    for overlap awareness.
  - Do not infer ownership from path, voice, or conventions, and never add the
    marker to a third-party skill.
- Cross-check against `~/.claude/skills/current-skills/CurrentSkills.md` when it
  exists, but defer to the frontmatter marker:
  - A skill listed as local but missing `owner: <your-org>` is a metadata gap
    (flag it, do not promote it to owned).
  - A skill listed as plugin/built-in but carrying `owner: <your-org>` is a
    metadata error (flag it, do not demote it).
  - Treat firecrawl as owned only if its frontmatter has `owner: <your-org>`.
- Exclude non-owned skills from:
  - the scorecard
  - drift lists
  - the "missing skills" gap section
  - reliability/polish deep-audit findings
- Capture the **full session skill inventory** — every skill description,
  including non-owned/plugin/third-party skills — for the cross-skill overlap
  pass only.
- Read the applicable instruction files that exist for the current runtime
  (e.g., `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.kimi-code/AGENTS.md`).
  Record which governed each check.
- Verify the shared traps-docs plumbing. The canonical directory is
  `~/.agents/notes/`; every runtime notes directory must contain hard links to the
  same `*traps*.md` files. Check existence and link equality; report any drift as
  a reliability finding under `audit-skills` itself.
- Read the previous report (latest `SkillAudit-*.md` in
  `<vault>\Claude\SkillAudits\` — the Report path below) for the
  trend diff.
- Collect available utility evidence for each owned skill and record the source
  and observation window: explicit skill invocations or mentions in local
  session histories, recorded outcomes, prior reports, and git history showing
  continued maintenance or supersession. Session/token totals without
  skill-level attribution are not invocation evidence. Missing evidence is
  `insufficient-evidence`, never an invented zero.

**Phase 1 — Audit one owned skill per isolated worker.**
Use the runtime's native parallel-agent capability when available. Give each worker the
contents of `audit-brief.md` (in this skill's directory), the path(s) to its one
skill (across every surface where it exists), the full description inventory,
and that skill's utility evidence. Each subagent reads only its skill, verifies
every reference, scores the four axes, detects its own cross-home drift, and
returns the structured JSON the brief specifies. Run the same contract
sequentially if delegation is unavailable.

**Phase 2 — Synthesize (main thread).**
- Collect the JSON. **Dedupe cross-skill findings** — an overlap surfaces from
  both sides of the pair.
- Run the cross-skill pass the per-skill subagents cannot: trigger **overlaps**
  across the full inventory, coverage **gaps** that an owned skill should fill,
  dead/duplicate trigger phrases in owned skills, and reinvention of a plugin
  skill by an owned skill.
- Reconcile each utility grade into one lifecycle disposition: `keep`, `narrow`,
  `merge`, `archive`, `retire`, or `insufficient-evidence`. Frequency is never a
  verdict by itself: preserve rare high-impact capabilities, account for whether
  the observation window contained a realistic trigger opportunity, and prefer
  demonstrated outcomes over raw invocation counts.
- Keep lifecycle decisions out of the defect findings buckets. A sound but
  superseded skill can merit `retire` without being technically broken.
- Assign severities, compute each skill's per-axis grade and an inventory-level
  verdict, and diff against the previous report (fixed / regressed / still-open
  / new).

**Phase 3 — Write & deliver.**
- Render the report to the vault path below (create the folder if absent),
  normalized to CRLF.
- In chat, give only: the verdict, the scorecard table, and the top fixes; state
  the report path. The only action offered is pointing the user at the
  appropriate skill-editing workflow to fix a specific skill deliberately — make no edits.

## Severity model

- **🟥 Broken** — a reference does not resolve, or the skill cannot work as
  written.
- **🟧 Reliability** — won't self-trigger, violates active runtime instructions,
  or has cross-home drift.
- **🟨 Polish** — token bloat, a missing conventional section, a weak example.
- **🟩 Good** — no finding on that axis.

These four glyphs form a shared visual vocabulary with two distinct scales.
Reach/Implementation/Correctness use defect severity; Utility uses lifecycle
grade: 🟩 `keep`, 🟨 `insufficient-evidence`, 🟧 `narrow`/`merge`/`archive`, and
🟥 `retire`. Never read a Utility glyph as defect severity or vice versa. The
scales match the JSON contract in `audit-brief.md`. CLAUDE.md's no-emoji rule
carries a carve-out naming exactly these four for audit findings — it does not
extend anywhere else, so the report's prose, headings and commit messages stay
glyph-free.

Every worker result uses the closed grade vocabulary: 🟩, 🟨, 🟧, 🟥.

## Report

Path: `<vault>\Claude\SkillAudits\SkillAudit-YYYY-MM-DD.md`
(sibling of `reflect`'s `Reflections`). Today's overwrites on re-run. CRLF.

```markdown
# Skill Audit — YYYY-MM-DD

> Generated by audit-skills · <N> owned skills · <S> runtime surfaces

## Verdict
<One honest paragraph at inventory level. A clean bill is fine if earned;
bloat, rot, and drift get named plainly. Candor over comfort.>

## Scorecard
| Skill | Reach | Impl | Correctness | Utility | Top issue |
|---|---|---|---|---|---|
| <name> | 🟩 | 🟧 | 🟥 | 🟨 | <one line> |

## Findings
### Broken
- **<skill>** — <evidence: exact path/line/phrase> → <precise fix, described not applied>
### Reliability
- ...
### Polish
- ...

## Cross-skill
- **Overlap:** <skill A> vs <skill B> — <which triggers collide>
- **Gap:** <recurring need with no skill / unclaimed trigger>
- **Drift:** <skill present/diverged across homes>
- **Reinvention:** <skill duplicates plugin skill X>

## Lifecycle recommendations
| Skill | Disposition | Confidence | Evidence |
|---|---|---|---|
| <name> | keep / narrow / merge / archive / retire / insufficient-evidence | high / medium / low | <source + window + decisive signal> |

## Trend since <date>
- Fixed: ... · Regressed: ... · Still open: ...
(Omit this whole section on a first run.)

## Prioritized fixes
1. **<skill>: <change>** — impact <h/m/l> · effort <l/m/h>
```

## Quick reference

`/audit-skills` — inventory every installed skill, classify third-party vs owned,
score reach/implementation/correctness/utility, recommend an evidence-backed
lifecycle disposition, and write `SkillAudit-YYYY-MM-DD.md` to
`<vault>\Claude\SkillAudits\`.

## Common Mistakes

These are the exact baseline failures this skill prevents — do not repeat them:

| Mistake | Reality |
|---|---|
| "Verify that path exists on your machine" (handing it back) | The audit verifies it. Run `Test-Path`/`Glob` and report RESOLVED/BROKEN. |
| Checking only the references you happened to notice | Enumerate EVERY reference in the body, then check each. Partial = unreliable. |
| Judging the description by length/vibe | Check concrete triggers, intended capability, third person, and the 1,024-character limit; reject process summaries that let agents skip the body. |
| "Follows house conventions well" (asserted) | Open the active runtime instructions; cite the specific rule the skill honours or violates. |
| Reviewing skills in isolation | Cross-home drift and trigger overlap only show at inventory level (Phase 2). |
| Treating low invocation count as low value | Check trigger opportunity and outcomes; rare incident skills can justify their cost. |
| Guessing from general token/session totals | Only explicit skill-level evidence counts; otherwise report `insufficient-evidence`. |
| Free-form per-skill prose | Use the structured contract — incomparable output kills the trend trail. |
| Editing a skill you found a problem in | Report only. Fixing is a separate skill-editing workflow (Iron Law: RED test first). |

## Red Flags — STOP

- You're about to write "verify/confirm/check that … exists" as a *finding*.
- You graded a skill without running a filesystem or package check.
- You never opened the active runtime instruction files this run.
- You conflated Antigravity IDE with Antigravity CLI or ignored Kimi-native overlays.
- Two subagents' findings use different severity words.

**All of these mean: you skipped the work. Go verify.**
