#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [ValidateSet('Publication', 'Finding')]
    [string] $Mode = 'Publication',

    [string] $FindingId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string] $Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Require-Text([object] $Value, [string] $Name) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        Fail "$Name is required."
    }
}

function Require-Property([object] $Object, [string] $Name, [string] $Location) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        Fail "$Location.$Name is required."
    }
    $value = $Object.$Name
    if ($null -eq $value) { Fail "$Location.$Name is required." }
    if ($value -is [array]) { return ,$value }
    $value
}

function Require-Object([object] $Value, [string] $Name) {
    if ($Value -isnot [pscustomobject]) { Fail "$Name must be an object." }
    $Value
}

function Require-TextArray([object] $Value, [string] $Name, [bool] $AllowEmpty = $false) {
    if ($Value -isnot [array]) { Fail "$Name must be an array of text." }
    if (-not $AllowEmpty -and $Value.Count -eq 0) { Fail "$Name must be a non-empty array of text." }
    if (@($Value | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        Fail "$Name must be an array of text."
    }
    return ,$Value
}

function Require-IsoTimestamp([System.Text.Json.JsonElement] $Audit, [string] $Name) {
    try { $element = $Audit.GetProperty($Name) }
    catch { Fail "audit.$Name is required." }
    if ($element.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { Fail "audit.$Name must be an ISO-8601 timestamp with UTC or offset." }
    $value = $element.GetString()
    if ($value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
        Fail "audit.$Name must be an ISO-8601 timestamp with UTC or offset."
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref] $parsed)) {
        Fail "audit.$Name must be an ISO-8601 timestamp with UTC or offset."
    }
    $parsed
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fail "Manifest '$Path' does not exist."
}

try {
    $manifestJson = Get-Content -LiteralPath $Path -Raw
    $manifest = $manifestJson | ConvertFrom-Json -NoEnumerate
    $manifestDocument = [System.Text.Json.JsonDocument]::Parse($manifestJson)
}
catch {
    Fail "Manifest '$Path' is not valid JSON: $($_.Exception.Message)"
}

if ($null -eq $manifest -or $manifest -is [array]) { Fail 'Manifest must be a JSON object.' }
$schemaVersion = Require-Property $manifest 'schemaVersion' 'manifest'
if ($schemaVersion -isnot [long] -or $schemaVersion -ne 1) { Fail 'schemaVersion must be the number 1.' }

$repository = Require-Property $manifest 'repository' 'manifest'
if ($repository -isnot [pscustomobject]) { Fail 'repository must be an object.' }
Require-Text (Require-Property $repository 'path' 'repository') 'repository.path'
Require-Text (Require-Property $repository 'head' 'repository') 'repository.head'
Require-Text (Require-Property $repository 'branch' 'repository') 'repository.branch'

