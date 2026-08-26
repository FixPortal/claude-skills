# Adversarial Review — v2 methodology (all-frontier, subscription-backed)

Status: implemented v2 methodology. This document records the contract shared by
the wrappers, `reviewers.json`, the driver, and Observatory telemetry.

## Motivation

V2 is built on two changes:

1. **Every frontier vendor is now reachable on a flat-rate subscription**, not
   metered API credits — Anthropic (Claude Max 20x, incl. Fable in perpetuity),
   OpenAI (ChatGPT Pro 20x via the Codex CLI), Moonshot (Kimi Allegretto via the
   Kimi Code CLI), Google (Gemini via Google One). Cost stops being a design
   constraint; methodology quality is the only axis.
2. **Kimi Code and Codex are headless agentic CLIs** (`kimi -p`,
   `codex exec`) — direct analogues of `claude -p`. So a second and third
   non-Anthropic vendor can now walk the repository, not just read the diff.

V2 addresses two structural weaknesses in the v1 panel:

- **Repo-blind abstention.** Only the Anthropic reviewers had repo access; the
  cross-vendor reviewers (Gemini, OpenAI-API) abstained ("needs evidence")
  whenever a mechanism lived outside the diff. Those abstentions masqueraded as
  doubt at adjudication.
- **Judge and verifier were an Anthropic monoculture.** The two most
  decision-heavy steps — Phase-3 adjudication and Phase-4 verification — ran on a
  single vendor, re-correlating the error the panel exists to decorrelate.

## Panel roster (5 reviewers / 4 vendors)

| id | label | vendor | primary wrapper | fallback wrapper | repoAccess |
|----|-------|--------|-----------------|------------------|------------|
| B  | Claude Sonnet | anthropic | `claude` (Agent tool under Claude Code) | — | yes |
| F  | Claude Fable 5 | anthropic | `claude` | — | yes |
| X  | GPT (Codex) | openai | `codex` (ChatGPT Pro sub) | `openai` (API) | yes (sandbox read-only) |
| K  | Kimi (K2.7 Standard) | moonshot | `kimi` (Allegretto sub) | — | no (hermetic; see note) |
| G  | Gemini | google | `agy` (paid Google plan) | — | no (diff + `-ContextPath`) |

- Consensus is **vendor-weighted**: Anthropic (B+F) = one vote; OpenAI, Google,
  Moonshot one each → **four vendor votes**. B+F telemetry merges into one
  `anthropic/reviewer` row, as v1.
- **Three of five finders are repo-aware** — B, F (Claude, hard read-only plan
  mode) and X (Codex, hard read-only sandbox). Gemini and Kimi stay diff-blind,
  fed the key files via `-ContextPath`. Kimi ships blind deliberately: Kimi Code
  has no per-invocation read-only flag (global mode is `yolo`), so pointing it at
  the repo is a trust-boundary risk the hard-sandbox reviewers don't carry. The
  invariant is non-negotiable: a wrapper with no hard per-invocation read-only
  mode never gets repo access, in any role — do not flip `repoAccess:true` for
  one; prompt plus git-tree is not a guard. This still fixes v1's repo-blind
  abstention (v1 had only Anthropic repo-aware; v2 adds Codex).
- **The wrapper explicitly pins `kimi-code/kimi-for-coding`** (K2.7 Coding,
  Standard), independent of the user's current CLI default. It previously used
  `-highspeed`, but that variant
  bills ~3x the credits for equivalent review output (the highspeed multiplier,
  not extra work), so a modest panel burned ~30% of the weekly allowance; Standard
  is the credit-sane default. `kimi-code/k3` (1M context, deeper) is a DISTINCT
  model — not the Standard tier of K2.7 — and was capacity-congested at its
  mid-Jul 2026 launch; swap to it per chunk only if the 1M window is needed, or
  to `-highspeed` only when speed is worth the 3x burn.
