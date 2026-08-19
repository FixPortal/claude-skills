# Adversarial review — clean fixture

Every snippet below is a *legitimate* quotation lifted from a real persisted report.
They are here to prove `validate-report.ps1` stays narrow: a rule broad enough to
reject these would fire on a dozen good reports in the vault and be ignored within a
week. Do not remove them.

## Phase 4 live-code verification

### C001 — DefineConstants clobbers DEBUG/TRACE on net48

**Verifier** — claude:sonnet
**Verdict** — CONFIRMED
**Where** — `WidgetSample/WidgetSample.csproj:10-12` (`PropertyGroup Condition="'$(TargetFramework)' == 'net48'"`)
**Fix** — Use `<DefineConstants>$(DefineConstants);NET48</DefineConstants>`.

### C002 — Token spliced onto the publish command line

**Verifier** — kimi
**Verdict** — CONFIRMED
**Fix** — Drop the `--mount` and the `GITHUB_PACKAGES_TOKEN=$(cat ...)` prefix from the publish RUN.

### C003 — Positional arrays make a column-order error invisible

**Verifier** — codex
**Verdict** — CONFIRMED
**Fix** — Replace the positional arrays with named fields (`@{ In=...; Out=...; CacheWrite=...; CacheRead=... }`).
