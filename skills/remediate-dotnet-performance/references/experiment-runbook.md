# One-experiment runbook

```text
published finding
  -> explicit experiment approval
  -> audited HEAD check
  -> isolated worktree
  -> baseline correctness + measurement
  -> one candidate change
  -> candidate correctness + measurement
  -> boundary check
  -> accepted | rejected | inconclusive | blocked
  -> documentation and cleanup
```

## Gates

1. Validate the immutable audit manifest with `test-performance-manifest.ps1 -Mode Finding -FindingId PERF-NNN`. Select one exact unresolved finding and preserve its repository path, audited SHA, project/files/symbols, workload and baseline, attributed mechanism, materiality threshold, correctness invariants, one proposed experiment, exact commands, tools/artifacts, cost inputs, conditions, rollback expectation, and boundary.
2. Obtain explicit user approval that names that finding and its one proposed experiment. Blanket or sweep approval does not authorize any experiment. Do not infer approval from a request to optimise, prior approval, or an accepted sibling finding.
3. Compare the target's current HEAD with the audited SHA and confirm the workload, dependencies, runtime, configuration, and mechanism still apply. Drift stops the experiment for a comparable re-baseline or a fresh audit decision; never compare a stale audit baseline with a new candidate.
4. Use only `<repo>\.claude\worktrees\performance-experiments`, with one branch such as `performance/perf-001-short-slug` from the verified baseline. Check `git worktree list` and `git status` there. Existing work or an active experiment blocks reuse until completed or explicitly abandoned. Do not create a second worktree, layer on another finding, or branch from an existing experiment.
5. Record baseline correctness first: behavioural outputs and side effects, ordering/concurrency, cancellation/exceptions, ownership, compatibility, precision, and the smallest relevant existing checks. Add a focused characterisation test only when protection is missing and the candidate has non-trivial new behaviour.
6. Run the exact baseline workload and retain raw output. Build/configuration, inputs and hashes, runtime/SDK, machine/resources, warm-up, repetitions, duration, diagnostics, and command must be comparable with the candidate. Release measurements run without a debugger.
7. Make one product-code change for the approved causal hypothesis. No refactor, benchmark-methodology change, second optimisation, or follow-on attempt is covered by the first approval.
8. Run the identical correctness checks and equivalent candidate workload; retain raw output before synthesis. Compare distributions, variance/noise, applicable resource displacement, and the stated practical materiality threshold. Run `test-managed-product-boundary.ps1` against the candidate diff and read the diff. For every warning, record an explicit disposition with evidence and rationale; no warning may be silently accepted. Then run every applicable normal repository build, test, lint, and analyzer gate. Record each exact command and result; no failed gate can be accepted.

## Decide, document, clean up

`accepted` requires passing focused correctness, boundary, and every applicable normal repository build/test/lint/analyzer gate; comparable evidence; material benefit above noise/variance; causal plausibility; and acceptable displaced costs and maintenance risk. Only then leave the product change ready for the repository's normal workflow.

`rejected` applies to a regression, correctness failure, boundary violation, neutral or immaterial result, or unacceptable complexity. `inconclusive` applies when stability, workload fidelity, or attribution cannot support a decision. `blocked` applies when required tooling, environment, authority, or a correctness seam is unavailable. Preserve external evidence for all outcomes. For rejected or inconclusive candidates, remove only the experiment-owned change from the experiment branch/worktree; do not broadly reset, clean, or touch unrelated work. A blocked record states whether a candidate exists and its exact safe disposition. Never turn rejection, uncertainty, or a block into a second code change under the same approval.

Create the external record for every result. Add `docs/performance/YYYY-MM-DD-<sweep>.md` only after acceptance. Keeping a benchmark is a separate post-acceptance user decision: retain it only with explicit approval and a stable, materially important hot path; do not add an automatic CI gate.
