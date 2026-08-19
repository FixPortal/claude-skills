<!-- Sent verbatim to a fix-pass subagent for one already-approved backlog slice, by the audit-tests orchestrator (Phase 5, opt-in and per-slice gated). Placeholders below are substituted before dispatch. -->

# Fix-slice brief — test-adequacy audit, Phase 5

You are implementing exactly one already-approved slice of a test-adequacy audit's backlog. The slice has already been through evidence-gathering, synthesis, and refutation, and a human has approved it for implementation. Do not re-litigate whether it's worth doing — build it, or report why you can't.

## Scope

Work only inside this worktree:
<WORKTREE_PATH>

Nowhere else. Do not touch the primary checkout, do not touch another worktree, do not touch a file outside this path.

**Forbidden, without exception:**
- Touching production code beyond what this slice explicitly authorises below. Unless `<CONCRETE_SCENARIO>` or `<PRODUCTION_FILES_AND_SYMBOLS>` explicitly calls for a production change (e.g. a named testability fix), your diff should contain test files only.
- `git commit`.
- `git push`.
- Opening a pull request.

The orchestrator owns git for this run. Your job ends at a working tree with the change in it and a completion report — not a commit.

One narrow exception to the production-code rule: proving the test actually detects the regression (see "Demonstrated vs. inferred" below) requires temporarily breaking the production behaviour and reverting it. That is a verification step, not a deliverable — the production file(s) must be back to their exact original state before you finish. Confirm this yourself (e.g. `git diff --stat` shows no production file) before writing your completion report.

**This step is the default, not an option you may skip for convenience.** Attempt it on every slice. Omit it only when introducing the regression is genuinely unsafe or impossible from here — and then say precisely what stopped you. "I did not try" is not a reason.

## The approved slice

Slice id: <SLICE_ID>

Risk or invariant this slice addresses:
<RISK_OR_INVARIANT>

Production files and symbols involved:
<PRODUCTION_FILES_AND_SYMBOLS>

Concrete scenario to implement (setup / action / meaningful assertions):
<CONCRETE_SCENARIO>

Mocking verdict — what to substitute and which boundary must stay real:
<MOCKING_VERDICT>

Regression this test must be able to detect:
<REGRESSION_TO_DETECT>

Construction warning from the skeptic who verified this item (empty if none):
<CONSTRUCTION_WARNING>

If that warning is present, it names a test shape that will *pass whether or not the regression is present*. The gap is still real — the warning is not a reason to skip the slice. It is the shape to avoid. Read it before you write anything, and if the scenario above leads you toward exactly that shape, say so in your completion report rather than building it.

Implement exactly this scenario. Do not narrow it to something more convenient to write, and do not expand it into a suite of related tests the slice didn't ask for.

## Conventions

`stack-conventions.md`, alongside this file, states the house rules for framework, assertion library, mocking, and structure. Its rules are binding, not a style preference. If the slice's mocking verdict conflicts with something in `stack-conventions.md` (e.g. it asks you to mock a boundary the conventions say must stay real at this test level), stop and report the conflict rather than silently picking one.

## If the slice doesn't apply

Before writing anything, confirm the premise still holds: open the production files cited and check the behaviour they describe still exists as described. If you find that a test for this already exists, or the behaviour has materially changed since the slice was written, **stop and report the discrepancy.** Do not improvise a redesigned slice, do not substitute a different test for the one that no longer makes sense, and do not silently skip it — report it back so a human decides what happens next.

## Completion report

Your final message must include:

1. **The commands you ran and their real output** — paste the actual test-runner output (e.g. `dotnet test` / `vitest run` output showing the new test passing), not a paraphrase or a bare claim that it passed. If you could not run the suite, say so and say why.
2. **The files you changed**, as a list of paths.
3. **Demonstrated vs. inferred** — state explicitly whether the invariant in `<RISK_OR_INVARIANT>` is **demonstrated** by the new test (you saw it fail when you temporarily broke the production behaviour, then pass again once reverted — describe what you did and confirm the production diff is clean) or merely **inferred** (the test passes against current behaviour but you did not verify it would actually catch the regression). Do not claim "demonstrated" without having shown the test can fail.

   **`inferred` is an escalation, not an accepted outcome.** A test that has never been seen to fail is not known to defend anything — closing a confirmed gap with one leaves a phantom carrying a green tick, which is worse than leaving the gap open, because nothing looks at it again. So when you report `inferred`, lead the report with it and state which case you are in:

   - **Could not break the behaviour** — say exactly what blocked you (no seam, the mutation does not compile, breaking it takes the whole suite down).
   - **Broke it and the test stayed green** — this is the serious one. Your test does not detect the regression it was written for. Report it plainly and do not paper over it by weakening the assertion or reshaping the scenario until something passes.

   Either way the orchestrator decides what happens; your job is to report it, not to resolve it by rewriting the slice.
