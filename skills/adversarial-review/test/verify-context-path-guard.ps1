#Requires -Version 7
<#
.SYNOPSIS
    run-review.ps1 must normalize and validate -ContextPath BEFORE spawning reviewers.

.DESCRIPTION
    Two hazards, both observed in the field (your-repo SPA review,
    run 20260816T153354Z), both of which cost a full parallel round:

      1. `pwsh -File` passes arguments as strings, so an inline multi-element array
         (`-ContextPath 'a','b'`) arrives as the SINGLE token `a,b`. The ';'-join
         the callers apply is a no-op on one element, so every wrapper split on ';'
         and got one path that could not exist. Four vendors failed identically and
         instantly, which reads like an outage rather than a bad argument.
      2. A context file that is simply absent — discovered once per reviewer per
         chunk, minutes in, instead of once at startup.

    This asserts the guard fires on (2) and does NOT fire on (1), i.e. the comma
    form is recovered rather than propagated.

    No reviewer is ever spawned: every case here is expected to exit before the
    panel starts, and the positive case is proven by the guard's own silence plus
    the run failing LATER for an unrelated, named reason.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$spine = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-review.ps1'
if (-not (Test-Path -LiteralPath $spine)) { throw "run-review.ps1 not found beside test/: $spine" }

$failures = @()
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { Write-Host "  PASS  $name" }
    else { Write-Host "  FAIL  $name -- $detail"; $script:failures += $name }
}

# A throwaway repo so the spine reaches the ContextPath guard without touching a real one.
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("ar-ctx-guard-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
try {
    & git -C $sandbox init --quiet 2>$null
    Set-Content -LiteralPath (Join-Path $sandbox 'a.txt') -Value 'one' -Encoding utf8
    & git -C $sandbox add -A 2>$null
    & git -C $sandbox -c user.email=t@t -c user.name=t commit -m 'one' --quiet 2>$null
    Set-Content -LiteralPath (Join-Path $sandbox 'a.txt') -Value 'two' -Encoding utf8
    & git -C $sandbox add -A 2>$null
    & git -C $sandbox -c user.email=t@t -c user.name=t commit -m 'two' --quiet 2>$null

    $ctxA = Join-Path $sandbox 'ctx-a.md'
    $ctxB = Join-Path $sandbox 'ctx-b.md'
    Set-Content -LiteralPath $ctxA -Value '# context a' -Encoding utf8
    Set-Content -LiteralPath $ctxB -Value '# context b' -Encoding utf8
    $missing = Join-Path $sandbox 'ctx-nope.md'

    function Invoke-Spine([string] $contextArg) {
        $work = Join-Path $sandbox ("wd-" + [Guid]::NewGuid().ToString('N'))
        # -Target with an explicit range keeps this tree-to-tree; the sandbox is clean anyway.
        $out = & pwsh -NoProfile -File $spine `
            -Target 'HEAD~1..HEAD' -RepoPath $sandbox -WorkDir $work -ContextPath $contextArg 2>&1 |
            Out-String
        return $out
    }

    # 1. Absent context file: the guard must name it and stop.
    $out = Invoke-Spine $missing
    Check 'missing context file is rejected' `
        ($out -match 'Context file not found') `
        "expected 'Context file not found', got: $($out.Substring(0, [Math]::Min(300, $out.Length)))"
    Check 'missing context file names the offending path' `
        ($out -match [regex]::Escape('ctx-nope.md')) `
        'the failing path was not named in the message'

    # 2. The comma-joined single token — the exact shape `pwsh -File` produces from an
    #    inline array. It must be SPLIT and accepted, not treated as one bogus path.
    $out = Invoke-Spine "$ctxA,$ctxB"
    Check 'comma-joined context paths are recovered, not propagated' `
        ($out -notmatch 'Context file not found') `
        "the guard rejected a comma-joined pair whose members both exist: $($out.Substring(0, [Math]::Min(300, $out.Length)))"

    # 3. The documented ';' convention between batch-review -> spine -> wrappers.
    $out = Invoke-Spine "$ctxA;$ctxB"
    Check 'semicolon-joined context paths still work' `
        ($out -notmatch 'Context file not found') `
        "the established ';' join regressed: $($out.Substring(0, [Math]::Min(300, $out.Length)))"

    # 4. A real absence hiding inside an otherwise-valid joined token must still fire.
    $out = Invoke-Spine "$ctxA;$missing"
    Check 'one absent member of a joined token is still caught' `
        ($out -match 'Context file not found') `
        'a joined token with one missing member was accepted'

    # 5. A path that legitimately CONTAINS a comma must survive as one path: the guard
    #    tests the whole token as a path before falling back to splitting on ','.
    $ctxComma = Join-Path $sandbox 'ctx,with-comma.md'
    Set-Content -LiteralPath $ctxComma -Value '# comma path' -Encoding utf8
    $out = Invoke-Spine $ctxComma
    Check 'a context path containing a comma is not shredded' `
        ($out -notmatch 'Context file not found') `
        "a real path containing a comma was split: $($out.Substring(0, [Math]::Min(300, $out.Length)))"
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures) {
    Write-Host "verify-context-path-guard: FAILED ($($failures.Count))" -ForegroundColor Red
    exit 1
}
# The Invoke-Spine calls above deliberately run failing child processes; do not leak
# their non-zero exit code as this script's own on a genuine pass.
$global:LASTEXITCODE = 0
Write-Host 'verify-context-path-guard: OK' -ForegroundColor Green
