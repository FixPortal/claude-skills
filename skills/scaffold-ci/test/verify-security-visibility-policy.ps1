$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$ciRoot = Join-Path $root 'scaffold-ci'
$security = Get-Content (Join-Path $ciRoot 'references' 'dependencies-and-security.md') -Raw
$ci = @(
    Get-Content (Join-Path $ciRoot 'SKILL.md') -Raw
    Get-ChildItem (Join-Path $ciRoot 'references') -Filter '*.md' | ForEach-Object { Get-Content $_.FullName -Raw }
) -join "`n"
# scaffold-repo is a sibling skill in the private home that this public mirror does not
# carry. Same convention as the absent-policy skip below: $null means ABSENT, and the
# scaffold-repo assertions are skipped with a stated reason rather than failing on a file
# the repository deliberately does not own.
$repoPath = Join-Path $root 'scaffold-repo' 'SKILL.md'
$repo = if (Test-Path -LiteralPath $repoPath) { [string](Get-Content -LiteralPath $repoPath -Raw) } else {
    Write-Host "SKIP: scaffold-repo sibling not present in this tree - $repoPath"
    $null
}
$audit = Get-Content (Join-Path $root 'audit-ci' 'SKILL.md') -Raw
$estate = Get-Content (Join-Path $root 'audit-github-estate' 'SKILL.md') -Raw
$gateRoot = Join-Path $root 'quality-gate-review'
$gate = @(
    Get-Content (Join-Path $gateRoot 'SKILL.md') -Raw
    Get-ChildItem (Join-Path $gateRoot 'references') -Filter '*.md' | ForEach-Object { Get-Content $_.FullName -Raw }
) -join "`n"
$dotnet = Get-Content (Join-Path $root 'scaffold-dotnet' 'SKILL.md') -Raw
# Codex's global policy file lives OUTSIDE this repository, so it is absent on CI and on
# any machine that is not this estate. Its absence is not a defect in this repo - skip the
# assertion with a stated reason rather than failing a PR over a file the repo does not own.
# $null means ABSENT (skip); an empty string means present-but-empty, which must still be
# asserted against and fail. Gating on truthiness would turn a truncated policy into a pass.
$agentsPath = Join-Path $HOME '.codex' 'AGENTS.md'
$agents = if (Test-Path -LiteralPath $agentsPath) { [string](Get-Content -LiteralPath $agentsPath -Raw) } else {
    Write-Host "SKIP: global Codex policy not present on this host - $agentsPath"
    $null
}

function Assert-NoUnsafeCodeQualityDefault {
    param([string]$Name, [string]$Text)

    foreach ($line in $Text -split '\r?\n') {
        $mentionsDefaultEnablement = $line -match '(?i)Code Quality' -and (
            ($line -match '(?i)\b(public|default)\b' -and $line -match '(?i)\b(enable(?:d|s)?|configur(?:e|ed))\b') -or
            $line -match '(?i)(enable|configure).*Code Quality.*automatic' -or
            $line -match '(?i)Code Quality.*(enabled|configured).*automatic'
        )
        $hasApprovalGuard = $line -match '(?i)disabled.*(explicit.*charges|charges.*explicit)'
        if ($mentionsDefaultEnablement -and -not $hasApprovalGuard) {
            throw "$Name enables paid Code Quality without explicit current-charge approval: $line"
        }
    }
}

