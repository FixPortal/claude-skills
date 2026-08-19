$ErrorActionPreference = 'Stop'

$skillRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$workflowInventory = Join-Path $skillRoot 'scripts/get-workflow-inventory.ps1'
$canonicalCompare = Join-Path $skillRoot 'scripts/compare-canonical-file.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('audit-ci-mechanics-' + [guid]::NewGuid().ToString('N'))

function Assert-Equal($actual, $expected, [string] $because) {
    $actualText = @($actual) -join "`n"
    $expectedText = @($expected) -join "`n"
    if ($actualText -ne $expectedText) {
        throw "$because`nExpected:`n$expectedText`nActual:`n$actualText"
    }
}

try {
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

    $skill = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw
    foreach ($required in @('inventory count', 'freshness drift', 'does not change the repository verdict', 'verification timestamp')) {
        if (-not $skill.Contains($required, [StringComparison]::OrdinalIgnoreCase)) {
            throw "audit-ci guidance is missing required contract text: $required"
        }
    }

    'audit-ci mechanics OK'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
