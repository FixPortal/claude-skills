[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RepositoryRoot,
    [Parameter(Mandatory)] [string] $ScaffoldRoot,
    [string] $ActionsEvidencePath,
    [string] $ExpectedHeadSha,
    [string] $ApprovalPath
)

$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$scaffold = (Resolve-Path -LiteralPath $ScaffoldRoot).Path
$ciPath = Join-Path $repository '.github/workflows/ci.yml'
$ciContract = Get-Content -LiteralPath (Join-Path $scaffold 'references/ci-workflow.md') -Raw
$securityContract = Get-Content -LiteralPath (Join-Path $scaffold 'references/dependencies-and-security.md') -Raw
$reviewContract = Get-Content -LiteralPath (Join-Path $scaffold 'references/review-policy.md') -Raw

function Assert-CanonicalFile([string] $relativePath, [string] $assetName) {
    $actual = Join-Path $repository $relativePath
    $canonical = Join-Path $scaffold "assets/$assetName"
    if (-not (Test-Path -LiteralPath $actual)) { throw "Missing scaffold asset: $relativePath" }
    if (([IO.File]::ReadAllText($actual) -replace "`r`n", "`n") -ne
        ([IO.File]::ReadAllText($canonical) -replace "`r`n", "`n")) {
        throw "Scaffold asset drift: $relativePath"
    }
}

function Get-JobBlocks([string] $text) {
    $lines = @($text -split "\r?\n")
    $jobsAt = [array]::IndexOf($lines, 'jobs:')
    if ($jobsAt -lt 0) { throw 'Workflow has no jobs mapping.' }
    $starts = [Collections.Generic.List[object]]::new()
    for ($i = $jobsAt + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^  (?<id>[A-Za-z_][A-Za-z0-9_-]*):\s*(?:#.*)?$') {
            $starts.Add([pscustomobject]@{ Id = $Matches.id; Index = $i })
        }
    }
    if (-not $starts.Count) { throw 'Workflow jobs mapping has no parseable jobs.' }
    $blocks = [ordered]@{}
    for ($i = 0; $i -lt $starts.Count; $i++) {
        $end = if ($i + 1 -lt $starts.Count) { $starts[$i + 1].Index } else { $lines.Count }
        $blocks[$starts[$i].Id] = @($lines[$starts[$i].Index..($end - 1)])
    }
    $blocks
}

