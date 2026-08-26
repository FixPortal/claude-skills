$ErrorActionPreference = 'Stop'

$skillRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$workflowInventory = Join-Path $skillRoot 'scripts/get-workflow-inventory.ps1'
$canonicalCompare = Join-Path $skillRoot 'scripts/compare-canonical-file.ps1'
$contractCheck = Join-Path $skillRoot 'scripts/test-scaffold-contract.ps1'
$costCheck = Join-Path $skillRoot 'scripts/test-required-lane-cost.ps1'
$scaffoldRoot = Resolve-Path (Join-Path $skillRoot '..' 'scaffold-ci')
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('audit-ci-mechanics-' + [guid]::NewGuid().ToString('N'))
$headSha = '1111111111111111111111111111111111111111'
$costEvidence = Join-Path $fixtures 'actions-cost-compliant.json'
$validApproval = Join-Path $fixtures 'actions-cost-approval-valid.json'

function Assert-Equal($actual, $expected, [string] $because) {
    $actualText = @($actual) -join "`n"
    $expectedText = @($expected) -join "`n"
    if ($actualText -ne $expectedText) {
        throw "$because`nExpected:`n$expectedText`nActual:`n$actualText"
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $cost = & $costCheck -EvidencePath (Join-Path $fixtures 'actions-cost-compliant.json') -ExpectedHeadSha $headSha `
        -RequiredJobNames @('Backend (.NET)', 'Frontend (UI)', 'Secrets') -BudgetMinutes 15
    if ($cost.Status -ne 'COMPLIANT' -or $cost.AggregateMinutes -ne 12 -or $cost.CountedJobs -ne 3) {
        throw "Canonical hybrid measured cost was misclassified: $($cost | ConvertTo-Json -Compress)"
    }

    foreach ($case in @(
        @{ Name = 'over-budget matrix'; Path = 'actions-cost-over-budget-matrix.json'; Jobs = @('Backend (.NET)', 'Frontend (UI)') },
        @{ Name = 'missing duration'; Path = 'actions-cost-missing-duration.json'; Jobs = @('Backend (.NET)', 'Frontend (UI)') },
        @{ Name = 'missing head SHA'; Path = 'actions-cost-missing-head.json'; Jobs = @('Backend (.NET)') },
        @{ Name = 'stale head SHA'; Path = 'actions-cost-stale.json'; Jobs = @('Backend (.NET)', 'Frontend (UI)') }
    )) {
        $failed = $false
        try { & $costCheck -EvidencePath (Join-Path $fixtures $case.Path) -ExpectedHeadSha $headSha -RequiredJobNames $case.Jobs -BudgetMinutes 15 2>$null | Out-Null }
        catch { $failed = $true }
        if (-not $failed) { throw "Required-lane cost evidence failed open: $($case.Name)" }
    }
    $missingEvidenceFailed = $false
    try { & $costCheck -EvidencePath (Join-Path $fixtures 'missing-actions-cost.json') -ExpectedHeadSha $headSha -RequiredJobNames @('Backend (.NET)') -BudgetMinutes 15 2>$null | Out-Null }
    catch { $missingEvidenceFailed = $true }
    if (-not $missingEvidenceFailed) { throw 'Missing required-lane cost evidence passed the audit.' }

    $omittedLegPath = Join-Path $tempRoot 'actions-cost-omitted-leg.json'
    $omittedLeg = Get-Content -LiteralPath (Join-Path $fixtures 'actions-cost-over-budget-matrix.json') -Raw | ConvertFrom-Json
    $omittedLeg.jobs = @($omittedLeg.jobs[0], $omittedLeg.jobs[1], $omittedLeg.jobs[3])
    [IO.File]::WriteAllText($omittedLegPath, ($omittedLeg | ConvertTo-Json -Depth 10))
    $omittedLegFailed = $false
    try { & $costCheck -EvidencePath $omittedLegPath -ExpectedHeadSha $headSha -RequiredJobNames @('Backend (.NET)', 'Frontend (UI)', 'Secrets') -BudgetMinutes 15 2>$null | Out-Null }
    catch { $omittedLegFailed = $true }
    if (-not $omittedLegFailed) { throw 'An omitted matrix leg passed despite the jobs total_count mismatch.' }

    foreach ($case in @(
        @{ Name = 'missing total_count'; Mutate = { param($value) $value.PSObject.Properties.Remove('total_count') } },
        @{ Name = 'negative total_count'; Mutate = { param($value) $value.total_count = -1 } },
        @{ Name = 'string total_count'; Mutate = { param($value) $value.total_count = '4' } },
        @{ Name = 'missing run id'; Mutate = { param($value) $value.run.PSObject.Properties.Remove('id') } }
    )) {
        $invalidEvidence = Get-Content -LiteralPath (Join-Path $fixtures 'actions-cost-over-budget-matrix.json') -Raw | ConvertFrom-Json
        & $case.Mutate $invalidEvidence
        $invalidEvidencePath = Join-Path $tempRoot (($case.Name -replace ' ', '-') + '.json')
        [IO.File]::WriteAllText($invalidEvidencePath, ($invalidEvidence | ConvertTo-Json -Depth 10))
        $invalidEvidenceFailed = $false
        try { & $costCheck -EvidencePath $invalidEvidencePath -ExpectedHeadSha $headSha -RequiredJobNames @('Backend (.NET)', 'Frontend (UI)', 'Secrets') -BudgetMinutes 15 -ApprovalPath $validApproval 2>$null | Out-Null }
        catch { $invalidEvidenceFailed = $true }
        if (-not $invalidEvidenceFailed) { throw "Invalid Actions evidence failed open: $($case.Name)" }
    }

    $approved = & $costCheck -EvidencePath (Join-Path $fixtures 'actions-cost-over-budget-matrix.json') -ExpectedHeadSha $headSha `
        -RequiredJobNames @('Backend (.NET)', 'Frontend (UI)', 'Secrets') -BudgetMinutes 15 -ApprovalPath $validApproval
    if ($approved.Status -ne 'APPROVED_EXCEPTION' -or $approved.AggregateMinutes -ne 18 -or $approved.CountedJobs -ne 4) {
        throw "Approved measured exception was misclassified: $($approved | ConvertTo-Json -Compress)"
    }

    foreach ($case in @(
        @{ Name = 'malformed approval'; Mutate = { param($path) [IO.File]::WriteAllText($path, 'banana') } },
        @{ Name = 'approval missing owner'; Mutate = { param($path) $value = Get-Content -LiteralPath $validApproval -Raw | ConvertFrom-Json; $value.PSObject.Properties.Remove('owner'); [IO.File]::WriteAllText($path, ($value | ConvertTo-Json)) } },
        @{ Name = 'approval missing date'; Mutate = { param($path) $value = Get-Content -LiteralPath $validApproval -Raw | ConvertFrom-Json; $value.PSObject.Properties.Remove('approved_at'); [IO.File]::WriteAllText($path, ($value | ConvertTo-Json)) } },
        @{ Name = 'approval invalid date'; Mutate = { param($path) $value = Get-Content -LiteralPath $validApproval -Raw | ConvertFrom-Json; $value.approved_at = 'banana'; [IO.File]::WriteAllText($path, ($value | ConvertTo-Json)) } },
        @{ Name = 'approval not approved'; Mutate = { param($path) $value = Get-Content -LiteralPath $validApproval -Raw | ConvertFrom-Json; $value.approved = $false; [IO.File]::WriteAllText($path, ($value | ConvertTo-Json)) } },
        @{ Name = 'approval stale SHA'; Mutate = { param($path) $value = Get-Content -LiteralPath $validApproval -Raw | ConvertFrom-Json; $value.head_sha = '2222222222222222222222222222222222222222'; [IO.File]::WriteAllText($path, ($value | ConvertTo-Json)) } },
        @{ Name = 'approval stale run'; Mutate = { param($path) $value = Get-Content -LiteralPath $validApproval -Raw | ConvertFrom-Json; $value.run_id = 9999; [IO.File]::WriteAllText($path, ($value | ConvertTo-Json)) } }
    )) {
        $invalidApprovalPath = Join-Path $tempRoot (($case.Name -replace ' ', '-') + '.json')
        & $case.Mutate $invalidApprovalPath
        $approvalFailed = $false
        try { & $costCheck -EvidencePath (Join-Path $fixtures 'actions-cost-over-budget-matrix.json') -ExpectedHeadSha $headSha -RequiredJobNames @('Backend (.NET)', 'Frontend (UI)', 'Secrets') -BudgetMinutes 15 -ApprovalPath $invalidApprovalPath 2>$null | Out-Null }
        catch { $approvalFailed = $true }
        if (-not $approvalFailed) { throw "Invalid approval evidence failed open: $($case.Name)" }
    }

    New-Item -ItemType Directory -Path (Join-Path $tempRoot '.github/workflows') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot '.github/workflows/ci.yml') -Value 'name: ci'
    Set-Content -LiteralPath (Join-Path $tempRoot '.github/workflows/deploy.yaml') -Value 'name: deploy'
    Set-Content -LiteralPath (Join-Path $tempRoot '.github/workflows/readme.txt') -Value 'not a workflow'

    $inventory = @(& $workflowInventory -RepositoryRoot $tempRoot)
    Assert-Equal $inventory @('.github/workflows/ci.yml', '.github/workflows/deploy.yaml') 'Inventory must include both workflow extensions and nothing else.'

    $canonical = Join-Path $tempRoot 'canonical.txt'
    $sameEol = Join-Path $tempRoot 'same-eol.txt'
    $drifted = Join-Path $tempRoot 'drifted.txt'
    [IO.File]::WriteAllText($canonical, "one`ntwo`n")
    [IO.File]::WriteAllText($sameEol, "one`r`ntwo`r`n")
    [IO.File]::WriteAllText($drifted, "one`r`nchanged`r`n")

    & $canonicalCompare -ActualPath $sameEol -CanonicalPath $canonical -IgnoreLineEndings | Out-Null

    $driftFailed = $false
    try { & $canonicalCompare -ActualPath $drifted -CanonicalPath $canonical -IgnoreLineEndings 2>$null | Out-Null }
    catch { $driftFailed = $true }
    if (-not $driftFailed) { throw 'Content drift must fail a copy-only comparison.' }

    $repo = Join-Path $tempRoot 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo '.github/scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo '.claude') -Force | Out-Null
    Copy-Item (Join-Path $scaffoldRoot 'assets/assert_gate_coverage.py') (Join-Path $repo '.github/scripts/assert_gate_coverage.py')
    Copy-Item (Join-Path $scaffoldRoot 'assets/assert_workflow_hygiene.py') (Join-Path $repo '.github/scripts/assert_workflow_hygiene.py')
    Copy-Item (Join-Path $scaffoldRoot 'assets/review-policy-guard.yml') (Join-Path $repo '.github/workflows/review-policy-guard.yml')
    Copy-Item (Join-Path $scaffoldRoot 'assets/review-policy.example.json') (Join-Path $repo '.claude/review-policy.json')

    $workflow = @'
name: CI
on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  build:
    name: Backend (.NET)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-dotnet@v6
      - run: |
          dotnet tool restore
      - run: |
          dotnet csharpier check .
      - run: |
          dotnet restore Example.sln
      - run: |
          dotnet test Example.sln --blame-hang-timeout 30s
  frontend:
    name: Frontend (UI)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - run: echo frontend
  secrets:
    name: Secrets
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - run: |
          "$RUNNER_TEMP/gitleaks" git -v --redact --log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}" .
      - run: |
          "$RUNNER_TEMP/gitleaks" dir -v --redact .
  publish:
    if: startsWith(github.ref, 'refs/tags/v')
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - name: Assert the tagged commit is reachable from main
        run: |
          set -euo pipefail
          git fetch --no-tags origin main
          if ! git merge-base --is-ancestor "$GITHUB_SHA" FETCH_HEAD; then
            echo "::error::unreviewed tag"
            exit 1
          fi
      - uses: actions/setup-dotnet@v6
      - run: dotnet pack Example.sln --no-build
  gate-coverage:
    name: Gate coverage
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
      - run: python3 .github/scripts/assert_gate_coverage.py .github/workflows/ci.yml
  ci-gate:
    name: CI Gate
    if: always()
    needs: [build, frontend, secrets, gate-coverage]
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions: {}
    steps:
      - if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')
        run: exit 1
