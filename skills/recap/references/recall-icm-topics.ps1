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
        [pscustomobject]@{ Topic = $topic; Bodies = $bodies; Failed = $false; Error = $null }
    } catch {
        # Per the recap contract: use NO context for the failed topic and never treat a partial
        # result as complete. Rethrowing here would terminate the loop and silently drop the
        # remaining topics' recall — worse than the single-topic gap. Emit an explicitly failed,
        # empty result and continue; the caller records the gap in journal detail.
        Write-Warning "ICM recall failed for topic '$topic': $($_.Exception.Message)"
        [pscustomobject]@{ Topic = $topic; Bodies = @(); Failed = $true; Error = $_.Exception.Message }
    }
}
