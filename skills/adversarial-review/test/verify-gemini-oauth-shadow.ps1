$ErrorActionPreference = 'Stop'

# Windows-only by construction: the fixture CLI is a .cmd batch file and the wrapper under
# test resolves the OAuth credential store through %USERPROFILE%.
if (-not $IsWindows) {
    Write-Host 'SKIP: gemini OAuth shadow test is Windows-only (batch-file fixture CLI)'
    return
}

$root = Join-Path $PSScriptRoot '..'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ar-gemini-oauth-' + [Guid]::NewGuid().ToString('N'))
$fakeHome = Join-Path $tempRoot 'home'
$geminiDir = Join-Path $fakeHome '.gemini'
$fakeBin = Join-Path $tempRoot 'bin'
$oldProfile = $env:USERPROFILE
$oldPath = $env:PATH
$oldKey = $env:GEMINI_API_KEY

try {
    New-Item -ItemType Directory -Path $geminiDir, $fakeBin | Out-Null
    $oauth = Join-Path $geminiDir 'oauth_creds.json'
    $fixedCollision = Join-Path $geminiDir 'oauth_creds.json.paused'
    Set-Content -LiteralPath $oauth -Value 'original-oauth' -Encoding utf8
    Set-Content -LiteralPath $fixedCollision -Value 'pre-existing-backup' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fakeBin 'gemini.cmd') -Encoding ascii -Value @(
        '@echo off',
        'echo {"response":"fixture response"}',
        'exit /b 0'
    )
    $diff = Join-Path $tempRoot 'diff.txt'
    $out = Join-Path $tempRoot 'out.txt'
    Set-Content -LiteralPath $diff -Value '+fixture' -Encoding utf8

    $env:USERPROFILE = $fakeHome
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $oldPath
    $env:GEMINI_API_KEY = 'fixture-key'
    & pwsh -NoProfile -File (Join-Path $root 'gemini-review.ps1') -Instruction 'Review.' -DiffPath $diff -OutPath $out
    if ($LASTEXITCODE -ne 0) { throw "gemini-review fixture exited $LASTEXITCODE" }

    if ((Get-Content -LiteralPath $oauth -Raw).Trim() -ne 'original-oauth') {
        throw 'OAuth credentials were not restored exactly'
    }
    if ((Get-Content -LiteralPath $fixedCollision -Raw).Trim() -ne 'pre-existing-backup') {
        throw 'pre-existing fixed .paused backup was overwritten'
    }
    if (Get-ChildItem -LiteralPath $geminiDir -Filter 'oauth_creds.json.paused*' -File |
        Where-Object FullName -ne $fixedCollision) {
        throw 'unique per-run OAuth backup remained after successful restore'
    }

    'gemini-review OAuth shadow OK — fixed collision preserved, unique backup restored'
}
finally {
    $env:USERPROFILE = $oldProfile
    $env:PATH = $oldPath
    $env:GEMINI_API_KEY = $oldKey
    if ($tempRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