'@
    $workflowPath = Join-Path $repo '.github/workflows/ci.yml'
    [IO.File]::WriteAllText($workflowPath, $workflow.Replace("`r`n", "`n"))
    $extended = @'
name: Extended tests
on:
  workflow_dispatch:
  schedule:
    - cron: '17 3 * * 2'
permissions:
  contents: read
jobs:
  extended-tests:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v7
      - run: dotnet test tests/Example.ExtendedTests/Example.ExtendedTests.csproj
'@
    $extendedPath = Join-Path $repo '.github/workflows/extended-tests.yml'
    [IO.File]::WriteAllText($extendedPath, $extended.Replace("`r`n", "`n"))
    $release = @'
name: Release
on:
  push:
    branches:
      - main
    tags:
      - 'v*'
permissions:
  contents: read
jobs:
  ship:
    continue-on-error: false # ancestry failures remain blocking
    name: Ship
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - name: Assert the tagged commit is reachable from main
        continue-on-error: false # ancestry failures remain blocking
        run: |
          set -euo pipefail
          # ship ancestry
          git fetch --no-tags origin main
          if ! git merge-base --is-ancestor "$GITHUB_SHA" FETCH_HEAD; then
            echo "::error::unreviewed tag"
            exit 1
          fi
      - run: dotnet pack Example.sln --no-build
  deliver:
    if: github.ref_type == 'tag'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - if: startsWith(github.ref, 'refs/tags/v')
        run: |
          set -euo pipefail
          # deliver ancestry
          git fetch --no-tags origin main
          if ! git merge-base --is-ancestor "$GITHUB_SHA" FETCH_HEAD; then
            echo "::error::unreviewed deliver tag"
            exit 1
          fi
      - run: gh release create "$GITHUB_REF_NAME"
  opaque:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - if: github.ref_type == 'tag'
        run: |
          set -euo pipefail
          # opaque ancestry
          git fetch --no-tags origin main
          if ! git merge-base --is-ancestor "$GITHUB_SHA" FETCH_HEAD; then
            echo "::error::unreviewed opaque tag"
            exit 1
          fi
      - if: github.ref_type == 'tag'
        run: npm publish
