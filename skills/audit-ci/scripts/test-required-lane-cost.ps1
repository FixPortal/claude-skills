[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EvidencePath,
    [Parameter(Mandatory)] [string] $ExpectedHeadSha,
    [Parameter(Mandatory)] [string[]] $RequiredJobNames,
    [Parameter(Mandatory)] [double] $BudgetMinutes,
    [string] $ApprovalPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $EvidencePath)) { throw "Required-lane cost evidence is missing: $EvidencePath" }
if ([string]::IsNullOrWhiteSpace($ExpectedHeadSha)) { throw 'Expected head SHA is missing.' }
if ($BudgetMinutes -le 0) { throw 'Required-lane budget must be positive.' }
$required = @($RequiredJobNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if (-not $required.Count) { throw 'Required job names are missing.' }

try { $evidence = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json }
catch { throw "Required-lane cost evidence is malformed JSON: $($_.Exception.Message)" }
if ($evidence -isnot [pscustomobject]) { throw 'Required-lane cost evidence must be a JSON object.' }
if ($evidence.PSObject.Properties.Name -notcontains 'run' -or $evidence.run -isnot [pscustomobject]) {
    throw 'Required-lane cost evidence omitted the run object.'
}
if ($evidence.run.PSObject.Properties.Name -notcontains 'head_sha' -or
    [string]::IsNullOrWhiteSpace([string] $evidence.run.head_sha)) {
    throw 'Required-lane cost evidence omitted run head_sha.'
}
if ($evidence.run.PSObject.Properties.Name -notcontains 'id' -or
    ($evidence.run.id -isnot [int] -and $evidence.run.id -isnot [long]) -or
    [long] $evidence.run.id -le 0) {
    throw 'Required-lane cost evidence omitted a valid run id.'
}
if ([string] $evidence.run.head_sha -ne $ExpectedHeadSha) { throw 'Required-lane cost evidence head_sha is stale.' }
if ($evidence.run.PSObject.Properties.Name -notcontains 'conclusion' -or
    [string] $evidence.run.conclusion -ne 'success') {
    throw 'Required-lane cost evidence is not from a successful completed run.'
}
if ($evidence.PSObject.Properties.Name -notcontains 'jobs' -or $null -eq $evidence.jobs) {
    throw 'Required-lane cost evidence omitted jobs.'
}
if ($evidence.PSObject.Properties.Name -notcontains 'total_count' -or
    ($evidence.total_count -isnot [int] -and $evidence.total_count -isnot [long]) -or
    [long] $evidence.total_count -lt 0) {
    throw 'Required-lane cost evidence has an invalid jobs total_count.'
}

$jobs = @($evidence.jobs)
if ($jobs.Count -ne [long] $evidence.total_count) {
    throw "Required-lane cost evidence is incomplete: received $($jobs.Count) of $($evidence.total_count) jobs."
}
$counted = [Collections.Generic.List[object]]::new()
foreach ($requiredName in $required) {
    $legs = @($jobs | Where-Object {
        $_ -is [pscustomobject] -and $_.PSObject.Properties.Name -contains 'name' -and
        ([string] $_.name -eq $requiredName -or ([string] $_.name).StartsWith("$requiredName (", [StringComparison]::Ordinal))
    })
    if (-not $legs.Count) { throw "Required-lane cost evidence omitted job '$requiredName' and its matrix legs." }
    foreach ($job in $legs) {
        foreach ($field in 'started_at', 'completed_at', 'conclusion') {
            if ($job.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string] $job.$field)) {
                throw "Required job '$($job.name)' omitted $field."
            }
        }
        if ([string] $job.conclusion -ne 'success') { throw "Required job '$($job.name)' did not conclude successfully." }
        try {
            $started = [DateTimeOffset]::Parse([string] $job.started_at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $completed = [DateTimeOffset]::Parse([string] $job.completed_at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        }
        catch { throw "Required job '$($job.name)' has an invalid duration timestamp." }
        if ($completed -le $started) { throw "Required job '$($job.name)' has a non-positive measured duration." }
        $counted.Add([pscustomobject]@{ Name = [string] $job.name; Minutes = ($completed - $started).TotalMinutes })
    }
}

$aggregate = [Math]::Round([double] (($counted | Measure-Object -Property Minutes -Sum).Sum), 3)
$approval = $null
if ($aggregate -gt $BudgetMinutes) {
    if ([string]::IsNullOrWhiteSpace($ApprovalPath) -or -not (Test-Path -LiteralPath $ApprovalPath)) {
        throw "Required-lane measured cost is $aggregate minutes; target is $BudgetMinutes and structured owner approval evidence is missing."
    }
    try { $approval = Get-Content -LiteralPath $ApprovalPath -Raw | ConvertFrom-Json }
    catch { throw "Owner approval evidence is malformed JSON: $($_.Exception.Message)" }
    if ($approval -isnot [pscustomobject]) { throw 'Owner approval evidence must be a JSON object.' }
    foreach ($field in 'approved', 'owner', 'approved_at', 'head_sha', 'run_id') {
        if ($approval.PSObject.Properties.Name -notcontains $field) { throw "Owner approval evidence omitted $field." }
    }
    if ($approval.approved -isnot [bool] -or -not $approval.approved) { throw 'Owner approval evidence is not explicitly approved.' }
    if ([string]::IsNullOrWhiteSpace([string] $approval.owner)) { throw 'Owner approval evidence has no owner.' }
    try { [DateTimeOffset]::Parse([string] $approval.approved_at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) | Out-Null }
    catch { throw 'Owner approval evidence has an invalid approved_at timestamp.' }
    if ([string]::IsNullOrWhiteSpace([string] $approval.head_sha) -or [string] $approval.head_sha -ne $ExpectedHeadSha) {
        throw 'Owner approval evidence head_sha is missing or stale.'
    }
    if (($approval.run_id -isnot [int] -and $approval.run_id -isnot [long]) -or
        [long] $approval.run_id -ne [long] $evidence.run.id) {
        throw 'Owner approval evidence run_id is missing or stale.'
    }
}

[pscustomobject]@{
    Status = if ($aggregate -gt $BudgetMinutes) { 'APPROVED_EXCEPTION' } else { 'COMPLIANT' }
    AggregateMinutes = $aggregate
    CountedJobs = $counted.Count
    HeadSha = $ExpectedHeadSha
    RunId = [long] $evidence.run.id
    Approval = $approval
}
