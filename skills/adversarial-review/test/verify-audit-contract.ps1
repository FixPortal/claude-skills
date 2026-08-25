$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..'
$main = Get-Content (Join-Path $root 'SKILL.md') -Raw
$driver = Get-Content (Join-Path $root 'run-review.ps1') -Raw
$manifest = Get-Content (Join-Path $root 'reviewers.json') -Raw | ConvertFrom-Json
$methodology = Get-Content (Join-Path $root 'docs' 'METHODOLOGY-v2.md') -Raw
$telemetry = Get-Content (Join-Path $root 'emit-review-telemetry.ps1') -Raw
$gemini = Get-Content (Join-Path $root 'gemini-review.ps1') -Raw
$aggregate = Get-Content (Join-Path $root 'aggregate-and-emit.ps1') -Raw
$codex = Get-Content (Join-Path $root 'codex-review.ps1') -Raw
$openai = Get-Content (Join-Path $root 'openai-review.ps1') -Raw

# A smell alarm, not the contract. What must not happen is prompt bodies and roster
# facts being mirrored here, and the needle checks below enforce that DIRECTLY - this
# count is the blunt proxy sitting on top of them. It was 1200, which the file reached
# with four words to spare, and a tripwire that tight buys nothing: the next legitimate
# addition either deletes load-bearing content to make room or silently bumps the
# number. Raised to 1400 with the file trimmed to ~1150. If it is ever approached
# again, look for mirrored canonical detail first and only then argue about the number.
$words = ([regex]::Matches($main, '\b[\w/-]+\b')).Count
if ($words -ge 1400) { throw "adversarial-review/SKILL.md is $words words; canonical prompts/roster must stay external" }
foreach ($stale in 'Gemini and GPT', 'G+X', 'claude-sonnet-4-6',
                      'claude-opus-4-8', '### Audit-mode preamble') {
    if ($main -match [regex]::Escape($stale)) { throw "SKILL.md retains duplicated/stale detail: $stale" }
}
foreach ($needle in 'PR targets do not support pathspecs', 'repoAccess:false',
                     'Resolve-TelemetryModel', 'Get-BlendedRatePerMillion') {
    if ($driver -notmatch [regex]::Escape($needle)) { throw "run-review.ps1 missing contract: $needle" }
}
# The registry path must be built with Join-Path segments, not a backslash literal. This
# needle used to be the literal 'model-registry\registry.json', which pinned the
# non-portable spelling in place: making the path portable BROKE the test guarding it.
foreach ($piece in "'model-registry'", "'registry.json'") {
    if ($driver -notmatch [regex]::Escape($piece)) { throw "run-review.ps1 must build the registry path from Join-Path segments: $piece" }
}
if ($driver -match [regex]::Escape('model-registry\registry.json')) {
    throw 'run-review.ps1 still embeds a backslash registry path; it fails soft to $null off Windows'
}
if ($aggregate -match [regex]::Escape('model-registry\registry.json')) {
    throw 'aggregate-and-emit.ps1 still embeds a backslash registry path'
}

# A wrapper with no hard per-invocation read-only mode must never be granted repo access
# anywhere in the manifest. Kimi's reviewer entry is deliberately repoAccess:false, but a
# ROLE-WIDE flag re-granted it as a Phase-4 verifier - write access to the very tree the
# phase exists to produce trustworthy evidence about.
$noSandbox = @($manifest.noSandboxWrappers)
if (-not $noSandbox) { throw 'reviewers.json must declare noSandboxWrappers' }
foreach ($r in @($manifest.reviewers) + @($manifest.alternates)) {
    if ($noSandbox -contains $r.wrapper -and $r.repoAccess) {
        throw "reviewer '$($r.id)' uses no-sandbox wrapper '$($r.wrapper)' with repoAccess:true"
    }
}
foreach ($roleName in $manifest.roles.PSObject.Properties.Name) {
    if ($roleName -eq '_comment') { continue }
    $role = $manifest.roles.$roleName
    if ($role.wrapper -and $noSandbox -contains $role.wrapper -and $role.repoAccess) {
        throw "role '$roleName' uses no-sandbox wrapper '$($role.wrapper)' with repoAccess:true"
    }
    # A role carrying a pool must NOT also carry a role-wide repoAccess: that is exactly the
    # shape that promoted every member to repo-aware regardless of its own posture.
    if ($role.pool) {
        if ($null -ne $role.PSObject.Properties['repoAccess']) {
            throw "role '$roleName' has a pool AND a role-wide repoAccess; access must be declared per pool member"
        }
        foreach ($member in @($role.pool)) {
            if ($member -isnot [System.Management.Automation.PSCustomObject]) {
                throw "role '$roleName' pool member '$member' is a bare string; it must declare its own repoAccess"
            }
            if ($noSandbox -contains $member.wrapper -and $member.repoAccess) {
                throw "role '$roleName' pool member '$($member.wrapper)' has no read-only mode but carries repoAccess:true"
            }
        }
    }
}
if ($driver -match 'return (6\.0|20\.0|30\.0)') { throw 'run-review.ps1 retains hardcoded blended model rates' }
foreach ($needle in 'Resolve-ModelSelector', 'Get-RegistryCost', 'judgeCostEstimated') {
    if ($aggregate -notmatch [regex]::Escape($needle)) { throw "judge aggregation missing current-model contract: $needle" }
}