'@
    $releasePath = Join-Path $repo '.github/workflows/release.yml'
    [IO.File]::WriteAllText($releasePath, $release.Replace("`r`n", "`n"))
    $priorGateExempt = $env:GATE_EXEMPT
    $env:GATE_EXEMPT = 'publish'
    $contractArguments = @{
        RepositoryRoot = $repo
        ScaffoldRoot = $scaffoldRoot
        ActionsEvidencePath = $costEvidence
        ExpectedHeadSha = $headSha
    }
    $missingContractEvidenceFailed = $false
    try { & $contractCheck -RepositoryRoot $repo -ScaffoldRoot $scaffoldRoot -ExpectedHeadSha $headSha 2>$null | Out-Null }
    catch { $missingContractEvidenceFailed = $true }
    if (-not $missingContractEvidenceFailed) { throw 'The scaffold contract passed without measured Actions evidence.' }
    & $contractCheck @contractArguments | Out-Null
    $approvedContractArguments = $contractArguments.Clone()
    $approvedContractArguments.ActionsEvidencePath = Join-Path $fixtures 'actions-cost-over-budget-matrix.json'
    $approvedContractArguments.ApprovalPath = $validApproval
    $approvedContract = & $contractCheck @approvedContractArguments
    if ($approvedContract.Status -ne 'APPROVED_EXCEPTION') {
        throw "Approved exception was not propagated to the scaffold contract: $($approvedContract.Status)"
    }

    $mutations = [ordered]@{
        'CI Gate always semantics' = @{ Old = '    if: always()'; New = '    if: success()' }
        'CI Gate zero permissions' = @{ Old = '    permissions: {}'; New = '    permissions: contents: read' }
        'CI Gate needs coverage' = @{ Old = '    needs: [build, frontend, secrets, gate-coverage]'; New = '    needs: [build, frontend, gate-coverage]' }
        'gate coverage execution' = @{ Old = '      - run: python3 .github/scripts/assert_gate_coverage.py .github/workflows/ci.yml'; New = '      - run: echo skipped' }
        'required-job timeout' = @{ Old = "  secrets:`n    name: Secrets`n    runs-on: ubuntu-latest`n    timeout-minutes: 10"; New = "  secrets:`n    name: Secrets`n    runs-on: ubuntu-latest" }
        'every substantive job timeout' = @{ Old = "  publish:`n    if: startsWith(github.ref, 'refs/tags/v')`n    needs: build`n    runs-on: ubuntu-latest`n    timeout-minutes: 10"; New = "  publish:`n    if: startsWith(github.ref, 'refs/tags/v')`n    needs: build`n    runs-on: ubuntu-latest" }
        'per-test timeout' = @{ Old = ' --blame-hang-timeout 30s'; New = '' }
        'CSharpier job scope' = @{ Old = '          dotnet csharpier check .'; New = "          echo no-format-gate`n          # dotnet csharpier check ." }
        'every .NET backend CSharpier gate' = @{
            Old = '  secrets:'
            New = "  backend-secondary:`n    runs-on: ubuntu-latest`n    timeout-minutes: 1`n    steps:`n      - uses: actions/setup-dotnet@v6`n      - run: dotnet tool restore`n      - run: dotnet restore Secondary.sln`n      - run: dotnet test Secondary.sln --blame-hang-timeout 30s`n  secrets:"
            SecondOld = '    needs: [build, frontend, secrets, gate-coverage]'
            SecondNew = '    needs: [build, backend-secondary, frontend, secrets, gate-coverage]'
        }
        'every .NET test step timeout' = @{ Old = '          dotnet test Example.sln --blame-hang-timeout 30s'; New = "          dotnet test Example.sln --blame-hang-timeout 30s`n      - run: dotnet test Other.sln" }
        'per-test timeout job scope' = @{ Old = ' --blame-hang-timeout 30s'; New = "`n  # misplaced: --blame-hang-timeout 30s" }
        'tag ancestry job scope' = @{ Old = '          if ! git merge-base --is-ancestor "$GITHUB_SHA" FETCH_HEAD; then'; New = "          echo unsafe-publish`n  # misplaced: git merge-base --is-ancestor `"`$GITHUB_SHA`" FETCH_HEAD" }
        'tag ancestry fetch' = @{ Old = '          git fetch --no-tags origin main'; New = '          echo no-fetch' }
        'tag ancestry shell failure' = @{ Old = '          set -euo pipefail'; New = '          echo no-fail-closed-shell' }
        'tag ancestry explicit failure' = @{ Old = '            exit 1'; New = '            echo accepted' }
        'tag ancestry before restore' = @{ Old = '      - name: Assert the tagged commit is reachable from main'; New = "      - run: dotnet restore Publish.sln`n      - name: Assert the tagged commit is reachable from main" }
        'PR range secret scan job scope' = @{ Old = '          "$RUNNER_TEMP/gitleaks" git -v --redact --log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}" .'; New = '          echo no-range-scan' }
        'checked-out-tree secret scan job scope' = @{ Old = '          "$RUNNER_TEMP/gitleaks" dir -v --redact .'; New = '          echo no-tree-scan' }
        'PR range secret scan arguments' = @{ Old = '--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}" .'; New = '--log-opts="--no-merges ${HEAD_SHA}" .' }
        'checked-out-tree secret scan target' = @{ Old = '"$RUNNER_TEMP/gitleaks" dir -v --redact .'; New = '"$RUNNER_TEMP/gitleaks" dir -v --redact src' }
    }

    [IO.File]::WriteAllText($workflowPath, $workflow.Replace("`r`n", "`n"))
    [IO.File]::WriteAllText($extendedPath, $extended.Replace('timeout-minutes: 45', 'timeout-minutes: 46').Replace("`r`n", "`n"))
    $extendedFailed = $false
    try { & $contractCheck @contractArguments 2>$null | Out-Null }
    catch { $extendedFailed = $true }
    if (-not $extendedFailed) { throw 'An extended lane above 45 minutes passed the audit.' }
    [IO.File]::WriteAllText($extendedPath, $extended.Replace("`r`n", "`n"))

    foreach ($case in @(
        @{ Name = 'mixed block-list unconditional publish'; Old = "          # ship ancestry`n          git fetch --no-tags origin main"; New = "          # ship ancestry`n          echo no-fetch" },
        @{ Name = 'ref_type tag predicate'; Old = "            echo `"::error::unreviewed deliver tag`"`n            exit 1"; New = "            echo accepted deliver tag" },
        @{ Name = 'step-conditioned opaque publish'; Old = "          # opaque ancestry`n          git fetch --no-tags origin main"; New = "          # opaque ancestry`n          echo no-fetch" },
        @{ Name = 'ancestry excludes tag path'; Old = '      - name: Assert the tagged commit is reachable from main'; New = "      - name: Assert the tagged commit is reachable from main`n        if: github.ref_type != 'tag'" },
        @{ Name = 'ancestry step continues on error'; Old = "      - name: Assert the tagged commit is reachable from main`n        continue-on-error: false # ancestry failures remain blocking"; New = "      - name: Assert the tagged commit is reachable from main`n        continue-on-error: true" },
        @{ Name = 'ancestry job continues on error'; Old = "  ship:`n    continue-on-error: false # ancestry failures remain blocking`n    name: Ship"; New = "  ship:`n    continue-on-error: true`n    name: Ship" },
        @{ Name = 'ancestry step true with comment'; Old = "      - name: Assert the tagged commit is reachable from main`n        continue-on-error: false # ancestry failures remain blocking"; New = "      - name: Assert the tagged commit is reachable from main`n        continue-on-error: true # bypass" },
        @{ Name = 'ancestry job true with comment'; Old = "  ship:`n    continue-on-error: false # ancestry failures remain blocking`n    name: Ship"; New = "  ship:`n    continue-on-error: true # bypass`n    name: Ship" },
        @{ Name = 'ancestry step expression continue'; Old = "      - name: Assert the tagged commit is reachable from main`n        continue-on-error: false # ancestry failures remain blocking"; New = "      - name: Assert the tagged commit is reachable from main`n        continue-on-error: `${{ matrix.experimental }}" },
        @{ Name = 'ancestry job expression continue'; Old = "  ship:`n    continue-on-error: false # ancestry failures remain blocking`n    name: Ship"; New = "  ship:`n    continue-on-error: `${{ true }}`n    name: Ship" }
    )) {
        [IO.File]::WriteAllText($releasePath, $release.Replace($case.Old, $case.New).Replace("`r`n", "`n"))
        $releaseFailed = $false
        try { & $contractCheck @contractArguments 2>$null | Out-Null }
        catch { $releaseFailed = $true }
        if (-not $releaseFailed) { throw "A tag path failed open: $($case.Name)" }
    }
    [IO.File]::WriteAllText($releasePath, $release.Replace("`r`n", "`n"))

    $derivedScaffold = Join-Path $tempRoot 'scaffold'
    Copy-Item -LiteralPath $scaffoldRoot -Destination $derivedScaffold -Recurse
    $derivedReview = Join-Path $derivedScaffold 'references/review-policy.md'
    $reviewText = Get-Content -LiteralPath $derivedReview -Raw
    [IO.File]::WriteAllText($derivedReview, $reviewText.Replace('.github/scripts/assert_workflow_hygiene.py`.', ".github/scripts/assert_workflow_hygiene.py`,``n  `.github/scripts/new_merge_barrier.py`." ).Replace("`r`n", "`n"))
    $derivedFailed = $false
    $derivedArguments = $contractArguments.Clone()
    $derivedArguments.ScaffoldRoot = $derivedScaffold
    try { & $contractCheck @derivedArguments 2>$null | Out-Null }
    catch { $derivedFailed = $true }
    if (-not $derivedFailed) { throw 'A merge-barrier path added to scaffold-ci was not required by the audit.' }
    foreach ($mutation in $mutations.GetEnumerator()) {
        $changed = $workflow.Replace($mutation.Value.Old, $mutation.Value.New)
        if ($mutation.Value.SecondOld) { $changed = $changed.Replace($mutation.Value.SecondOld, $mutation.Value.SecondNew) }
        [IO.File]::WriteAllText($workflowPath, $changed.Replace("`r`n", "`n"))
        $failed = $false
        try { & $contractCheck @contractArguments 2>$null | Out-Null }
        catch { $failed = $true }
        if (-not $failed) { throw "Incomplete fixture passed audit: $($mutation.Key)" }
    }

    [IO.File]::WriteAllText($workflowPath, $workflow.Replace("`r`n", "`n"))
    Add-Content -LiteralPath (Join-Path $repo '.github/scripts/assert_workflow_hygiene.py') -Value '# drift'
    $hygieneFailed = $false
    try { & $contractCheck @contractArguments 2>$null | Out-Null }
    catch { $hygieneFailed = $true }
    if (-not $hygieneFailed) { throw 'A drifted workflow-hygiene checker passed the audit.' }

    Copy-Item (Join-Path $scaffoldRoot 'assets/assert_workflow_hygiene.py') (Join-Path $repo '.github/scripts/assert_workflow_hygiene.py') -Force
    $policy = Get-Content -LiteralPath (Join-Path $repo '.claude/review-policy.json') -Raw | ConvertFrom-Json
    $policy.high = @($policy.high | Where-Object { $_ -ne '.github/scripts/assert_gate_coverage.py' })
    $policy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $repo '.claude/review-policy.json')
    $policyFailed = $false
    try { & $contractCheck @contractArguments 2>$null | Out-Null }
    catch { $policyFailed = $true }
    if (-not $policyFailed) { throw 'A missing merge-barrier HIGH path passed the audit.' }

    Copy-Item (Join-Path $scaffoldRoot 'assets/review-policy.example.json') (Join-Path $repo '.claude/review-policy.json') -Force
    $guardPath = Join-Path $repo '.github/workflows/review-policy-guard.yml'
    $guard = Get-Content -LiteralPath $guardPath -Raw
    [IO.File]::WriteAllText($guardPath, $guard.Replace('run: python3 .github/scripts/assert_workflow_hygiene.py', 'run: echo skipped').Replace("`r`n", "`n"))
    $guardFailed = $false
    try { & $contractCheck @contractArguments 2>$null | Out-Null }
    catch { $guardFailed = $true }
    if (-not $guardFailed) { throw 'A guard that skips workflow hygiene passed the audit.' }

    $skill = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw
    foreach ($required in @('inventory count', 'freshness drift', 'does not change the repository verdict', 'verification timestamp')) {
        if (-not $skill.Contains($required, [StringComparison]::OrdinalIgnoreCase)) {
            throw "audit-ci guidance is missing required contract text: $required"
        }
    }

    'audit-ci mechanics OK'
}
finally {
    $env:GATE_EXEMPT = $priorGateExempt
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