function Test-PowerShellExamples {
    param([string]$Text)

    $problems = @()
    $blocks = [regex]::Matches($Text, '(?ms)^[ \t]*```powershell[ \t]*\r?\n(?<body>.*?)(?=^[ \t]*```[ \t]*$)')
    $commands = @($blocks | ForEach-Object { $_.Groups['body'].Value.Trim() })

    foreach ($command in $commands) {
        if ($command -match '\r?\n') {
            $problems += "PowerShell example is not one line: $command"
        }
    }

    if ($commands -notcontains '$repo = gh repo view --json nameWithOwner --jq .nameWithOwner') {
        $problems += 'PowerShell examples do not resolve the current repository'
    }
    if ($commands -notcontains '$pr = gh pr view --json number --jq .number') {
        $problems += 'PowerShell examples do not resolve the current pull request'
    }

    foreach ($command in $commands | Where-Object { $_ -match '^gh api\b' }) {
        if ($command -notmatch '^gh api(?: -X [A-Z]+)? "repos/\$repo(?:/[^" ]*)?"(?: |$)') {
            $problems += "gh api endpoint is not quoted and repository-resolved: $command"
        }
    }

    if (($commands -join "`n") -match 'OWNER/REPO|<n>|\{owner\}|\{repo\}') {
        $problems += 'PowerShell examples contain manual repository or pull-request placeholders'
    }

    $alertCommand = $commands | Where-Object { $_ -match 'code-scanning/alerts' } | Select-Object -First 1
    if ($alertCommand -notmatch 'refs/pull/\$pr/head') {
        $problems += 'Code scanning alert example does not use the resolved pull request number'
    }

    return $problems
}

$collapsedDependabotPattern = 'automated-security-fixes[^\r\n]*HTTP 204 means enabled|vulnerability alerts and automated security fixes[^|\r\n]*both return HTTP 204'

$forbidden = @{
    'scaffold-ci enables CodeQL for every repository' = $ci -match 'CodeQL \*\*default setup\*\* \| code scanning \| always'
    'scaffold-ci calls paid private features free' = $ci -match 'CodeQL and Code Quality are GitHub-side and free per commit'
    'scaffold-ci enables Code Quality by public visibility' = $ci -match 'Public[^\r\n]*Enable[^\r\n]*deterministic Code Quality'
    'scaffold-repo enables Code Quality by public visibility' = $repo -match 'Public[^\r\n]*receive[^\r\n]*deterministic Code Quality'
    'audit-ci calls public Code Quality free coverage' = $audit -match 'public:[^|\r\n]*deterministic Code Quality|public free coverage off'
    'audit-github-estate enables Code Quality by public visibility' = $estate -match 'Public[^\r\n]*Enable deterministic Code Quality'
    'scaffold-ci enables paid Code Quality by default' = $ci -match 'Enable paid Code Quality by default'
    'scaffold-ci mistakes a dynamic CodeQL workflow for default setup' = $ci -match 'dynamic/github-code-scanning/codeql[^\r\n]*(means|=)[^\r\n]*default setup'
    'audit-ci mistakes a dynamic CodeQL workflow for default setup' = $audit -match 'dynamic/github-code-scanning/codeql[^\r\n]*(means|=)[^\r\n]*default setup'
    'audit-ci collapses both Dependabot GET contracts to HTTP 204' = $audit -match $collapsedDependabotPattern
    'scaffold-ci collapses both Dependabot GET contracts to HTTP 204' = $ci -match 'Verify both endpoints return HTTP 204'
    'scaffold-repo provisions Copilot review' = $repo -match 'ruleset-copilot-review\.json'
    'scaffold-repo enables secret scanning estate-wide' = $repo -match 'Secret scanning \+ push protection\*\* — on for the estate'
    'scaffold-repo expects two rulesets' = $repo -match 'two active rulesets'
    'scaffold-dotnet implies CodeQL is universal' = $dotnet -match '\(ci\.yml, mutation\.yml, CodeQL\)'
    'scaffold-ci gives user-facing Bash commands' = $security -match '(?m)^[ \t]*```bash[ \t]*$'
}

foreach ($entry in $forbidden.GetEnumerator()) {
    if ($entry.Value) { throw $entry.Key }
}

$powerShellProblems = Test-PowerShellExamples $security
if ($powerShellProblems.Count -gt 0) { throw ($powerShellProblems -join "`n") }