# "Cost unknown" must survive all the way to the Observatory, not stop at metrics.json:
# a bare 0.0 there is indistinguishable from a genuinely free subscription-backed call.
$emitParams = (Get-Command (Join-Path $root 'emit-review-telemetry.ps1')).Parameters
if (-not $emitParams.ContainsKey('CostUnknown')) {
    throw 'emit-review-telemetry.ps1 has no -CostUnknown parameter, so unknown cost reaches the dashboard as 0.0'
}
# It MUST be a switch. Callers invoke through `pwsh -File`, where every argument is a
# string, and a [bool] parameter refuses a string outright ("Cannot convert value
# System.String to type System.Boolean") for "False"/"True"/"1"/"0" alike - so a [bool]
# here fails the entire emit call the moment the flag is passed.
if ($emitParams['CostUnknown'].ParameterType -ne [switch]) {
    throw "emit-review-telemetry.ps1 -CostUnknown must be [switch], not $($emitParams['CostUnknown'].ParameterType); a [bool] cannot bind through pwsh -File"
}
if ($emitParams['CostUnknown'].ParameterType -eq [switch] -and $aggregate -notmatch '\$v -is \[bool\]') {
    throw 'Invoke-Emit must render boolean values as bare switch flags; "-Flag False" cannot bind and would invert the meaning'
}
foreach ($needle in 'CostUnknown = [bool]$r.costUnknown', 'CostUnknown = $judgeCostUnknown') {
    if ($aggregate -notmatch [regex]::Escape($needle)) { throw "aggregate-and-emit.ps1 does not forward costUnknown to emission: $needle" }
}
if ($driver -notmatch 'costUnknown\s+=') { throw 'run-review.ps1 does not record costUnknown in metrics.json' }
foreach ($wrapper in @{ 'codex-review.ps1' = $codex; 'openai-review.ps1' = $openai }.GetEnumerator()) {
    if ($wrapper.Value -match "(?m)^\s*'gpt-5\.6-sol'\s*=") {
        throw "$($wrapper.Key) privately prices unpriced registry model gpt-5.6-sol"
    }
}
if ($main -notmatch [regex]::Escape('~/.agents/notes/model-routing-traps.md')) {
    throw 'SKILL.md must read the canonical model-routing traps before repository-aware Codex routing'
}

foreach ($wrapperName in ($manifest.wrappers.PSObject.Properties | Where-Object Name -ne '_comment' | ForEach-Object Value)) {
    $params = (Get-Command (Join-Path $root $wrapperName)).Parameters.Keys
    foreach ($required in 'Instruction', 'DiffPath', 'FindingsPath', 'ContextPath', 'Model') {
        if ($params -notcontains $required) { throw "$wrapperName lacks required minimum parameter -$required" }
    }
}

# Every wrapper an ENABLED reviewer can actually reach - primary or declared fallback -
# must be pre-flightable, because pre-flight is what keeps an unauthenticated CLI from
# being discovered mid-fan-out, inside a paid parallel round.
$reachable = @($manifest.reviewers | Where-Object { $_.enabled } | ForEach-Object { $_.wrapper; $_.fallbackWrapper }) |
    Where-Object { $_ } | Sort-Object -Unique
foreach ($w in $reachable) {
    $file = $manifest.wrappers.$w
    if (-not $file) { throw "enabled reviewer references undeclared wrapper '$w'" }
    $body = Get-Content (Join-Path $root $file) -Raw
    if ($body -notmatch '(?m)^\s*PREFLIGHT_COMMAND:\s*\S') { throw "$file declares no PREFLIGHT_COMMAND" }
    if ($body -notmatch '(?m)^\s*PREFLIGHT_SUCCESS:\s*\S') { throw "$file declares no PREFLIGHT_SUCCESS" }
}

