param(
    [Parameter(Mandatory = $true)][string[]]$Topics,
    [scriptblock]$InvokeIcm = {
        param([string[]]$Arguments)
        & icm.exe @Arguments
        if ($LASTEXITCODE -ne 0) { throw "icm.exe $($Arguments[0]) failed with exit code $LASTEXITCODE" }
    }
)

foreach ($topic in $Topics) {
    try {
        $json = ((& $InvokeIcm @('list', '--topic', "$topic", '--all', '--format', 'json')) -join "`n")
        $bodies = if ([string]::IsNullOrWhiteSpace($json)) { @() } else { @($json | ConvertFrom-Json) }
        [pscustomobject]@{ Topic = $topic; Bodies = $bodies }
    } catch {
        throw "ICM recall is incomplete for topic '$topic': $($_.Exception.Message)"
    }
}
