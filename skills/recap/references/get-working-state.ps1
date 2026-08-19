param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

$ErrorActionPreference = 'Stop'

# Make the explicit $LASTEXITCODE check below the ONLY failure signal, independent of the
# caller's session. When $PSNativeCommandUseErrorActionPreference is $true, a native
# command's nonzero exit raises a NativeCommandError before that check runs, replacing a
# message naming the repository and git's own output with a generic one. Measured on pwsh
# 7.6.3 the preference is already $false and the intended check fires - this pin is so
# that stays true under a caller profile, or a future default, that flips it.
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-GitOrThrow {
    <#
      Every git call here is checked, because the failure mode is indistinguishable from
      success. $ErrorActionPreference = 'Stop' does NOT terminate on a native nonzero
      exit, so an unchecked `git status --short` in a path that is not a repository
      returns nothing - and empty status, empty staged stat, empty unstaged stat is
      precisely what a clean tree looks like. Recap would then reconstruct "nothing in
      progress" from a lookup that never ran.
    #>
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        throw "git $($Arguments -join ' ') failed in '$RepositoryRoot' (exit $LASTEXITCODE): $detail"
    }
    ($output | ForEach-Object { [string]$_ }) -join "`n"
}

[pscustomobject]@{
    Status = Invoke-GitOrThrow -Arguments @('status', '--short')
    StagedStat = Invoke-GitOrThrow -Arguments @('diff', '--cached', '--stat')
    UnstagedStat = Invoke-GitOrThrow -Arguments @('diff', '--stat')
}