- The judge stays **Opus** (Anthropic) — one coherent adjudicating voice, whose
  inputs are already four-vendor. Reviewer≠judge decorrelation is preserved
  (Opus never reviews).

## Where Kimi sits, and why

Kimi is placed where it fixes v1's weaknesses, not merely as a fifth voice:

1. **Diff-blind Phase-1 finder** (with `-ContextPath`) — a fourth vendor whose
   errors decorrelate from the other three. (Design intent was repo-aware, but it
   ships blind for the yolo trust-boundary reason above; Codex is the
   non-Anthropic vendor that carries the repo-aware role instead.)
2. **Phase-4 verifier pool member** — see below; it breaks the Sonnet-only
   verification monoculture with an agentic, repro-constructing skeptic from a
   different vendor.

## Subscription-first, API-fallback

`reviewers.json` uses a `fallbackWrapper` field. The driver resolves a
reviewer's wrapper as: **try `wrapper` (the sub-backed CLI); on non-zero exit
(CLI missing, not logged in, sub lapsed) fall back to `fallbackWrapper` (the API
path) and mark the run degraded-to-API for that vendor.** The v1 API wrappers
(`openai-review.ps1`, `gemini-review.ps1`) are retained on disk, but only OpenAI
is wired as an automatic fallback. The retired Gemini CLI path is dormant for a
possible deliberate API re-enable.

Only OpenAI carries a fallback today (`codex` → `openai`). Google runs through
Antigravity (`agy`) with no fallback; Kimi is also sub-only. Anthropic runs in-process
via the Agent tool under Claude Code (no fallback needed).

## Wrapper contract

Every wrapper declares this required minimum:

```
-Instruction <text>
-DiffPath <file>
-FindingsPath <file>
-ContextPath "a;b;c"
-Model <id>
```

`-InstructionPath`, `-Effort`, `-RepoPath`, `-OutPath`, and
`-UsageSidecarPath` are optional capabilities. The driver introspects them and
passes only supported flags. Every wrapper returns review text on stdout and a
non-zero exit on failure.

Each wrapper also declares two pre-flight header tokens, enforced by the
contract test for every wrapper an enabled reviewer can reach:

- `PREFLIGHT_COMMAND: <command>` — the exact probe the host runs before
  fan-out (typically an auth/version check against the CLI).
- `PREFLIGHT_SUCCESS: <text>` — the output the host accepts as passing.

The host executes them; `run-review.ps1` never parses the headers, so a wrapper
without them is unverified, not passing, and results are recorded into
`preflight.json` in the run root (see SKILL.md, Pre-flight).

Read-only and hermetic: `codex exec --sandbox read-only`; Kimi (`kimi -p`, which
cannot combine with `--plan`) is run hermetically instead — throwaway scratch cwd,
copied context, repo not in the workspace, prompt forbids mutation;
`claude --permission-mode plan`. Repo access, when granted, is read-only
(`--add-dir` / `--add-dir` / `-RepoPath`).

### Cost & tokens under subscriptions

Sub-backed calls are flat-rate, so **real per-token cost is ~0**. Telemetry
therefore reports **putative cost** (the v1 treatment for Claude), computed from
best-effort token counts extracted from each CLI's JSON output
(`codex exec --json`, `kimi --output-format stream-json`, `claude -p
--output-format json`). V2 added registry-backed pricing and an explicit
unknown-cost state because unavailable pricing and zero marginal subscription spend are
different facts. The live lookup and rendering policy now sits in `SKILL.md` beside the
emission rules. Collectors recorded zero tokens when a CLI exposed no usage (including
`agy`), without changing outcome telemetry (issuesRaised / issuesAccepted).

## Phase design

### Phase 1 — blind independent find (5 reviewers, parallel)
Kimi (K) participates; X (Codex) is repo-aware, while K (Kimi) is
diff-blind (hermetic; fed `-ContextPath`). Gemini via Antigravity remains
diff-blind with `-ContextPath`. Each reviewer is blind to the others.

