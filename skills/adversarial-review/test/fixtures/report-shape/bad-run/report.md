# Adversarial review — bad fixture

This is the recorded shape of a report that actually shipped to the vault. Do not
"tidy" it: the two defects below are the subject of `validate-report.ps1`, and a
fixture that loses them turns its test into a green no-op.

## Phase 4 live-code verification

### C001 — AR-1 · Stage 5 publication is ordered so the PR gate blocks it, then repeats the publish

**Verifier** — $(@{id=C001; title=AR-1 · Stage 5 publication is ordered so the PR gate blocks it, then repeats the publish; verifier=claude:sonnet; verdict=CONFIRMED; valid=True; hasFileLine=True; verdictPath=<workdir>\AppData\Local\Temp\adversarial-review\your-repo-pr153-20260806T211407Z\phase4\C001-verdict.md}.verifier)
**Verdict** — CONFIRMED
