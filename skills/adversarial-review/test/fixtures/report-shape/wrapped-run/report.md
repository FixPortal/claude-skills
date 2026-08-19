# Adversarial review — wrapped-leak fixture

Same two defects as `bad-run`, but word-wrapped across a newline, which is what
markdown prose does to a long line. A per-line matcher reports this file clean.
Keep the line breaks exactly where they are.

## Phase 4 live-code verification

**Verifier** — $(
@{id=C001; verifier=claude:sonnet; verdict=CONFIRMED}.verifier)

**Evidence** — verdict written to `<workdir>\AppData\
Local\Temp\adversarial-review\run-20260806T211407Z\phase4\C001-verdict.md`
