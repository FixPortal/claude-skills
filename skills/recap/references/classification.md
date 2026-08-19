# Recap Classification

Every forward candidate needs current primary evidence: a live code marker, a
repository planning document, an open PR, or a memory body read during this
run. Tag the resulting item with `[code]`, `[doc]`, `[pr]`, or `[memory]`.

## Buckets

- **Actionable Now**: concrete work startable in this repository during this
  session with no blocker. Order prerequisites and high-leverage work first.
- **Deferred**: intended work in this repository that is parked, sequenced
  behind local work, or locally blocked.
- **Unverifiable**: work in another repository whose status remains unknown
  after a reasonable attempt to inspect that repository.
- **Operator Gated**: requires human action outside the codebase, such as an
  approval, live-environment smoke test, manual deployment, or credentialed
  operation the agent cannot perform.
- **Information Only**: state or a closed decision carrying no action.

## Evidence rules

- Read every cited memory body; `MEMORY.md` is a lossy pointer, not evidence.
  When body and index disagree, the body wins and the index should be fixed.
- A prior recap's forward sections, including a copy recalled from ICM, never
  supply or corroborate a candidate. Re-derive it each run.
- Memory-only work cannot become Actionable Now without a positive live signal
  such as a TODO, open PR, or active plan.
- A recorded closure—closed, won't-fix, by design, resolved, reverted, or
  superseded—outranks code shape. Omit it or place it in Information Only.
- Absence is not evidence. A missing file, guard, index, or migration cannot
  distinguish pending work from a deliberate rejection.
- For cross-repo work, locate and inspect the sibling repository when practical
  using `rg`/`rg --files` first and an available host fallback. Confirmed-done
  work becomes Information Only; unresolved status is Unverifiable. Deferred
  is strictly this-repository work.
- An optional recurring audit/review that has never produced findings is not a
  to-do. Only its unremediated findings are work; optional-pass state may be
  Information Only.

When uncertain, ask: can this exact work start now in this repository? If yes,
Actionable Now. If locally parked, Deferred. If in another repo and unresolved,
Unverifiable. If it needs a human/external action, Operator Gated. If no action
remains, Information Only.