# The OpenAI pre-flight probe must keep its inner command SINGLE-quoted. Double-quoted,
# the invoking shell expands the key before the child runs: the child gets a ParserError
# and the literal credential lands on its command line, so the only declared OpenAI
# fallback reads as permanently unavailable AND leaks the key exactly when one is set.
if ($openai -match 'PREFLIGHT_COMMAND:[^\r\n]*-Command\s+"') {
    throw 'openai-review.ps1 pre-flight uses a double-quoted inner command; the invoking shell expands $env:OPENAI_API_KEY onto the child command line'
}
if ($openai -notmatch "PREFLIGHT_COMMAND:[^\r\n]*-Command\s+'[^']*IsNullOrWhiteSpace\(\`$env:OPENAI_API_KEY\)'") {
    throw 'openai-review.ps1 pre-flight must single-quote the in-child key test'
}

if ($methodology -match '~/.claude/skills/adversarial-review|own `default_model`|unchanged, uniform') {
    throw 'methodology retains stale canonical-home, Kimi-default, or uniform-contract wording'
}
if ($telemetry -notmatch 'own Phase-1 findings' -or $telemetry -match 'credit all four vendors') {
    throw 'telemetry help must use own-finding attribution, not consensus credit'
}
foreach ($path in 'claude-review.ps1', 'gemini-review.ps1', 'openai-review.ps1', 'emit-review-telemetry.ps1') {
    $help = (Get-Content (Join-Path $root $path) -Raw) -split '#>', 2 | Select-Object -First 1
    if ($help -match '(?m)^\s+pwsh .+`\s*$') { throw "$path exposes a backtick-continued copy/paste example" }
}

if ($gemini -notmatch 'NewGuid\(\).*paused|paused\.\$PID.*NewGuid' -or
    $gemini -match "oauth_creds\.json\.paused'" -or
    $gemini -match 'restore.*SilentlyContinue') {
    throw 'gemini OAuth shadowing must use a unique backup and strict restore'
}

# The driver must admit the canonical clean sentinel the Phase-1 brief pins: a review
# that finds nothing replies with exactly that heading and counts as participation
# (issuesRaised=0, failed=$false), so an all-clean pool terminates cleanly instead of Die.
$phase1Brief = Get-Content (Join-Path $root 'briefs' 'phase1-review.txt') -Raw
foreach ($needle in '### No substantive defects') {
    if ($phase1Brief -notmatch [regex]::Escape($needle)) { throw "phase1-review.txt does not pin the clean sentinel: $needle" }
    if ($driver -notmatch [regex]::Escape($needle)) { throw "run-review.ps1 does not admit the clean sentinel as participation: $needle" }
}

# The -PreamblePath preamble must front ALL FOUR phase briefs. Phases 3/4 used to get the
# raw brief, so the judge and verifier worked a code-shaped frame on a corpus target.
foreach ($n in 1..4) {
    if ($driver -notmatch ('\$phase' + $n + '\s*=\s*\$preamble \+')) {
        throw "run-review.ps1 does not front the -PreamblePath preamble onto the phase $n brief"
    }
}

# Phase 4 scope is "Every Critical, every High and every contested finding" — the judge
# packet line used to drop Critical, so the highest-severity findings could skip
# verification entirely.
foreach ($needle in 'Every Critical, every High and every contested finding') {
    if ($driver -notmatch [regex]::Escape($needle)) { throw "run-review.ps1 judge packet does not scope Phase 4 over Criticals: $needle" }
    if ($main -notmatch [regex]::Escape($needle)) { throw "SKILL.md does not scope Phase 4 over Criticals: $needle" }
    if ($methodology -notmatch [regex]::Escape($needle)) { throw "METHODOLOGY-v2.md does not scope Phase 4 over Criticals: $needle" }
}

# Die() collapsed exit codes 2-5 to 1: a bare Write-Error under $ErrorActionPreference=Stop
# throws before `exit $code` runs. Every Write-Error feeding an exit must continue first.
# Anchored at line start so the prose comments explaining this do not trip it.
if ($driver -match '(?m)^\s*Write-Error(?![^\r\n]*-ErrorAction\s+Continue)') {
    throw 'run-review.ps1 has a Write-Error without -ErrorAction Continue; it throws before exit $code and collapses the exit code'
}

# Every participant record that emits cost fields must set costUnknown. The
# failed-reviewer branch (costEstimated = $false) used to omit it, so a wrapper outage
# reached the dashboard as a measured 0.0 instead of UNKNOWN.
if ($driver -notmatch '(?s)costEstimated\s*=\s*\$false.{0,120}?costUnknown\s*=') {
    throw 'run-review.ps1 emits cost fields in a participant branch without setting costUnknown'
}

# Provenance and pre-flight artefacts the host/judge side now depends on: the pooled map
# makes IssuesAccepted derivable; preflight.json is the evidence pre-flight ran.
foreach ($needle in 'pooled-map.json', 'preflight.json') {
    if ($driver -notmatch [regex]::Escape($needle)) { throw "run-review.ps1 does not honour the run-root artefact contract: $needle" }
}

"adversarial-review audit contract OK — $words words"