$audit = Require-Property $manifest 'audit' 'manifest'
if ($audit -isnot [pscustomobject]) { Fail 'audit must be an object.' }
$auditElement = $manifestDocument.RootElement.GetProperty('audit')
if ($auditElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { Fail 'audit must be an object.' }
$startedUtc = Require-IsoTimestamp $auditElement 'startedUtc'
$completedUtc = Require-IsoTimestamp $auditElement 'completedUtc'
if ($completedUtc -lt $startedUtc) { Fail 'audit.completedUtc must be greater than or equal to audit.startedUtc.' }
if ((Require-Property $audit 'targetStateUnchanged' 'audit') -isnot [bool] -or -not $audit.targetStateUnchanged) {
    Fail 'audit.targetStateUnchanged must be true.'
}

$findings = Require-Property $manifest 'findings' 'manifest'
if ($findings -isnot [array]) { Fail 'findings must be an array.' }
$classifications = 'Observed bottleneck', 'Benchmarked improvement', 'Production-correlated', 'Static opportunity', 'Unmeasured', 'Rejected experiment'
$confidences = 'High', 'Moderate', 'Low', 'Indeterminate'
$canonicalProductBoundaryExclusions = 'unsafe', 'System.Runtime.Intrinsics', 'DllImport', 'LibraryImport', 'PInvoke', 'native binaries', 'native-dependent packages', 'custom native allocators', 'undocumented runtime switches', 'runtime-private APIs', 'reflection/runtime patching'
$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($finding in $findings) {
    if ($finding -isnot [pscustomobject]) { Fail 'Each finding must be an object.' }
    $id = Require-Property $finding 'id' 'finding'
    Require-Text $id 'finding.id'
    if ($id -notmatch '^PERF-\d{3}$') { Fail "finding.id '$id' must match PERF-NNN." }
    if (-not $ids.Add($id)) { Fail "finding.id '$id' is duplicate." }
    Require-Text (Require-Property $finding 'title' 'finding') 'finding.title'
    $classification = Require-Property $finding 'classification' 'finding'
    Require-Text $classification 'finding.classification'
    if ($classifications -cnotcontains $classification) { Fail "finding.classification '$classification' is invalid." }
    $confidence = Require-Property $finding 'confidence' 'finding'
    Require-Text $confidence 'finding.confidence'
    if ($confidences -cnotcontains $confidence) { Fail "finding.confidence '$confidence' is invalid." }
    $resolutionState = Require-Property $finding 'resolutionState' 'finding'
    Require-Text $resolutionState 'finding.resolutionState'
    if ($resolutionState -cne 'unresolved') { Fail 'finding.resolutionState must be unresolved.' }
    Require-TextArray (Require-Property $finding 'evidence' 'finding') 'finding.evidence' | Out-Null
    Require-Text (Require-Property $finding 'project' 'finding') 'finding.project'
    Require-TextArray (Require-Property $finding 'files' 'finding') 'finding.files' | Out-Null
    Require-TextArray (Require-Property $finding 'symbols' 'finding') 'finding.symbols' | Out-Null
    $workload = Require-Object (Require-Property $finding 'workload' 'finding') 'finding.workload'
    Require-Text (Require-Property $workload 'id' 'finding.workload') 'finding.workload.id'
    Require-Text (Require-Property $workload 'baseline' 'finding.workload') 'finding.workload.baseline'
    Require-Text (Require-Property $finding 'attributedMechanism' 'finding') 'finding.attributedMechanism'
    Require-Text (Require-Property $finding 'proposedExperiment' 'finding') 'finding.proposedExperiment'
    Require-TextArray (Require-Property $finding 'correctnessInvariants' 'finding') 'finding.correctnessInvariants' | Out-Null
    Require-TextArray (Require-Property $finding 'expectedTradeoffs' 'finding') 'finding.expectedTradeoffs' | Out-Null
    Require-Text (Require-Property $finding 'materialityThreshold' 'finding') 'finding.materialityThreshold'
    $commands = Require-Object (Require-Property $finding 'commands' 'finding') 'finding.commands'
    Require-Text (Require-Property $commands 'baseline' 'finding.commands') 'finding.commands.baseline'
    Require-Text (Require-Property $commands 'candidate' 'finding.commands') 'finding.commands.candidate'
    Require-TextArray (Require-Property $finding 'requiredTools' 'finding') 'finding.requiredTools' $true | Out-Null
    Require-TextArray (Require-Property $finding 'requiredArtifacts' 'finding') 'finding.requiredArtifacts' $true | Out-Null
    $cost = Require-Object (Require-Property $finding 'cost' 'finding') 'finding.cost'
    Require-TextArray (Require-Property $cost 'inputs' 'finding.cost') 'finding.cost.inputs' $true | Out-Null
    Require-TextArray (Require-Property $cost 'missingInputs' 'finding.cost') 'finding.cost.missingInputs' $true | Out-Null
    $productBoundary = Require-Object (Require-Property $finding 'productBoundary' 'finding') 'finding.productBoundary'
    $allowedBoundary = Require-Property $productBoundary 'allowed' 'finding.productBoundary'
    Require-Text $allowedBoundary 'finding.productBoundary.allowed'
    if ($allowedBoundary -cne 'managed-public-api') { Fail 'finding.productBoundary.allowed must be managed-public-api.' }
    $exclusions = Require-TextArray (Require-Property $productBoundary 'exclusions' 'finding.productBoundary') 'finding.productBoundary.exclusions'
    foreach ($exclusion in $canonicalProductBoundaryExclusions) {
        if ($exclusions -cnotcontains $exclusion) { Fail "finding.productBoundary.exclusions must include '$exclusion'." }
    }
    Require-TextArray (Require-Property $finding 'acceptanceConditions' 'finding') 'finding.acceptanceConditions' | Out-Null
    Require-TextArray (Require-Property $finding 'rejectionConditions' 'finding') 'finding.rejectionConditions' | Out-Null
    Require-Text (Require-Property $finding 'rollbackExpectation' 'finding') 'finding.rollbackExpectation'
}

if ($Mode -eq 'Finding') {
    Require-Text $FindingId 'FindingId'
    $finding = @($findings | Where-Object id -ceq $FindingId)
    if ($finding.Count -eq 0) { Fail "FindingId '$FindingId' was not found." }
    [pscustomobject]@{ repository = $repository; finding = $finding[0] } | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

[pscustomobject]@{ valid = $true } | ConvertTo-Json -Compress