foreach ($mutation in @(
    @{ Name = 'a hard-coded repository'; From = '$repo = gh repo view --json nameWithOwner --jq .nameWithOwner'; To = '$repo = ''OWNER/REPO''' },
    @{ Name = 'an unquoted gh endpoint'; From = '"repos/$repo/code-scanning/default-setup"'; To = 'repos/{owner}/{repo}/code-scanning/default-setup' },
    @{ Name = 'a manual pull request number'; From = 'refs/pull/$pr/head'; To = 'refs/pull/<n>/head' }
)) {
    $mutated = $security.Replace($mutation.From, $mutation.To)
    if ($mutated -eq $security) { throw "PowerShell red check '$($mutation.Name)' did not modify the reference" }
    if ((Test-PowerShellExamples $mutated).Count -eq 0) {
        throw "PowerShell red check failed: $($mutation.Name) was accepted"
    }
}

$collapsedAuditMutation = $audit + "`n| **Dependabot security settings** | vulnerability alerts and automated security fixes both return HTTP 204 | gap |"
if ($collapsedAuditMutation -notmatch $collapsedDependabotPattern) {
    throw 'Collapsed Dependabot audit contract mutation was not rejected'
}

Assert-NoUnsafeCodeQualityDefault 'scaffold-ci' $ci
if ($null -ne $repo) { Assert-NoUnsafeCodeQualityDefault 'scaffold-repo' $repo }
Assert-NoUnsafeCodeQualityDefault 'audit-ci' $audit
Assert-NoUnsafeCodeQualityDefault 'audit-github-estate' $estate
if ($null -ne $agents) { Assert-NoUnsafeCodeQualityDefault 'AGENTS.md' $agents }

$unsafeWasRejected = $false
try {
    Assert-NoUnsafeCodeQualityDefault 'mutation check' ($ci + "`nPublic repositories enable paid Code Quality automatically.")
} catch {
    $unsafeWasRejected = $true
}
if (-not $unsafeWasRejected) { throw 'Unsafe Code Quality default mutation was not rejected' }