function Get-Steps([string[]] $job) {
    $starts = [Collections.Generic.List[int]]::new()
    for ($i = 1; $i -lt $job.Count; $i++) {
        if ($job[$i] -match '^      -\s+') { $starts.Add($i) }
    }
    $steps = @()
    for ($i = 0; $i -lt $starts.Count; $i++) {
        $end = if ($i + 1 -lt $starts.Count) { $starts[$i + 1] } else { $job.Count }
        $block = @($job[$starts[$i]..($end - 1)] | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $steps += $block
    }
    $steps
}

function Get-RunSteps([string[]] $job) {
    @(Get-Steps $job | Where-Object { $_ -match '(?m)^\s*(?:-\s*)?run:\s*' })
}

function Get-StepCommands([string] $step) {
    $lines = @($step -split "\r?\n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^\s*(?:-\s*)?run:\s*(?<value>.*)$') { continue }
        $inline = $Matches.value.Trim()
        if ($inline -and $inline -notmatch '^[>|][+-]?$') { return @($inline) }
        return @($lines[($i + 1)..($lines.Count - 1)] | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^#' })
    }
    @()
}

function Test-PublishDeployStep([string] $step) {
    foreach ($command in @(Get-StepCommands $step)) {
        if ($command -match '^(?:dotnet\s+(?:pack|publish|nuget\s+push)|npm\s+publish|pnpm\s+publish|yarn\s+npm\s+publish|gh\s+release\s+create|docker\s+(?:push|buildx\s+build\b.*--push)|az\s+(?:deployment|acr\s+build|containerapp)|kubectl\s+(?:apply|set\s+image)|helm\s+upgrade)\b') {
            return $true
        }
    }
    $step -match '(?m)^\s*(?:-\s*)?uses:\s*(?:docker/(?:build-push-action|login-action)|azure/(?:webapps-deploy|functions-action|container-apps-deploy-action)|softprops/action-gh-release|ncipollo/release-action|JS-DevTools/npm-publish)@'
}

function Assert-AncestryRunsOnTag([string[]] $job, [string] $step, [string] $jobId, [string] $workflowName) {
    $jobContinue = @($job | ForEach-Object {
        if ($_ -match '^    continue-on-error:\s*(?<value>.*?)\s*$') { $Matches.value.Trim() }
    } | Where-Object { $null -ne $_ })
    if ($jobContinue | Where-Object { $_ -notmatch '^(?i:false)(?:\s+#.*)?$' }) {
        throw "Tag-fired job '$jobId' in '$workflowName' has a non-failing continue-on-error value at job scope."
    }
    $stepContinue = @([regex]::Matches($step, '(?m)^ {8}continue-on-error:\s*(?<value>.*?)\s*$'))
    if ($stepContinue | Where-Object { $_.Groups['value'].Value.Trim() -notmatch '^(?i:false)(?:\s+#.*)?$' }) {
        throw "Tag-fired job '$jobId' in '$workflowName' has a non-failing continue-on-error value on the ancestry step."
    }
    $condition = [regex]::Match($step, '(?m)^\s*(?:-\s*)?if:\s*(?<condition>.+?)\s*$').Groups['condition'].Value.Trim()
    if (-not $condition) { return }
    if ($condition -match '^\$\{\{\s*(?<body>.*?)\s*\}\}$') { $condition = $Matches.body.Trim() }
    if ($condition -notmatch '^github\.ref_type\s*==\s*[''\"]tag[''\"]$' -and
        $condition -notmatch '^startsWith\(github\.ref,\s*[''\"]refs/tags/[^''\"]*[''\"]\)$') {
        throw "Tag-fired job '$jobId' in '$workflowName' has an ancestry step that does not execute on the tag path."
    }
}

function Get-Needs([string[]] $job) {
    for ($i = 1; $i -lt $job.Count; $i++) {
        if ($job[$i] -match '^    needs:\s*\[(?<items>[^]]*)\]') {
            return @($Matches.items.Split(',') | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ })
        }
        if ($job[$i] -match '^    needs:\s*$') {
            $items = [Collections.Generic.List[string]]::new()
            for ($j = $i + 1; $j -lt $job.Count -and $job[$j] -match '^\s{6,}-\s*(?<id>[A-Za-z_][A-Za-z0-9_-]*)'; $j++) {
                $items.Add($Matches.id)
            }
            return @($items)
        }
    }
    @()
}

function Get-Timeout([string[]] $job, [string] $jobId) {
    $line = $job | Where-Object { $_ -match '^    timeout-minutes:\s*(?<minutes>\d+)\s*$' } | Select-Object -First 1
    if (-not $line) { throw "Substantive job '$jobId' has no timeout-minutes." }
    [int] ([regex]::Match($line, '\d+').Value)
}

function Get-JobName([string[]] $job, [string] $jobId) {
    $line = $job | Where-Object { $_ -match '^    name:\s*(?<name>.+?)\s*$' } | Select-Object -First 1
    if (-not $line) { return $jobId }
    [regex]::Match($line, '^    name:\s*(?<name>.+?)\s*$').Groups['name'].Value.Trim().Trim("'").Trim('"')
}

function Assert-DotNetJob([string[]] $job, [string] $jobId, [int] $testSeconds) {
    $steps = @(Get-Steps $job)
    $setupAt = [array]::FindIndex($steps, [Predicate[string]] { param($step) $step -match 'uses:\s*actions/setup-dotnet@' })
    $toolAt = [array]::FindIndex($steps, [Predicate[string]] { param($step) @(Get-StepCommands $step | Where-Object { $_ -match '^dotnet tool restore\s*$' }).Count -gt 0 })
    $formatAt = [array]::FindIndex($steps, [Predicate[string]] { param($step) @(Get-StepCommands $step | Where-Object { $_ -match '^dotnet csharpier check \.\s*$' }).Count -gt 0 })
    $restoreAt = [array]::FindIndex($steps, [Predicate[string]] { param($step) @(Get-StepCommands $step | Where-Object { $_ -match '^dotnet restore\s+' }).Count -gt 0 })
    if ($setupAt -lt 0 -or $toolAt -ne ($setupAt + 1) -or $formatAt -ne ($toolAt + 1) -or $restoreAt -le $formatAt) {
        throw ".NET backend job '$jobId' must set up .NET, restore tools, run CSharpier, then restore packages."
    }
    foreach ($command in $steps | ForEach-Object { Get-StepCommands $_ } | Where-Object { $_ -match '^dotnet test\s+' }) {
        if ($command -notmatch [regex]::Escape("--blame-hang-timeout ${testSeconds}s")) {
            throw ".NET test step in '$jobId' is missing its per-test timeout."
        }
    }
}

if (-not (Test-Path -LiteralPath $ciPath)) { throw 'Missing .github/workflows/ci.yml' }
$ci = Get-Content -LiteralPath $ciPath -Raw
$jobs = Get-JobBlocks $ci

Assert-CanonicalFile '.github/scripts/assert_gate_coverage.py' 'assert_gate_coverage.py'
Assert-CanonicalFile '.github/scripts/assert_workflow_hygiene.py' 'assert_workflow_hygiene.py'
Assert-CanonicalFile '.github/workflows/review-policy-guard.yml' 'review-policy-guard.yml'

$python = if (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { 'python' }
& $python (Join-Path $repository '.github/scripts/assert_gate_coverage.py') $ciPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'CI Gate coverage or semantics failed.' }

$gateCoverage = @($jobs['gate-coverage']) -join "`n"
if ($gateCoverage -notmatch '(?m)^\s*-\s+run:\s*python3 \.github/scripts/assert_gate_coverage\.py \.github/workflows/ci\.yml\s*$') {
    throw 'Gate coverage does not execute the shipped checker.'
}
$gate = @($jobs['ci-gate']) -join "`n"
if ($gate -notmatch '(?m)^    permissions:\s*\{\}\s*$') { throw 'CI Gate must have zero permissions.' }

Push-Location $repository
try {
    & $python '.github/scripts/assert_workflow_hygiene.py' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Workflow hygiene failed.' }
}
finally { Pop-Location }

$policyPath = Join-Path $repository '.claude/review-policy.json'
if (-not (Test-Path -LiteralPath $policyPath)) { throw 'Missing review policy.' }
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$mergeBarrier = [regex]::Match($reviewContract, '(?s)\*\*So must the merge barrier\*\*\s+—(?<body>.*?)(?=\r?\n- \*\*)').Groups['body'].Value
$requiredHigh = @([regex]::Matches($mergeBarrier, '`(?<path>\.github/[^`]+)`') | ForEach-Object { $_.Groups['path'].Value } | Select-Object -Unique)
if (-not $requiredHigh.Count) { throw 'Cannot derive merge-barrier HIGH paths from scaffold-ci.' }
foreach ($path in $requiredHigh) {
    if (@($policy.high) -notcontains $path) { throw "Merge-barrier path is not HIGH: $path" }
}

$requiredTimeout = [int] [regex]::Match($ciContract, 'each substantive required job gets `timeout-minutes: (?<minutes>\d+)`').Groups['minutes'].Value
$aggregateBudget = [int] [regex]::Match($ciContract, '(?<minutes>\d+) aggregate runner-minutes').Groups['minutes'].Value
$testSeconds = [int] [regex]::Match($ciContract, 'One test gets a (?<seconds>\d+)-second hard\s+ceiling').Groups['seconds'].Value
if (-not $requiredTimeout -or -not $aggregateBudget -or -not $testSeconds) { throw 'Cannot derive executable CI time limits from scaffold-ci.' }
$requiredJobs = @(Get-Needs $jobs['ci-gate'] | Where-Object { $_ -ne 'gate-coverage' })
$controlJobs = @('ci-gate', 'gate-coverage')
foreach ($entry in $jobs.GetEnumerator() | Where-Object { $_.Key -notin $controlJobs }) {
    Get-Timeout $entry.Value $entry.Key | Out-Null
}
foreach ($jobId in $requiredJobs) {
    if (-not $jobs.Contains($jobId)) { throw "CI Gate needs unknown job '$jobId'." }
    $timeout = Get-Timeout $jobs[$jobId] $jobId
    if ($timeout -gt $requiredTimeout) { throw "Required job '$jobId' exceeds $requiredTimeout minutes." }
    $jobCommands = @(Get-RunSteps $jobs[$jobId] | ForEach-Object { Get-StepCommands $_ })
    if ($jobCommands | Where-Object { $_ -match '^dotnet (?:restore|build|test)\s+' }) {
        Assert-DotNetJob $jobs[$jobId] $jobId $testSeconds
    }
}

if ([string]::IsNullOrWhiteSpace($ActionsEvidencePath)) { throw 'Required-lane Actions cost evidence is missing.' }
if ([string]::IsNullOrWhiteSpace($ExpectedHeadSha)) { throw 'Required-lane expected head SHA is missing.' }
$requiredJobNames = @($requiredJobs | ForEach-Object { Get-JobName $jobs[$_] $_ })
$costEvidence = & (Join-Path $PSScriptRoot 'test-required-lane-cost.ps1') -EvidencePath $ActionsEvidencePath `
    -ExpectedHeadSha $ExpectedHeadSha -RequiredJobNames $requiredJobNames -BudgetMinutes $aggregateBudget `
    -ApprovalPath $ApprovalPath

$extendedLimit = [int] [regex]::Match($ciContract, 'weekly/manual jobs capped at (?<minutes>\d+) minutes').Groups['minutes'].Value
if (-not $extendedLimit) { $extendedLimit = [int] [regex]::Match($ciContract, 'timeout-minutes: (?<minutes>45)').Groups['minutes'].Value }
foreach ($workflow in Get-ChildItem -LiteralPath (Join-Path $repository '.github/workflows') -File | Where-Object { $_.Name -ne 'ci.yml' -and $_.Extension -in '.yml', '.yaml' }) {
    $text = Get-Content -LiteralPath $workflow.FullName -Raw
    if ($text -notmatch '(?im)^name:\s*Extended tests\s*$') { continue }
    foreach ($entry in (Get-JobBlocks $text).GetEnumerator()) {
        $timeout = Get-Timeout $entry.Value $entry.Key
        if ($timeout -gt $extendedLimit) { throw "Extended job '$($entry.Key)' exceeds $extendedLimit minutes." }
    }
}

$ciPush = [regex]::Match($ci, '(?ms)^  push:\s*\r?\n(?<body>(?:^ {4,}.*(?:\r?\n|$))*)').Groups['body'].Value
$mainline = [regex]::Match($ciPush, '(?m)^    branches:\s*\[(?<branch>[^],]+)').Groups['branch'].Value.Trim().Trim("'").Trim('"')
$workflowFiles = @(Get-ChildItem -LiteralPath (Join-Path $repository '.github/workflows') -File | Where-Object { $_.Extension -in '.yml', '.yaml' })
foreach ($workflow in $workflowFiles) {
    $workflowText = Get-Content -LiteralPath $workflow.FullName -Raw
    $push = [regex]::Match($workflowText, '(?ms)^  push:\s*\r?\n(?<body>(?:^ {4,}.*(?:\r?\n|$))*)').Groups['body'].Value
    if ($push -notmatch '(?m)^    tags:\s*(?:\[.*\]\s*|)$') { continue }
    if (-not $mainline) { throw 'Cannot derive the default branch for tag ancestry.' }
    foreach ($entry in (Get-JobBlocks $workflowText).GetEnumerator()) {
        $steps = @(Get-Steps $entry.Value)
        $publishAt = @()
        for ($i = 0; $i -lt $steps.Count; $i++) {
            if (Test-PublishDeployStep $steps[$i]) { $publishAt += $i }
        }
        if (-not $publishAt.Count) { continue }
        $ancestryAt = @()
        for ($i = 0; $i -lt $steps.Count; $i++) {
            if (@(Get-StepCommands $steps[$i] | Where-Object { $_ -match '^if ! git merge-base --is-ancestor\s+' }).Count) { $ancestryAt += $i }
        }
        if ($ancestryAt.Count -ne 1) { throw "Tag-fired publish/deploy path in job '$($entry.Key)' in '$($workflow.Name)' must have exactly one ancestry assertion step." }
        if ($ancestryAt[0] -gt ($publishAt | Measure-Object -Minimum).Minimum) {
            throw "Tag-fired publish/deploy path in job '$($entry.Key)' in '$($workflow.Name)' runs before ancestry is proven."
        }
        for ($i = 0; $i -lt $ancestryAt[0]; $i++) {
            if (@(Get-StepCommands $steps[$i] | Where-Object { $_ -match '^dotnet restore\s+' }).Count) {
                throw "Tag-fired job '$($entry.Key)' in '$($workflow.Name)' restores before ancestry is proven."
            }
        }
        $command = $steps[$ancestryAt[0]]
        Assert-AncestryRunsOnTag $entry.Value $command $entry.Key $workflow.Name
        $tokens = @('set -euo pipefail', "git fetch --no-tags origin $mainline", 'if ! git merge-base --is-ancestor "$GITHUB_SHA" FETCH_HEAD; then', 'exit 1', 'fi')
        $position = -1
        foreach ($token in $tokens) {
            $next = $command.IndexOf($token, $position + 1, [StringComparison]::Ordinal)
            if ($next -lt 0) { throw "Tag-fired job '$($entry.Key)' in '$($workflow.Name)' has an incomplete ancestry assertion: $token" }
            $position = $next
        }
    }
}

$secretJobId = [regex]::Match($securityContract, 'One `(?<id>[A-Za-z0-9_-]+)` job in `ci\.yml`').Groups['id'].Value
if (-not $secretJobId -or -not $jobs.Contains($secretJobId)) { throw 'Cannot locate the scaffold-ci private secret job.' }
$secretRuns = @(Get-RunSteps $jobs[$secretJobId])
$canonicalGitleaks = @([regex]::Matches($securityContract, '(?m)^\s*(?<command>"\$RUNNER_TEMP/gitleaks"\s+(?:git|dir)\s+.+)$') |
    ForEach-Object { $_.Groups['command'].Value.Trim() } | Select-Object -Unique)
if ($canonicalGitleaks.Count -ne 2) { throw 'Cannot derive both canonical Gitleaks invocations from scaffold-ci.' }
foreach ($command in $canonicalGitleaks) {
    $invocation = '(?m)^\s*(?:-\s*run:\s*)?' + [regex]::Escape($command) + '\s*$'
    if (-not ($secretRuns | Where-Object { $_ -match $invocation })) { throw "Private secret job is missing canonical scan: $command" }
}

[pscustomobject]@{ Status = $costEvidence.Status; Repository = $repository; CostEvidence = $costEvidence }
