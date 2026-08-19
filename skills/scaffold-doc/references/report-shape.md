# Audit and report shape

Read this for supplied audit findings, cost reports, technical reports, and runbooks.

## Patterns that should already be habit

Confirm these are present; they rarely need teaching:

- **Lead with the conclusion.** Executive summary opens with the headline number/finding and the *why*. Inverted pyramid, not a slow build.
- **Plain-English column in every data table.** Name it after what it contains (`Description`, `What it tests`, `Why`, `Status`) — never leave a row decodeable only from a bare identifier. Right-align numeric columns (`---:`).
- **Actions-taken ledger** (audit/report docs only — not READMEs). Table of what changed (action · target · result), deferred items included. Plain-text status markers (`[deleted]`, `[confirmed]`, `[deferred]`), no emoji.
- **Priority-ordered recommendations**, biggest lever first.

## Document skeleton (audit/report)

Full report-style, in order. README and ADR use their own sub-templates, in [templates.md](templates.md#doc-type-sub-templates).

Use this skeleton with its frontmatter block only for a parser-backed
destination, such as an Obsidian vault note or configured Jekyll/GitHub Pages
site. Ordinary repo/GitHub reports must omit the frontmatter block because
their standard renderer does not consume it.

```
---  frontmatter (title, date, author, status, last-updated, tags)  ---
# Title — date
> orientation blockquote (scope · currency · units)
## Executive summary        ← lead with the number + why
## <Data section>           ← tables (right-aligned numerics, description column)
   ```mermaid pie / graph```  ← load-bearing diagram
## <Per-item catalogue>      ← one subsection per major item, each self-contained
## Symptom→cause explanation ← if the doc exists to resolve a confusion
## Notable findings          ← numbered, surprising-first
## Recommendations           ← priority order, biggest lever first
## Actions taken             ← ledger: action · target · result
## Appendix — raw IDs / commands  ← untruncated, reproducible
```
