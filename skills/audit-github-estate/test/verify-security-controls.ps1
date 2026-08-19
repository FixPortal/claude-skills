$ErrorActionPreference = 'Stop'
$skill = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw
$normalizedSkill = $skill -replace '\s+', ' '

$controls = [ordered]@{
    code_security                              = @{ Configuration = 'code_security'; Public = 'enabled';  Private = 'disabled' }
    secret_scanning                            = @{ Configuration = 'secret_scanning'; Public = 'enabled';  Private = 'disabled' }
    secret_scanning_push_protection            = @{ Configuration = 'secret_scanning_push_protection'; Public = 'enabled';  Private = 'disabled' }
    secret_scanning_ai_detection               = @{ Configuration = 'secret_scanning_generic_secrets'; Public = 'enabled';  Private = 'disabled' }
    secret_scanning_non_provider_patterns      = @{ Configuration = 'secret_scanning_non_provider_patterns'; Public = 'enabled';  Private = 'disabled' }
    secret_scanning_validity_checks            = @{ Configuration = 'secret_scanning_validity_checks'; Public = 'enabled';  Private = 'disabled' }
    secret_scanning_delegated_alert_dismissal  = @{ Configuration = 'secret_scanning_delegated_alert_dismissal'; Public = 'disabled'; Private = 'disabled' }
    secret_scanning_delegated_bypass            = @{ Configuration = 'secret_scanning_delegated_bypass'; Public = 'disabled'; Private = 'disabled' }
}

foreach ($entry in $controls.GetEnumerator()) {
    $row = '| `{0}` | `{1}` | `{2}` | `{3}` |' -f
        $entry.Key, $entry.Value.Configuration, $entry.Value.Public, $entry.Value.Private
    if ($skill -notmatch [regex]::Escape($row)) {
        throw "The paid-control table is missing its exact mapping/targets row: $row"
    }
}

$configurationOnly = [ordered]@{
    secret_protection                         = @{ Public = 'enabled';  Private = 'not attached' }
    code_scanning_default_setup               = @{ Public = 'enabled';  Private = 'not attached' }
    code_scanning_delegated_alert_dismissal   = @{ Public = 'disabled'; Private = 'not attached' }
    secret_scanning_extended_metadata         = @{ Public = 'enabled';  Private = 'not attached' }
    private_vulnerability_reporting           = @{ Public = 'enabled';  Private = 'not attached' }
}

foreach ($entry in $configurationOnly.GetEnumerator()) {
    $row = '| `{0}` | `{1}` | `{2}` |' -f $entry.Key, $entry.Value.Public, $entry.Value.Private
    if ($skill -notmatch [regex]::Escape($row)) {
        throw "The configuration-only target table is missing: $row"
    }
}
if ($normalizedSkill -notmatch [regex]::Escape('Do not use `advanced_security` as a substitute for the individual `code_security` and `secret_protection` fields')) {
    throw 'The legacy advanced_security aggregate must not replace individual product readback.'
}

function Get-PrivateDrift([hashtable] $State) {
    @($controls.Keys | Where-Object {
        $State.ContainsKey($_) -and $State[$_] -ne $controls[$_].Private
    })
}

# Regression: code_security=disabled is not enough when any Secret Protection
# child remains enabled. Exercise every child independently so a dead row cannot
# hide behind another failing control.
foreach ($secretControl in @($controls.Keys | Where-Object { $_ -like 'secret_scanning*' })) {
    $state = @{ code_security = 'disabled'; $secretControl = 'enabled' }
    if ((Get-PrivateDrift $state) -notcontains $secretControl) {
        throw "Private drift failed to identify enabled control: $secretControl"
    }
}

foreach ($needle in '.visibility', '.owner.type', '.security_and_analysis', 'GET /repos/{owner}/{repo}') {
    if ($skill -notmatch [regex]::Escape($needle)) {
        throw "Live repository identity/readback guidance is missing: $needle"
    }
}
# The private copy also asserts that one specific stale account name never returns to
# SKILL.md. That literal is machine-specific and is omitted from this public mirror; the
# live-derivation check below carries the same contract in general form.
if ($skill -notmatch '(?is)visibility.*owner\.type.*each (repository|run)') {
    throw 'Visibility and owner type must be derived live for each repository.'
}
if ($skill -notmatch '(?is)after.*PATCH.*GET /repos/\{owner\}/\{repo\}.*every.*control') {
    throw 'Repository mutation must be followed by an explicit readback of every paid control.'
}
foreach ($control in 'code_scanning_default_setup',
                     'code_scanning_delegated_alert_dismissal',
                     'secret_scanning_delegated_alert_dismissal',
                     'secret_scanning_delegated_bypass',
                     'private_vulnerability_reporting') {
    if ($skill -notmatch "(?is)Re-read the named public\s+configuration.*$control") {
        throw "Named-configuration readback must identify the control individually: $control"
    }
}

$validityBoundary = [regex]::Match(
    $skill,
    '(?ms)^### Unsupported repository mutation\s*\r?\n(?<body>.*?)(?=^###? |\z)'
).Groups['body'].Value
foreach ($needle in 'secret_scanning_validity_checks', 'NONCOMPLIANT', 'UNKNOWN', 'open', 'automation boundary') {
    if ($validityBoundary -notmatch [regex]::Escape($needle)) {
        throw "Unsupported validity-check mutation contract is missing: $needle"
    }
}
if ($validityBoundary -match '(?is)remains enabled.*classify it `UNKNOWN`') {
    throw 'A known enabled validity-check state must not be reclassified as UNKNOWN.'
}
if ($validityBoundary -notmatch '(?is)enabled.*NONCOMPLIANT.*open.*unsupported mutation.*automation boundary') {
    throw 'Known enabled validity-check drift must stay open while mutation alone is unsupported.'
}
if ($validityBoundary -notmatch '(?is)(omitted field|read failure).*UNKNOWN') {
    throw 'UNKNOWN must be reserved for omitted validity-check state or read failure.'
}

'audit-github-estate security controls OK'
