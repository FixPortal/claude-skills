$ErrorActionPreference = 'Stop'

$skillDir = Split-Path $PSScriptRoot -Parent
$wrapper = Join-Path $skillDir 'agy-review.ps1'
if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw "wrapper not found: $wrapper" }

$expectedParameters = @(
    'Instruction', 'InstructionPath', 'DiffPath', 'FindingsPath', 'ContextPath',
    'Model', 'Effort', 'RepoPath', 'OutPath', 'UsageSidecarPath'
)
$actualParameters = (Get-Command $wrapper).Parameters.Keys
foreach ($name in $expectedParameters) {
    if ($actualParameters -notcontains $name) { throw "wrapper is missing -$name" }
}

$manifest = Get-Content (Join-Path $skillDir 'reviewers.json') -Raw | ConvertFrom-Json
$google = $manifest.reviewers | Where-Object id -eq 'G'
if ($manifest.wrappers.agy -ne 'agy-review.ps1') { throw 'manifest must map agy to agy-review.ps1' }
if ($google.wrapper -ne 'agy') { throw 'reviewer G must use the agy wrapper' }
if ($google.model -ne 'gemini-3.1-pro-high') { throw 'reviewer G must pin gemini-3.1-pro-high' }

$root = Join-Path ([IO.Path]::GetTempPath()) ('agy-review-test-' + [guid]::NewGuid().ToString('N'))
$fakeBin = Join-Path $root 'bin'
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null

