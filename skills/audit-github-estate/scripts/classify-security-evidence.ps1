[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EvidencePath,
    [string] $ConfigurationPath
)

$ErrorActionPreference = 'Stop'
$evidence = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
$findings = [Collections.Generic.List[string]]::new()
$gaps = [Collections.Generic.List[string]]::new()

function Convert-Envelope($response, [string] $name, [int[]] $statuses = @(200)) {
    if ($null -eq $response) { return [pscustomobject]@{ Success = $false; Error = "$name response is missing"; Body = $null } }
    if ($response.PSObject.Properties.Name -notcontains 'exit_code') {
        return [pscustomobject]@{ Success = $false; Error = "$name response omitted exit_code"; Body = $null }
    }
    if ($response.PSObject.Properties.Name -notcontains 'http_status') {
        return [pscustomobject]@{ Success = $false; Error = "$name response omitted http_status"; Body = $null }
    }
    if ([int] $response.exit_code -ne 0) {
        return [pscustomobject]@{ Success = $false; Error = "$name gh call failed with exit $($response.exit_code)"; Body = $null }
    }
    if ([int] $response.http_status -notin $statuses) {
        return [pscustomobject]@{ Success = $false; Error = "$name returned HTTP $($response.http_status)"; Body = $null }
    }
    if ($response.PSObject.Properties.Name -notcontains 'body_json' -or $null -eq $response.body_json) {
        return [pscustomobject]@{ Success = $false; Error = "$name response omitted body_json"; Body = $null }
    }
    try {
        $body = if ([string]::Equals(([string] $response.body_json).Trim(), '[]', [StringComparison]::Ordinal)) { @() } else { $response.body_json | ConvertFrom-Json }
        [pscustomobject]@{ Success = $true; Error = ''; Body = $body }
    }
    catch { [pscustomobject]@{ Success = $false; Error = "$name returned malformed JSON"; Body = $null } }
}

function Read-Response($response, [string] $name, [int[]] $statuses = @(200)) {
    $result = Convert-Envelope $response $name $statuses
    if (-not $result.Success) { $gaps.Add($result.Error) }
    $result
}

function Require-State($object, [string] $path, [string] $expected, [string] $surface) {
    $value = $object
    foreach ($part in $path.Split('.')) {
        if ($null -eq $value -or $value.PSObject.Properties.Name -notcontains $part) {
            $gaps.Add("$surface omitted applicable field $path")
            return
        }
        $value = $value.$part
    }
    if ([string] $value -ne $expected) {
        $findings.Add("$surface $path is '$value', expected '$expected'")
    }
}

$hasDefaultSha = $evidence.PSObject.Properties.Name -contains 'default_branch_sha' -and
    -not [string]::IsNullOrWhiteSpace([string] $evidence.default_branch_sha)
if (-not $hasDefaultSha) { $gaps.Add('default_branch_sha is missing') }
$defaultSha = if ($hasDefaultSha) { [string] $evidence.default_branch_sha } else { $null }

$repositoryResponse = Read-Response $evidence.repository 'repository'
$repository = $null
if ($repositoryResponse.Success) {
    $repositoryJson = ([string] $evidence.repository.body_json).TrimStart()
    if (-not $repositoryJson.StartsWith('{', [StringComparison]::Ordinal) -or $repositoryResponse.Body -isnot [pscustomobject]) {
        $gaps.Add('repository response body must be a JSON object')
    }
    else { $repository = $repositoryResponse.Body }
}
$hasFullName = $repository -and $repository.PSObject.Properties.Name -contains 'full_name' -and
    -not [string]::IsNullOrWhiteSpace([string] $repository.full_name)
if ($repository -and -not $hasFullName) { $gaps.Add('repository omitted full_name') }
$hasOwnerType = $repository -and $repository.PSObject.Properties.Name -contains 'owner' -and $null -ne $repository.owner -and
    $repository.owner.PSObject.Properties.Name -contains 'type' -and
    -not [string]::IsNullOrWhiteSpace([string] $repository.owner.type)
if ($repository -and -not $hasOwnerType) { $gaps.Add('repository omitted owner.type') }
$fullName = if ($hasFullName) { [string] $repository.full_name } else { '' }
$visibility = if ($repository) { [string] $repository.visibility } else { '' }
$ownerType = if ($hasOwnerType) { [string] $repository.owner.type } else { '' }