foreach ($required in @(
    @{ Name = 'scaffold-ci public free policy'; Text = $ci; Pattern = '(?m)^\| Public \|[^\r\n]*CodeQL[^\r\n]*secret scanning[^\r\n]*push protection[^\r\n]*Keep paid Code Quality disabled[^\r\n]*explicitly approves' },
    @{ Name = 'scaffold-ci paid Code Quality opt-in'; Text = $ci; Pattern = 'Code Quality.*paid.*explicit' },
    @{ Name = 'scaffold-ci enforced default-off scope'; Text = $ci; Pattern = 'No repositories.*Enforce\s+access' },
    @{ Name = 'scaffold-ci enforced approved scope'; Text = $ci; Pattern = 'Selected repositories.*exactly.*approved' },
    @{ Name = 'scaffold-ci CodeQL setup verification'; Text = $ci; Pattern = 'GET.*code-scanning/default-setup.*state.*configured' },
    @{ Name = 'scaffold-ci vulnerability-alerts GET contract'; Text = $ci; Pattern = 'GET.{0,100}?vulnerability-alerts.{0,100}?HTTP 204' },
    @{ Name = 'scaffold-ci automated-security-fixes GET contract'; Text = $ci; Pattern = 'GET.{0,100}?automated-security-fixes.{0,150}?HTTP 200.{0,100}?enabled.{0,50}?true.{0,100}?paused.{0,50}?false' },
    @{ Name = 'scaffold-ci automated-security-fixes noncompliant states'; Text = $ci; Pattern = 'automated-security-fixes.{0,250}?404.{0,100}?enabled.{0,50}?false.{0,100}?paused.{0,50}?true.{0,100}?non-compliant' },
    @{ Name = 'scaffold-ci private security policy'; Text = $ci; Pattern = 'Private or internal.*disable.*Code Security.*secret scanning' },
    @{ Name = 'scaffold-ci live public push-protection verification'; Text = $security; Pattern = 'verify.*live.*security_and_analysis\.secret_scanning_push_protection.*enabled' },
    @{ Name = 'scaffold-ci disables Code Quality AI'; Text = $ci; Pattern = 'Code Quality AI.*disabled' },
    @{ Name = 'audit-ci visibility-aware CodeQL'; Text = $audit; Pattern = 'CodeQL.*public' },
    @{ Name = 'audit-ci paid Code Quality default'; Text = $audit; Pattern = 'GitHub security surfaces.*every visibility: paid Code Quality disabled unless current charges were explicitly approved' },
    @{ Name = 'audit-ci organization Code Quality gate'; Text = $audit; Pattern = 'Repository access.*enforcement.*billing' },
    @{ Name = 'audit-ci CodeQL setup verification'; Text = $audit; Pattern = 'GET.*code-scanning/default-setup.*state.*configured' },
    @{ Name = 'audit-ci vulnerability-alerts GET contract'; Text = $audit; Pattern = 'vulnerability-alerts.{0,150}?HTTP 204' },
    @{ Name = 'audit-ci automated-security-fixes GET contract'; Text = $audit; Pattern = 'automated-security-fixes.{0,150}?HTTP 200.{0,100}?enabled.{0,50}?true.{0,100}?paused.{0,50}?false' },
    @{ Name = 'audit-ci automated-security-fixes noncompliant states'; Text = $audit; Pattern = 'automated-security-fixes.{0,250}?404.{0,100}?enabled.{0,50}?false.{0,100}?paused.{0,50}?true.{0,100}?non-compliant' },
    @{ Name = 'audit estate organization Code Quality gate'; Text = $estate; Pattern = 'organization.*Repository access.*billing.*before.*repository' },
    @{ Name = 'audit estate enforced default-off scope'; Text = $estate; Pattern = 'No repositories.*Enforce\s+access' },
    @{ Name = 'audit estate enforced approved scope'; Text = $estate; Pattern = 'Selected repositories.*exactly.*approved' },
    @{ Name = 'audit estate paid Code Quality default'; Text = $estate; Pattern = '(?m)^\| Public \|[^\r\n]*Code Quality remains a paid explicit opt-in[^\r\n]*Keep Code Quality disabled[^\r\n]*explicitly approves' },
    @{ Name = 'scaffold-repo organization Code Quality gate'; Text = $repo; Pattern = 'Repository access.*enforcement.*billing' },
    @{ Name = 'scaffold-repo paid Code Quality default'; Text = $repo; Pattern = 'Keep paid Code Quality disabled at every visibility unless the user explicitly.*approves the current charges' },
    @{ Name = 'quality gate checks only applicable surfaces'; Text = $gate; Pattern = 'expected enabled tool with no result is a gap.*disabled.*N/A' },
    @{ Name = 'scaffold-dotnet delegates visibility policy'; Text = $dotnet; Pattern = 'visibility-appropriate' }
)) {
    # A $null Text is an absent sibling skill (see the scaffold-repo skip above), not a
    # missing assertion: -notmatch against $null would fail every such row spuriously.
    if ($null -eq $required.Text) { continue }
    if ($required.Text -notmatch "(?is)$($required.Pattern)") {
        throw "Missing $($required.Name)"
    }
}

if ($null -ne $agents -and $agents -notmatch '(?is)Public\s+CodeQL and Secret Protection remain enabled.*Code Quality is paid.*disabled.*explicitly approves') {
    throw 'Global AGENTS.md contradicts the mandatory public baseline or paid Code Quality opt-in'
}

$copilotAsset = Join-Path $root 'scaffold-repo' 'assets' 'ruleset-copilot-review.json'
if (Test-Path $copilotAsset) {
    throw 'Obsolete Copilot review ruleset asset still exists'
}

'GitHub security visibility policy OK'
