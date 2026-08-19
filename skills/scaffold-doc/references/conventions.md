# Markdown house conventions

Read this for frontmatter, orientation, callouts, diagrams, symptom/cause teaching, and reproducible appendices.

## The five non-obvious conventions

These are the patterns baseline drafts consistently miss. Get these right and the rest follows.

### 1. YAML frontmatter — not a bold header block

Use a real YAML block only where the destination consumes frontmatter, not a
bolded `**Key:**` block. Obsidian vault notes and configured Jekyll/GitHub Pages
destinations consume it; an ordinary GitHub README and a README rendered by the
NuGet gallery do not, so omit it there.

```markdown
---
title: Acme Azure Audit
date: 2026-05-30
author: <actual human and/or runtime>
status: living document
last-updated: 2026-06-20
tags: [audit, azure, acme]
---
```

- `author` — vault docs and private notes only; **omit from repo-committed files** (a package README checked into source control should not carry a personal author line).
- `tags` — optional metadata for vault taxonomy, tag search, and graph filters. Tags alone do not decide visibility: untagged notes remain visible in the Obsidian Graph view by default, but Graph Search and a tag filter can exclude them, the Orphans toggle can hide unlinked notes, and excluded-file patterns keep matching files out of the graph. Add tags when a taxonomy or tag-based filter needs them. Use the consistent taxonomy: `audit`, `azure`, `dotnet`, `runbook`, `architecture`, `decision`, `review`, plus project name.
- `last-updated` — required when `status: living document`; update on every substantive revision.
- Domain keys when they aid retrieval: `tenant`, `account`, `subscription`, `repo`, `scope`.

### 2. Orientation blockquote and Obsidian callouts

**Orientation blockquote** — immediately after the H1, not buried at the end. Tells the reader scope, currency of data, and units. Plain `>` syntax:

```markdown
# Acme Azure Audit — 2026-05-30

> Snapshot of the **Acme** Azure estate as seen from `you@example.com`.
> All figures are **month-to-date (MTD)** actual cost in **USD**, pulled live via the
> Cost Management API on 2026-05-30.
```

**Callout blocks** — use these (not plain `>`) for warnings, notes, and tips within sections. Both GitHub (since 2023-12-14) and Obsidian render them distinctly. They are valid in **any Markdown that GitHub itself renders** — a repo README, an Issue, a PR body, a Discussion. They are **not** valid everywhere a repo-committed file ends up: see the README sub-template in [templates.md](templates.md#doc-type-sub-templates) for the one place (the NuGet gallery) they silently fail to render:

```markdown
> [!WARNING]
> This runbook deletes resources permanently. Verify the subscription before running.

> [!NOTE]
> All costs are MTD actuals in USD as of 2026-05-30.

> [!TIP]
> Run `az account set --subscription <id>` first to avoid operating on the wrong sub.

> [!IMPORTANT]
> If the App Service is recreated, delete the stale Key Vault role assignment before re-deploying.
```

GitHub supports: `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`. Obsidian supports all of these plus custom types. Use `[!WARNING]`/`[!CAUTION]` for destructive actions or data-loss risks. Use `[!NOTE]` for caveats, assumptions, or data currency. Use `[!TIP]` for shortcuts or non-obvious tricks. Use `[!IMPORTANT]` for critical setup or operational prerequisites. The orientation blockquote under the H1 stays as plain `>`; callout types are for inline annotation within sections.

### 3. Load-bearing mermaid — diagrams that carry information tables can't

> **Pick the renderer first.** This section is the *Mermaid* grammar — the default for
> repo-committed Markdown and vault notes. For a presentation, client-facing, or hero figure,
> invoke the `diagram-design` skill and commit its asset instead; see
> [diagram-renderers.md](diagram-renderers.md). Never hand-author branded SVG inside this skill.

Tables are not enough. Add a diagram wherever shape, hierarchy, or relationship is part of the message. Decoration is not the bar — *load-bearing* is. Three workhorses:

- **`pie showData`** for a distribution (cost by service, time by area, issues by severity)
- **`graph TD`** for hierarchy/topology (account → tenant → subscription → resource group; module tree)
- **`graph LR`** for relationships/flow (who calls what, data lineage, what-hosts-what)

Use node styling to make state legible: `stroke-dasharray` for absent/unreachable, a red `stroke` for the problem node, a `classDef` for dead/deleted items.

### 4. Symptom→cause section — name the confusion, then explain it

When the document exists because something is surprising or wrong, give that confusion its own section with a table mapping surface symptom to underlying cause. This is the section that makes the doc *teach* rather than just *report*. Scope: audit reports and runbooks. For READMEs, use a `## Troubleshooting` section with the same symptom → cause table shape.

### 5. Appendix of raw references — reproducible, untruncated

Close with an appendix carrying the full, copy-pasteable identifiers and exact commands or API endpoints used. Never truncate an ID (`1234abcd-…` is useless to the next person). For READMEs the appendix carries install commands and package IDs instead of internal infra IDs.