if ($repository) {
    if ($visibility -eq 'public') {
        foreach ($field in 'secret_scanning', 'secret_scanning_push_protection', 'secret_scanning_non_provider_patterns', 'secret_scanning_validity_checks') {
            Require-State $repository "security_and_analysis.$field.status" 'enabled' 'repository'
        }
    }
    elseif ($visibility -in @('private', 'internal')) {
        foreach ($field in 'code_security', 'secret_scanning', 'secret_scanning_push_protection', 'secret_scanning_non_provider_patterns', 'secret_scanning_validity_checks') {
            Require-State $repository "security_and_analysis.$field.status" 'disabled' 'repository'
        }
    }
    else { $gaps.Add("repository visibility is unknown: '$visibility'") }
}

if ($visibility -eq 'public') {
    $attachment = Read-Response $evidence.code_security_configuration 'code-security configuration attachment'
    if ($attachment.Success) { Require-State $attachment.Body 'status' 'attached' 'code-security configuration attachment' }

    $defaultSetup = Read-Response $evidence.code_scanning_default_setup 'Code Scanning default setup'
    if ($defaultSetup.Success) { Require-State $defaultSetup.Body 'state' 'configured' 'Code Scanning default setup' }

    $analysis = Read-Response $evidence.code_scanning_analysis 'Code Scanning analysis'
    if ($analysis.Success) {
        if ($analysis.Body.PSObject.Properties.Name -notcontains 'commit_sha' -or [string]::IsNullOrWhiteSpace([string] $analysis.Body.commit_sha)) {
            $gaps.Add('Code Scanning analysis omitted commit_sha')
        }
        elseif ($hasDefaultSha -and [string] $analysis.Body.commit_sha -ne $defaultSha) {
            $gaps.Add('Code Scanning analysis commit_sha is stale')
        }
    }

    if (-not $ConfigurationPath) { $gaps.Add('public security configuration response is missing') }
    else {
        $configurationEnvelope = Get-Content -LiteralPath $ConfigurationPath -Raw | ConvertFrom-Json
        $configuration = Read-Response $configurationEnvelope 'public security configuration'
        if ($configuration.Success) {
            if ($attachment.Success) {
                $comparableIdentity = $false
                $matchingIdentity = $false
                foreach ($field in 'id', 'name') {
                    $attachmentHasField = $attachment.Body.PSObject.Properties.Name -contains $field -and
                        -not [string]::IsNullOrWhiteSpace([string] $attachment.Body.$field)
                    $configurationHasField = $configuration.Body.PSObject.Properties.Name -contains $field -and
                        -not [string]::IsNullOrWhiteSpace([string] $configuration.Body.$field)
                    if ($attachmentHasField -and $configurationHasField) {
                        $comparableIdentity = $true
                        if ([string] $attachment.Body.$field -eq [string] $configuration.Body.$field) { $matchingIdentity = $true }
                    }
                }
                if (-not $comparableIdentity) { $gaps.Add('Public configuration attachment identity cannot be correlated') }
                elseif (-not $matchingIdentity) { $findings.Add('Attached code-security configuration does not match the required public configuration') }
            }

            $targets = [ordered]@{
                code_scanning_default_setup = 'enabled'
                code_scanning_delegated_alert_dismissal = 'disabled'
                secret_scanning = 'enabled'
                secret_scanning_push_protection = 'enabled'
                secret_scanning_validity_checks = 'enabled'
                secret_scanning_non_provider_patterns = 'enabled'
                secret_scanning_generic_secrets = 'enabled'
                secret_scanning_delegated_alert_dismissal = 'disabled'
                secret_scanning_extended_metadata = 'enabled'
                secret_scanning_delegated_bypass = 'disabled'
                private_vulnerability_reporting = 'enabled'
            }
            foreach ($target in $targets.GetEnumerator()) {
                Require-State $configuration.Body $target.Key $target.Value 'public security configuration'
            }
        }
    }

    $secretAlerts = $null
    $repoAlerts = Convert-Envelope $evidence.secret_scanning_repository_alerts 'repository secret-scanning alerts'
    if ($repoAlerts.Success) { $secretAlerts = @($repoAlerts.Body).Count }
    elseif ($ownerType -eq 'Organization') {
        $orgAlerts = Convert-Envelope $evidence.secret_scanning_organization_alerts 'organization secret-scanning alerts'
        if ($orgAlerts.Success) {
            $secretAlerts = @($orgAlerts.Body | Where-Object { $_.repository.full_name -eq $fullName }).Count
        }
    }
    if ($null -eq $secretAlerts) { $gaps.Add('Secret scanning alert inventory is unavailable after capability probes') }
}
elseif ($visibility -in @('private', 'internal')) {
    $attachment = $evidence.code_security_configuration
    $attachmentExitCode = 0
    $attachmentHttpStatus = 0
    if ($null -eq $attachment) { $gaps.Add('code-security configuration attachment response is missing') }
    elseif ($attachment.PSObject.Properties.Name -notcontains 'exit_code') { $gaps.Add('code-security configuration attachment response omitted exit_code') }
    elseif ($attachment.PSObject.Properties.Name -notcontains 'http_status') { $gaps.Add('code-security configuration attachment response omitted http_status') }
    elseif (-not ([int]::TryParse([string] $attachment.exit_code, [ref] $attachmentExitCode) -and
        [int]::TryParse([string] $attachment.http_status, [ref] $attachmentHttpStatus))) {
        $gaps.Add('code-security configuration attachment response has non-numeric exit_code/http_status')
    }
    elseif ($attachmentExitCode -eq 0 -and $attachmentHttpStatus -eq 204) { }
    elseif ($attachmentExitCode -eq 0 -and $attachmentHttpStatus -eq 200) {
        $findings.Add('Private/internal repository has a code-security configuration attached')
    }
    else { $gaps.Add("code-security configuration attachment probe failed with exit $($attachment.exit_code), HTTP $($attachment.http_status)") }
    $secretAlerts = 0
}
else { $secretAlerts = 0 }

