# AGENTS.md

Repo-specific conventions for the public Claude Code skills portfolio. Global
agent rules live in the runtime homes (`~/.claude/CLAUDE.md` etc.) and are not
repeated here.

## Public-repo constraints

- Everything in this repo is world-readable. Never commit machine-specific
  paths, client names, or personal vault locations — use the established
  placeholders (`~/.claude/...`, `<vault>`, `<workdir>`, `you@example.com`,
  `Acme`). The `verify-*.ps1` scripts fail the build on leaked Windows
  user-profile or drive-root path tokens.
- Skills here are a sanitised subset of a larger private working set. Sync
  from the private canonical copies with `sync-private-skills`; do not edit
  the public and private copies independently.

## Skill shape

- Each skill is a folder under `skills/` with a `SKILL.md` carrying YAML
  frontmatter: `name` (must equal the folder name) and `description`
  (≤ 1024 chars — the Copilot limit; third-person, trigger-phrase led).
- `SKILL.md` must resolve support files relative to its own loaded skill
  directory, never via a hardcoded `~/.claude/skills/<name>` path.

## CI contract

- `ci.yml` runs every `skills/**/test/verify-*.ps1` (except
  `verify-collect.ps1`, an estate integration skeleton with intentional
  `<repos-root>` placeholders that cannot run standalone). A new or changed
  skill must keep its verifiers green; run them locally with pwsh before
  pushing.
- Workflows are linted by `raven-actions/actionlint` (SHA-pinned,
  `shellcheck: true`) as the first validation step of every job.
- `.claude/review-policy.json` is the review control plane;
  `review-policy-guard.yml` asserts it stays tracked and unignored. Do not
  re-add `.gitignore` to its `high` list without removing that guard.
