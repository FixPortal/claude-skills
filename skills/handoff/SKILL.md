---
name: handoff
description: Use when work must cross a session boundary and context will be lost. Triggers — "/handoff", "hand this off to Codex", "I'm out of usage, move this to another agent", "I need to reboot, save where we are", "pick this up in a new session".
---

# Handoff

## Overview

Context does not survive a session boundary, and the artefacts normally left
behind are lossy: git records what changed but not what was tried and
rejected; memory records durable facts but excludes ephemeral state — the
half-finished thought, the one command that was about to run. `handoff`
writes the missing artefact, and writes it BEFORE the loss, not after.

It is not `close` (which parks a session and persists durable memory for
*this* agent to find later) and not `recap` (which reconstructs "where were
we" from cold artefacts once memory is already gone). Those run after the
fact; `handoff` writes the brief before the context is lost. `handoff` produces
one thing: a brief a *different* session — possibly a different agent entirely —
can pick up cold, plus one resume line to invoke it with.

Canonical in ~/.agents/skills/, junctioned into ~/.claude/skills/,
~/.gemini/config/skills/, and ~/.gemini/antigravity-cli/skills/ — keep it
host-agnostic and MCP-free.

## Modes

| Invocation | Direction | Rules-diff |
|---|---|---|
| `/handoff codex` | this host -> Codex CLI | runs |
| `/handoff antigravity` | this host -> Antigravity / Gemini | runs |
| `/handoff claude` | this host -> Claude Code (run this *from* Codex) | runs |
| `/handoff kimi` | this host -> Kimi Code | runs |
| `/handoff copilot` | this host -> Copilot CLI | runs |
| `/handoff self` | this host -> fresh session, same host | skipped |
| `/handoff` | unknown | ask, then proceed |

The source is whichever agent is running this skill right now; the target is
the argument. Neither is baked into this file — resolve both at runtime. If
invoked bare, ask which target before doing anything else, then run the full
procedure below for the answer given.

## Procedure

### 1. Resolve the target and read its rule file

| Target | Rule file |
|---|---|
| Claude Code | `~/.claude/CLAUDE.md` |
| Codex | `~/.codex/AGENTS.md` |
| Copilot CLI | `~/.copilot/copilot-instructions.md` |
| Kimi Code | `~/.kimi-code/AGENTS.md` |
| Antigravity / Gemini | `~/.gemini/GEMINI.md` |

Codex and Copilot CLI are separate targets with separate rule files — do not
read one and assume it covers the other.

Read it at runtime — do not recall it from memory or from this session's own
rule file. Do not assume the rule files have reached parity; they have not,
and closing that gap on every handoff is why this step exists. Where the
target has no rule file, say so plainly in the brief rather than implying a
coverage that does not exist.

### 2. Gather git state — read-only

If no repository is in scope, this is an estate handoff: skip Git and PR discovery.
Fill the brief's state with these honest values:

- Repository: `estate`
- Branch: `none`
- Worktree: `none`
- Working tree: `N/A`
- Unpushed commits: `N/A`
- Open PR: `N/A`

Otherwise gather the repo name, branch, whether the cwd is a review worktree,
`git status --short`, unpushed commits (`git log '@{u}..HEAD' --oneline` or note
the branch has no upstream), and the open PR if `gh` is available and authenticated.

This step never writes: no commit, no stash, no push, no clean. A dirty tree
is reported so the receiver knows what they are inheriting; it is not
resolved on the receiver's behalf.

### 3. Establish the task from the conversation

Not from git — from what actually happened in this session: the goal; what
is done; the ONE concrete next action (a command or an edit, not a plan);
dead ends; decisions already made. If the next concrete action cannot be
stated, say so — "I do not know what comes next, here is where I got stuck"
is a usable handoff; an invented next step is not.

### 4. Diff the rules

Work out which convention areas this task actually touches — PR flow, review
worktrees, testing stack, EF Core, Azure/CI, QuickFIX/n, npm, Windows shell
selection, whatever is live for this task. For each one, check whether the
rule file read in step 1 already covers it. Inline only the gaps — the
target's existing coverage needs no restating. Skip this step entirely for
`self`: same host, same rule file, inlining it would be pure noise.

### 5. Recommend a model

| Task shape | Tier | Reasoning effort |
|---|---|---|
| Mechanical — exact-string edits, renames, executing a fully specified plan | `mechanical` | `low` |
| Implementation needing codebase understanding | `workhorse` | `medium` |
| Architecture, novel design, adversarial review | `frontier` | `high` |

Never name a model from memory or inspect raw roster slugs. Resolve the canonical
tier through `model-registry` at handoff time:

```text
python <skills-home>/model-registry/resolve.py --tier <tier> [--vendor <vendor>]
```

Use a vendor filter only when the target fixes the vendor (Claude → Anthropic,
Codex → OpenAI, Kimi → Moonshot, Antigravity → Google). Copilot remains tier-only
unless its current rule file defines a vendor. If resolution returns no model,
recommend the tier and say no available match was found. For a Claude tool surface,
translate a resolved family to its supported short alias as documented by
`model-registry`; do not pass a full API ID where the host accepts aliases only.

Routing facts that outlive any roster live in
`~/.agents/notes/model-routing-traps.md` — which vendor CLI fails where, and why.
Read it here rather than restating its contents, so the two cannot drift apart.
That applies to entry 1 in particular: it has already been corrected once, so read
its current status before routing around any vendor CLI and **do not assume it still
means what it meant** when it was written.

A written brief is the handoff mechanism because context does not survive a session
boundary — not because any particular CLI cannot be invoked. That reason holds
whatever entry 1 says this week.

Recommend the tier the task warrants. Do not add an approval caveat for the
`frontier` tier — read the target's rule file (step 1) for whatever gating it actually
states today, and say nothing if it states none.

### 6. Write the brief and hand off

The output is a file, always, at a fixed, predictable path — never chat text.
When a repository is in scope, use `<repo>/.claude/handoff`. No repository is in scope
means an estate handoff: use the stable estate key `estate`, not
the cwd or host name, and `~/.agents/handoff/estate`.

In PowerShell, construct these paths with `Join-Path` — PowerShell 5.1 has no
path-safe string interpolation shortcut:

```powershell
$estateKey = 'estate'
$estateHome = Join-Path $HOME '.agents'
$estateHandoffRoot = Join-Path $estateHome (Join-Path 'handoff' $estateKey)
$handoffRoot = if ($repoRoot) { Join-Path $repoRoot (Join-Path '.claude' 'handoff') } else { $estateHandoffRoot }
$datedBrief = Join-Path $handoffRoot "$date-$slug.md"
$datedTemp = Join-Path $handoffRoot ".$date-$slug.md.tmp"
$latestBrief = Join-Path $handoffRoot 'latest.md'
$latestTemp = Join-Path $handoffRoot '.latest.md.tmp'
```

Run this one twin-update procedure. The temporary files are siblings, so their
renames are atomic; do not overwrite an existing dated brief — choose a new
slug instead:

```powershell
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null
Set-Content -LiteralPath $datedTemp -Value $brief -Encoding UTF8
[System.IO.File]::Move($datedTemp, $datedBrief)
Copy-Item -LiteralPath $datedBrief -Destination $latestTemp
if (Test-Path -LiteralPath $latestBrief) {
    [System.IO.File]::Replace($latestTemp, $latestBrief, $null)
} else {
    [System.IO.File]::Move($latestTemp, $latestBrief)
}
if ((Get-FileHash -LiteralPath $datedBrief).Hash -ne (Get-FileHash -LiteralPath $latestBrief).Hash) {
    throw 'latest.md differs from the dated brief; repeat only the pointer update'
}
```

The dated brief is authoritative. If `latest.md differs from the dated brief`,
retain the dated file and repeat only the temporary-pointer update; never
overwrite the dated brief. A failed pointer update is therefore recoverable,
and the resume line is printed only after the hashes match.

`latest.md` is a **replacement**, not an addition: the previous pointer is gone
once it lands, and another session may be relying on it to resume. Writing a new
dated brief needs no permission — it only adds a file — but replacing an
existing `latest.md` does. When one is already present, say which brief it
currently points at and get explicit approval before the replace, unless the
request already authorized the handoff write (`/handoff`, "write the handoff",
"hand this off to X" all do). Never replace it as a side effect of a request
that only asked for a summary.

Briefs are session ephemera and must never reach a PR, so confirm the directory
is ignored — but test whether it is *ignored*, not whether it is *listed*:

```text
git -C <repo-root> check-ignore -q .claude/handoff/
```

Pass `-C <repo-root>` explicitly: `check-ignore` resolves its path against the
current directory, so running it from a subdirectory tests the wrong path,
reports the brief directory as unignored, and walks you into adding the very
`.gitignore` entry this step exists to avoid.

Exit 0 means ignored; do nothing. Only if that fails does `.gitignore` need a
new entry. A repo whose `.gitignore` is a fail-safe allow-list (`/*`, `/.*`)
already ignores the directory without naming it — appending a redundant rule
there would dirty a tracked file on the very branch you are about to hand over.
For the estate location, no repository is in scope, so there is no `.gitignore`
check or repository mutation.

Use this template. Every heading is a required slot; an empty slot gets an
honest "none" or "unknown", never padding:

```markdown
# Handoff: <source> -> <target>
**Date:** YYYY-MM-DD · **Repo:** <name or `estate`> · **Branch:** <branch or "none"> · **Worktree:** <path, "primary", or "none">

## Task
<goal, one or two sentences>

## State
- Working tree: <clean | N files modified, listed>
- Unpushed commits: <none | list>
- Open PR: <none | #N title, status>

## Done
## Next  (one concrete action — a command or an edit, not a plan)
## Dead ends  (tried and rejected, with the reason)
## Decisions already made

## Rules the target is missing
<only the gaps, only for areas this task touches. Omit entirely for `self`.>

## Traps that apply
<excerpt + pointer to the source agent's notes directory for the active runtime
(~/.agents/notes/*-traps.md).
Excerpt, do not dump.>

## Model recommendation
<tier, roster-bound name or an honest "roster unreadable", plus caveats>
```

Then print the resume line, with the brief's **absolute** path — the receiving
CLI may not start in the repo root, and a receiver that cannot resolve the path
cannot read the brief that would have told it where the brief is:

```text
read <workdir>\repo\.claude\handoff\latest.md and continue
```

## Red flags — STOP

- You are about to write a model name you did not read from a roster file.
- You are about to inline `CLAUDE.md` wholesale instead of diffing what the
  target already has.
- You are writing the brief into the chat instead of to a file. It dies with
  the session — that is the whole failure this skill exists to prevent.
- You cannot state the next concrete action and you are about to write a plan
  to cover for it.
- You are about to commit, stash, or push to "tidy up before the handoff".
  Report the dirty tree; do not resolve it.