$actions = Read-Response $evidence.actions_run 'Actions run'
if ($actions.Success) {
    if ($actions.Body.PSObject.Properties.Name -notcontains 'head_sha' -or [string]::IsNullOrWhiteSpace([string] $actions.Body.head_sha)) {
        $gaps.Add('Actions run omitted head_sha')
    }
    elseif ($hasDefaultSha -and [string] $actions.Body.head_sha -ne $defaultSha) { $gaps.Add('Actions run head_sha is stale') }
    if ([string] $actions.Body.conclusion -ne 'success') { $gaps.Add("Actions run is $($actions.Body.conclusion)") }
}

$orgAccessPresent = $evidence.PSObject.Properties.Name -contains 'code_quality_org_access' -and
    -not [string]::IsNullOrWhiteSpace([string] $evidence.code_quality_org_access)
if (-not $orgAccessPresent) { $gaps.Add('Code Quality org access evidence is missing') }
elseif ([string] $evidence.code_quality_org_access -eq 'UNVERIFIED') { $gaps.Add('Code Quality org access is UNVERIFIED') }
elseif ([string] $evidence.code_quality_org_access -notin @('VERIFIED_NO_REPOSITORIES', 'VERIFIED_APPROVED')) {
    $gaps.Add("Code Quality org access evidence is unknown: '$($evidence.code_quality_org_access)'")
}

$codeQuality = Read-Response $evidence.code_quality_setup 'Code Quality setup'
if ($codeQuality.Success) {
    $state = [string] $codeQuality.Body.state
    $approved = $evidence.PSObject.Properties.Name -contains 'code_quality_paid_approved' -and
        $evidence.code_quality_paid_approved -eq $true -and
        [string] $evidence.code_quality_org_access -eq 'VERIFIED_APPROVED'
    if ($state -eq 'configured' -and $approved) {
        Require-State $codeQuality.Body 'ai_findings_option' 'disabled' 'Code Quality setup'
    }
    elseif ($state -eq 'configured') { $findings.Add('Code Quality is configured without approved paid use') }
    elseif ($state -ne 'not-configured') { $gaps.Add("Code Quality setup has unknown state '$state'") }
}

$status = if ($findings.Count) { 'NONCOMPLIANT' } elseif ($gaps.Count) { 'INCOMPLETE' } else { 'ACCOUNTED_FOR' }
[pscustomobject]@{
    Status = $status
    Findings = @($findings)
    EvidenceGaps = @($gaps)
    SecretAlerts = $secretAlerts
} | ConvertTo-Json -Depth 5
