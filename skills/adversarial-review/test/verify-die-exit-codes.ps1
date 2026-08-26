#Requires -Version 7
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$spine = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-review.ps1'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("ar-die-codes-" + [Guid]::NewGuid().ToString('N'))
$workDir = Join-Path ([IO.Path]::GetTempPath()) ("ar-existing-run-" + [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
try {
    & git -C $sandbox init --quiet 2>$null
    Set-Content -LiteralPath (Join-Path $sandbox 'a.txt') -Value 'one' -Encoding utf8
    & git -C $sandbox add -A 2>$null
    & git -C $sandbox -c user.email=t@t -c user.name=t commit -m 'one' --quiet 2>$null
    Set-Content -LiteralPath (Join-Path $sandbox 'a.txt') -Value 'two' -Encoding utf8
    & git -C $sandbox add -A 2>$null
    & git -C $sandbox -c user.email=t@t -c user.name=t commit -m 'two' --quiet 2>$null

    $missing = Join-Path $sandbox 'missing.md'
    $output = & pwsh -NoProfile -File $spine -RepoPath $sandbox -ContextPath $missing 2>&1 | Out-String
    if ($LASTEXITCODE -ne 2) {
        throw "a missing context file must exit 2, got $LASTEXITCODE`n$output"
    }

    New-Item -ItemType Directory -Path $workDir | Out-Null
    '{"runIdentity":"different-run"}' | Set-Content -LiteralPath (Join-Path $workDir 'status.json') -Encoding utf8
    $output = & pwsh -NoProfile -File $spine -Target 'HEAD~1..HEAD' -RepoPath $sandbox -WorkDir $workDir 2>&1 | Out-String
    if ($LASTEXITCODE -ne 5) {
        throw "mismatched run evidence must exit 5, got $LASTEXITCODE`n$output"
    }

    'run-review.ps1 OK — fatal exit codes 2 and 5 stay distinct from 1'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