### Phase 2 — cross-examine (same 5, parallel)
Unchanged. All five attack the pooled, anonymised findings.

### Phase 3 — adjudicate (Opus judge)
Unchanged. Vendor-weighted consensus over four vendors. Judge reads the repo to
settle contested mechanisms.

### Phase 3.5 — judge-audit (mandatory on merge-gating runs)
A single cross-vendor pass (default a non-Anthropic vendor — Kimi or Codex)
that audits the Opus judge's report for: findings silently dropped between the
pooled set and the report, severity mis-rating vs the evidence, and consensus
tags that don't match the vendor split. It does **not** re-review the code; it
checks the adjudication against its own inputs. Output: a short list of
`{findingId, issue, suggested correction}` the host folds back before Phase 4 —
DROPPED corrections carry a complete house-style finding block and fold
unconditionally; demotions route back to the judge. Mandatory (not merely
recommended) whenever the review gates a merge or the target is HIGH-tier under
the repo's review policy — the same tier signal the review-policy gate uses.
Otherwise the host runs it when the user asks. There is no driver flag:
`run-review.ps1` stops at the judgment boundary, so Phases 3 onward belong to
the host and a flag on the driver could never reach this phase.

The panel's multi-vendor inputs do not make it redundant. Those cover Phases 1-2;
Phase 3 is a single judge, and the one stage that can lose a finding outright.
Phase 4 cannot cover for it either — it only sees findings that reached the
report, verifies only Criticals/Highs/contested, and never inspects consensus
tags, so dropped, demoted and mislabelled findings all pass it untouched.

### Phase 4 — verify (NOW cross-vendor pool)
Every Critical, every High and every contested finding is verified by a fresh
agent that took no part in the report. v2 draws verifiers from a **cross-vendor pool**
— Sonnet, Kimi, Codex — assigned round-robin by vendor, so no single vendor
owns verification. For a finding with more than one failure mode, assign
**diverse lenses** across vendors (correctness / security / does-it-reproduce).
Verifiers are agentic and construct repros where cheap. Verdicts fold back
exactly as v1 (CONFIRMED / REFUTED / INDETERMINATE, additive annotations).

## Telemetry (Observatory)

The controller owns the live emission, attribution, and unknown-cost rules. The
Observatory schema was designed around participant-and-role identity because it upserts
on `(runId, reviewer, role)`; a repeated identity replaces that row. Attribution was
based on pooled Phase-1 provenance so the dashboard measures what each vendor found,
not which consensus labels it later supported. Unknown-cost state exists separately
from numeric cost because subscription usage and missing registry prices cannot safely
be represented by the same zero.

## Files

Canonical skill (`~/.agents/skills/adversarial-review`), surfaced to other
runtimes through their configured junctions/discovery roots:
- `codex-review.ps1`, `kimi-review.ps1`, `agy-review.ps1`
- `reviewers.json` — roster + `fallbackWrapper` + `moonshot` wrapper mapping
- `emit-review-telemetry.ps1` — `moonshot` in ValidateSet
- `run-review.ps1` — fallback resolver; roster already data-driven
- `briefs/phase3.5-judge-audit.txt`; `briefs/phase4-verify.txt` (note the pool)
- `SKILL.md` — roster, prerequisites, phase procedure, telemetry, cost
- retained legacy/API paths: `openai-review.ps1`, `gemini-review.ps1`

Your observability service, wherever telemetry lands (separate repository, its own PR).
Adding a vendor touches four places there, whatever they are called in your codebase:
- the provider enum or lookup its data layer persists — add the new vendor
- the runs endpoint / review service — accept the new vendor's identifier
- the web grouping component and its API client — widen from N to N+1 vendors
- the label and colour map, plus its test

## Non-goals / guardrails

- No transcript/DOM scraping. Every vendor runs headless via its CLI; the
  Observatory ingests telemetry, never transcripts.
- No retiring of the API wrappers — they remain the documented fallback.
- Opus stays judge-only, never a blind reviewer (preserves reviewer≠judge).
