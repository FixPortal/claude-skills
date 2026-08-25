# Choosing the diagram renderer

Read this before drawing anything. Two renderers are available and they are not interchangeable.

## Route by what the figure is FOR, not by where the file is stored

The first cut of this rule routed on destination — Mermaid for repo-committed Markdown, `diagram-design` for decks. It was wrong, and it was wrong in a specific way worth remembering: it sent a walk-someone-through-it architecture guide to Mermaid purely because the file lived in `docs/`. Storage location is not the signal. Ask what the figure has to do.

| The figure's job | Renderer | Why |
|---|---|---|
| **Track a moving target.** It describes code that changes, it is edited in the same pull requests, and its readers are the people maintaining it. | **Mermaid**, fenced inline | Diffs as text, so a reviewer sees exactly which edge changed; renders natively on GitHub; follows the reader's light/dark theme with no extra work |
| **Land with a reader who is not the author.** Onboarding, an architecture guide, hand-over or interview material, a client-facing summary, a talk, a hero figure. | **`diagram-design` skill** | Deliberate layout, brand skin, enforced focal hierarchy and node budget. Comprehension *is* the deliverable, and it wins the trade |

A repo-committed Markdown document can be either. A README whose one diagram is a module tree nobody reads twice is the first row. A `docs/` guide written so someone can explain the system out loud is the second — and living in `docs/` says nothing about which.

**When the rows pull in different directions, ask what the document is for.** If a reader opens it to *understand the system* rather than to *maintain the description of it*, the figure is doing communication work. Spend the hour.

> [!NOTE]
> The node budget is part of the value, not a tax on it. Being pushed under nine nodes reliably
> surfaces that some box was standing in for a label, or that two boxes were always one thing. Those
> edits improve the Mermaid version too, so the exercise is worth running even when the answer is
> row one.

Invoke `diagram-design` through the Skill tool. **Never hand-author branded SVG inside `scaffold-doc`** — that skill owns the skin, the focal rule, the connector grammar and three checkers this one does not have. If `diagram-design` is not installed in the environment you are running in, fall back to Mermaid and note the substitution in the document — the routing table above still applies.

## Mixing them in one document

A `diagram-design` figure is a committed SVG or PNG asset referenced by path. It does not render from a fence, so it cannot be the default for a document that will be edited.

Promoting a single figure is the supported pattern, and usually the right one:

1. Regenerate that one figure through `diagram-design`.
2. Commit the asset beside the document.
3. Keep the Mermaid source in the file as the maintained version.

Do not convert a whole document. The cost is per-figure and so is the benefit.

## Three constraints before choosing `diagram-design`

**Single-theme.** Generated files carry literal hex values, so a figure commits to light or dark. In a theme-aware page it needs a pinned plate behind it, or two maintained files per figure. A Mermaid fence has no such problem.

**Nine-node budget, enforced.** Usually a feature rather than a limit: being pushed under it tends to surface that a node was standing in for a label, or that two boxes were really one. But it will force an edit, so do not reach for it when the diagram genuinely needs to be dense — split it instead.

**Cost.** Roughly an order of magnitude more authoring effort than a Mermaid fence, because every coordinate is placed by hand on a 4px grid. Spend it where the figure is the deliverable rather than documentation of a moving target.

## Validating either one

| Renderer | Check | Command |
|---|---|---|
| Mermaid | It parses | `npx -y @mermaid-js/mermaid-cli@11.16.0 -i d.mmd -o d.svg` (exit 0 = parses; **pin the version**) |
| `diagram-design` | Accessibility contract, single-file safety | `python <skill-dir>/scripts/self_check.py <file>` |
| `diagram-design` | Geometry collisions — label masks over nodes, overlapping connectors | `python <clone>/scripts/verify-geometry.py <file>` |
| `diagram-design` | Skin conformance against the brand token set | `python <clone>/scripts/lint-skin.py <file>` |

> [!NOTE]
> On Windows, `diagram-design`'s `mermaid_extract.py` fails on the default console encoding —
> `UnicodeEncodeError: 'charmap' codec can't encode character '⏎'` — because its digest emits a
> line-break glyph cp1252 cannot represent. Set the encoding in the same call, using the syntax of
> the shell you are actually in:
>
> - PowerShell — `$prev = $env:PYTHONIOENCODING; try { $env:PYTHONIOENCODING='utf-8'; python <script> <file> } finally { $env:PYTHONIOENCODING = $prev }`
>   (a bare `$env:PYTHONIOENCODING='utf-8'; python ...` mutates the caller's session;
>   the `try`/`finally` scopes it to the one call)
> - cmd.exe — `set PYTHONIOENCODING=utf-8 && python <script> <file>`
> - bash — `PYTHONIOENCODING=utf-8 python <script> <file>`
>
> The bare `VAR=value <command>` prefix is POSIX-only: PowerShell rejects it as a parse error and
> cmd treats it as a literal argument. Windows is the primary shell here, so reach for the
> PowerShell form first.
