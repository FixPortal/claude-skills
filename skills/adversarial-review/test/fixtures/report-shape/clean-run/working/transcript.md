# Phase 4 working transcript — clean fixture

`working/` is raw run material, not a deliverable, and it legitimately carries both
patterns the validator rejects in a report. This file exists to prove the exclusion
is real; if it stops carrying them, the exclusion test is vacuous.

Verifier objects as PowerShell rendered them:

    $(@{id=C001; verifier=claude:sonnet; verdict=CONFIRMED}.verifier)

Verdict written to:

    <workdir>\AppData\Local\Temp\adversarial-review\run-20260806T211407Z\phase4\C001-verdict.md
