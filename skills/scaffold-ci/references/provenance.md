# CI policy provenance

This appendix records dated measurements and incidents behind the actionable contracts.
The owning references remain authoritative for what to implement.

## Review guard and workflow hygiene

An automated rollout once emptied review-policy files across 21 repositories. The first
two-check guard still passed because an empty file remained tracked and unignored; the
shipped guard was expanded to validate JSON shape and load-bearing HIGH paths.

Workflow hygiene began as grep rules. On a pilot repository, patterns matched the
comments explaining themselves; later exclusions also misread quoted values, list-form
triggers, and digest pins. The stdlib parser replaced those greps on 2026-08-24.

A 2026-08 review-budget sample found 27 config-only diffs among 100 recent HIGH PRs but
only four actionable CodeRabbit comments, while 45 PRs received no verdict after the
account reached 73 reviews in seven days. Mechanical workflow checks replaced the broad
HIGH glob. A later review found the merge-barrier paths NORMAL in six repositories,
which is why those exact files remain HIGH.

## Mutation score correction

Before 2026-08-13 the summary used `killed / (total - ignored)`, omitting Timeout from
the numerator while retaining CompileError and RuntimeError in the denominator. One
A CI-backend report moved from 52.6% to 64.9% with no suite improvement. Two
identical-code classifier runs then scored 84.9% and 87.9%, with 63 of 892
mutants changing status in both directions; this is why threshold re-baselining needs two
runs.
