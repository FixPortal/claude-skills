# CI test budgets

PR CI is a bounded feedback lane, not the place to run every test the repository owns.

## Default budgets

| Surface | Budget |
|---|---:|
| One PR test case | 30 seconds, hard ceiling |
| One substantive required PR job | 10 minutes, hard ceiling |
| Substantive PR work per commit | 15 aggregate runner-minutes, target |
| One extended-test job | 45 minutes, hard ceiling |

A repository may tighten these defaults. Widening one requires explicit owner approval backed by measured CI evidence.

The ceilings detect missing completion and bound spend; they are not product-performance assertions. Never retry a timeout to make CI green. Make the test deterministic and bounded, optimize it, or move it to the extended lane.

## Lane contract

A test is PR-eligible only when it is deterministic and completes within 30 seconds on the representative CI runner. PR CI contains unit, component, and bounded integration tests that fit both PR ceilings.

Put these in a separate test project or explicit extended-project list, regardless of whether one sample happens to run quickly:

- end-to-end tests;
- stress, load, and soak tests;
- repeated or randomized concurrency/race amplification;
- real package, publish, install, or deployment exercises that exceed 30 seconds; and
- full operating-system or runtime compatibility matrices.

The extended lane has `workflow_dispatch` plus one staggered weekly schedule and a 45-minute job timeout. It is never a required PR gate; manual dispatch is for diagnosis or release verification, not a routine pre-merge ritual. Weekly is not unbounded: split or optimize a suite that cannot fit. Keep a small deterministic PR regression when it can prove the same behavioural contract without reproducing the stress workload.

Use project structure rather than test-case exclusion filters. This keeps lane selection visible and works with both VSTest and Microsoft Testing Platform.

## Runner enforcement

For the house VSTest PR path, add the native per-test ceiling without collecting a dump:

```text
dotnet test ... --blame-hang-timeout 30s --blame-hang-dump-type none
```

The timeout terminates the test host, so run separate test projects in separate commands when useful failure isolation matters. Keep the GitHub job's `timeout-minutes: 10` as the aggregate backstop.

MTP's hang timeout measures test-host inactivity, not an individual test's elapsed duration. Do not present it as equivalent. Keep operation-local completion ceilings from [async-and-timing.md](async-and-timing.md), use the ten-minute job cap, and structurally route known long tests out of PR CI.

## Cost check

Count substantive jobs multiplied by their matrix legs and expected duration. PR CI uses the smallest representative runner set that exercises the supported production path; broad compatibility matrices belong weekly. Lightweight gate-control jobs do not count toward the 15 aggregate runner-minute target.