# Capture BEFORE try: a throw during fixture setup must not leave the finally
# assigning $null back into $env:PATH.
$oldPath = $env:PATH
try {
    $brief = Join-Path $root 'brief.txt'
    $diff = Join-Path $root 'diff.txt'
    $context1 = Join-Path $root 'one.cs'
    $context2 = Join-Path $root 'two.cs'
    $out = Join-Path $root 'review.txt'
    $usage = Join-Path $root 'usage.json'
    $capture = Join-Path $root 'args.txt'

    Set-Content $brief 'Review the diff.'
    Set-Content $diff '+ fixed'
    Set-Content $context1 'interface IOne {}'
    Set-Content $context2 'interface ITwo {}'
    Set-Content (Join-Path $fakeBin 'agy.ps1') @(
        "if (-not (Test-Path brief.txt)) { exit 31 }"
        "if (-not (Test-Path review-diff.txt)) { exit 32 }"
        "if (-not (Test-Path 'context\00_one.cs')) { exit 33 }"
        "if (-not (Test-Path 'context\01_two.cs')) { exit 34 }"
        "Set-Content '$capture' (`$args -join ' ')"
        '$global:LASTEXITCODE = 0'
        "'FAKE REVIEW'"
    )

    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath
    $resolvedAgy = & pwsh -NoProfile -Command '(Get-Command agy).Source'
    if ($resolvedAgy -ne (Join-Path $fakeBin 'agy.ps1')) { throw "test double not resolved: $resolvedAgy" }
    & pwsh -NoProfile -File $wrapper -InstructionPath $brief -DiffPath $diff `
        -ContextPath "$context1;$context2" -Model 'gemini-3.1-pro-high' -Effort low `
        -OutPath $out -UsageSidecarPath $usage
    if ($LASTEXITCODE -ne 0) { throw "wrapper exited $LASTEXITCODE" }

    if (-not (Test-Path -LiteralPath $capture)) {
        throw "test double did not capture args; review output: $((Get-Content $out -Raw).Trim())"
    }
    $argsText = Get-Content $capture -Raw
    foreach ($fragment in @('--mode plan', '--model gemini-3.1-pro-high', '--effort high')) {
        if ($argsText -notlike "*$fragment*") { throw "agy invocation missing '$fragment': $argsText" }
    }

    # trap 8: agy resolves a BARE filename by searching the filesystem, not against its
    # working directory, so a prompt saying "read brief.txt" let it pick another agent's
    # scratchpad out of %TEMP% and review a different repository. The prompt must name
    # every input by absolute path and forbid the search outright.
    foreach ($banned in 'Read brief.txt', 'change in review-diff.txt', 'Cross-examine pooled-findings.txt') {
        if ($argsText -like "*$banned*") {
            throw "prompt names an input by bare filename, which agy resolves by search: $banned"
        }
    }
    foreach ($required in 'Do NOT search the filesystem', 'never substitute another file') {
        if ($argsText -notlike "*$required*") { throw "prompt does not forbid the filesystem search: $required" }
    }
    if ($argsText -notmatch 'brief\.txt') { throw 'prompt does not reference the brief at all' }
    # Capture the cited path by anchoring on the prompt phrase and matching NON-GREEDILY to
    # the filename. A character class that cannot cross a space (`[^ ]*`, or `\S+`) stops at
    # the first one, so on any host whose temp directory contains a space -- an ordinary
    # `<user-profile>\AppData\Local\Temp\...` on a runner with a real user name -- the
    # match fails against a wrapper that is behaving correctly. Same class of false failure
    # as the host-specific assertion below, reached by a different route.
    if ($argsText -notmatch 'Read the brief at (?<brief>.+?brief\.txt)') {
        throw "prompt does not cite the brief by path: $argsText"
    }
    # Absolute in BOTH shapes: a Windows drive-letter root and a POSIX leading slash. Asserted
    # by pattern rather than [IO.Path]::IsPathRooted, which answers for whichever host runs the
    # test -- an assertion written for the authoring host only is a host check wearing a
    # contract's clothes, and that one passed on Windows and failed on the Linux runner against
    # a wrapper that was behaving correctly.
    if ($Matches['brief'] -notmatch '^(?:[A-Za-z]:[\\/]|/)') {
        throw "prompt must cite brief.txt by absolute path, got: $($Matches['brief'])"
    }

    # trap 8: a hardcoded 5m ceiling killed slots that 20m recovered on the first attempt,
    # and retrying at the same ceiling recovered nothing in four attempts.
    if ($argsText -like '*--print-timeout 5m*') { throw 'print-timeout is pinned back to the 5m ceiling that kills slots' }
    if ($argsText -notlike '*--print-timeout 20m*') { throw "default print-timeout must be 20m: $argsText" }
    if ((Get-Content $out -Raw).Trim() -ne 'FAKE REVIEW') { throw 'wrapper did not write the review text' }
    $usageJson = Get-Content $usage -Raw | ConvertFrom-Json
    if ($usageJson.inputTokens -ne 0 -or $usageJson.outputTokens -ne 0 -or $usageJson.costUsd -ne 0) {
        throw 'agy usage sidecar must report unknown usage as zero'
    }

    # -Effort must drive --effort when the model name carries no effort suffix:
    # the case above lets the -high suffix win, so it never exercises the mapping.
    & pwsh -NoProfile -File $wrapper -InstructionPath $brief -DiffPath $diff `
        -ContextPath "$context1;$context2" -Model 'gemini-3.1-pro' -Effort low `
        -OutPath $out
    if ($LASTEXITCODE -ne 0) { throw "wrapper exited $LASTEXITCODE on the unsuffixed-model run" }
    $argsText = Get-Content $capture -Raw
    if ($argsText -notlike '*--effort low*') { throw "-Effort low was not passed through for an unsuffixed model: $argsText" }

    # The panel-contract values xhigh/max must FOLD to --effort high (the agy CLI
    # accepts only low/medium/high); passing them through would die at the CLI.
    foreach ($folded in @('xhigh', 'max')) {
        & pwsh -NoProfile -File $wrapper -InstructionPath $brief -DiffPath $diff `
            -ContextPath "$context1;$context2" -Model 'gemini-3.1-pro' -Effort $folded `
            -OutPath $out
        if ($LASTEXITCODE -ne 0) { throw "wrapper exited $LASTEXITCODE on -Effort $folded" }
        $argsText = Get-Content $capture -Raw
        if ($argsText -notlike '*--effort high*') { throw "-Effort $folded must fold to '--effort high': $argsText" }
        if ($argsText -like "*--effort $folded*") { throw "-Effort $folded leaked through to the CLI unchanged: $argsText" }
    }

    'agy-review.ps1 OK'
}
finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
