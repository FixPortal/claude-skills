$ErrorActionPreference = 'Stop'
# aggregate-and-emit.ps1 posts to the observatory when OBSERVATORY_API_KEY AND
# OBSERVATORY_URL are both set; a developer's normal environment would publish
# these fixture rows as real telemetry. Clear both for the whole script and
# restore them in finally (each verifier runs in its own process in CI, so no
# sibling verifier clears them for this one).
$savedApiKey = $env:OBSERVATORY_API_KEY
$savedUrl = $env:OBSERVATORY_URL
$env:OBSERVATORY_API_KEY = ''
$env:OBSERVATORY_URL = ''
$root = Join-Path $PSScriptRoot '..'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ar-model-telemetry-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $tempRoot 'repo'
$work = Join-Path $tempRoot 'work'
$manifestPath = Join-Path $tempRoot 'reviewers.json'

try {
    New-Item -ItemType Directory -Path $repo | Out-Null
    & git -C $repo init --quiet
    & git -C $repo config user.email fixture@example.com
    & git -C $repo config user.name Fixture
    Set-Content -LiteralPath (Join-Path $repo 'sample.txt') -Value fixture -Encoding utf8
    & git -C $repo add sample.txt
    & git -C $repo -c commit.gpgsign=false commit --quiet -m fixture

    # The spine refuses to start without a preflight.json in the WorkDir or its parent
    # (the host's pre-flight record); the fixture satisfies the gate at the temp root.
    [ordered]@{ stub = 'pass' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempRoot 'preflight.json') -Encoding utf8

    [ordered]@{
        minVendors = 2
        wrappers = [ordered]@{ stub = 'test/fixtures/stub-review.ps1' }
        reviewers = @(
            [ordered]@{ id='A'; label='Anthropic'; wrapper='stub'; model='sonnet'; vendor='anthropic'; repoAccess=$false; enabled=$true },
            [ordered]@{ id='B'; label='OpenAI'; wrapper='stub'; model='unpriced-openai-model'; vendor='openai'; repoAccess=$false; enabled=$true }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

    $rejectOutput = & pwsh -NoProfile -File (Join-Path $root 'run-review.ps1') -RepoPath $repo `
        -Target 123 -Pathspec sample.txt -WorkDir (Join-Path $tempRoot 'reject-work') `
        -ManifestPath $manifestPath 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $rejectOutput -notmatch 'PR targets do not support pathspecs') {
        throw "PR + pathspec must fail before gh invocation, got:`n$rejectOutput"
    }

    & pwsh -NoProfile -File (Join-Path $root 'run-review.ps1') -RepoPath $repo -Target audit `
        -Pathspec sample.txt -WorkDir $work -ManifestPath $manifestPath *> $null
    if ($LASTEXITCODE -ne 0) { throw "run-review fixture exited $LASTEXITCODE" }

    # The model-registry skill is a sibling in the private home but is not part of this
    # public mirror, so only the registry-backed model-resolution assertions below are
    # skipped when it is absent; the unknown-cost and display assertions need no
    # registry and always run.
    $registryPath = Join-Path $root '..' 'model-registry' 'registry.json'
    $hasRegistry = Test-Path -LiteralPath $registryPath
    if (-not $hasRegistry) {
        Write-Host "SKIP: model-registry sibling not present in this tree - $registryPath"
    }
    $metrics = Get-Content (Join-Path $work 'metrics.json') -Raw | ConvertFrom-Json
    $anthropic = $metrics.participants | Where-Object reviewer -eq anthropic

    if ($hasRegistry) {
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json -AsHashtable
        $expected = $registry.models.GetEnumerator() |
            Where-Object { $_.Key.StartsWith('claude-sonnet-') -and $_.Value.availability.cli -eq 'available' -and -not $_.Value.retired } |
            Sort-Object { [int]($_.Value.rank ?? [int]::MaxValue) }, Key |
            Select-Object -First 1

        if (-not $expected -or $anthropic.model -ne $expected.Key) {
            throw "expected current registry model '$($expected.Key)', got '$($anthropic.model)'"
        }
        if ($anthropic.costUsd -le 0 -or -not $anthropic.costEstimated) {
            throw 'sidecar-less Anthropic telemetry must use current registry prices and remain estimated'
        }
    }

    $openai = $metrics.participants | Where-Object reviewer -eq openai
    if (-not $openai.costUnknown -or $openai.costUsd -ne 0) {
        throw 'an unpriced registry model must remain costUnknown in chunk metrics'
    }

    $aggregateOutput = & pwsh -NoProfile -File (Join-Path $root 'aggregate-and-emit.ps1') `
        -RunRoot $work -Repo fixture 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "aggregate-and-emit fixture exited $LASTEXITCODE`n$aggregateOutput" }
    if ($aggregateOutput -notmatch 'openai \(reviewer\).*UNKNOWN') {
        throw "aggregate display must render unknown cost as UNKNOWN, never numeric zero:`n$aggregateOutput"
    }

    [ordered]@{
        judge = [ordered]@{
            reviewer = 'openai'; model = 'gpt-5.6-sol'; inputTokens = 10; outputTokens = 5
            costUsd = 0.0; reviewDurationMs = 1
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $work 'aggregate-verdict.json') -Encoding utf8
    $judgeOutput = & pwsh -NoProfile -File (Join-Path $root 'aggregate-and-emit.ps1') `
        -RunRoot $work -Repo fixture 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "exact-judge aggregate fixture exited $LASTEXITCODE`n$judgeOutput" }
    if ($judgeOutput -notmatch 'openai \(judge\).*gpt-5\.6-sol.*UNKNOWN') {
        throw "an exact unpriced judge model must remain UNKNOWN through aggregation and display:`n$judgeOutput"
    }

    'run-review model telemetry OK — registry prices resolve and unknown cost stays unknown through display'
}
finally {
    # Assigning $null removes the variable entirely, so an originally-unset var is
    # restored to unset rather than left defined-but-empty.
    $env:OBSERVATORY_API_KEY = $savedApiKey
    $env:OBSERVATORY_URL = $savedUrl
    if ($tempRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
