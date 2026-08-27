$ErrorActionPreference = 'Stop'

$skillRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$skill = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'SKILL.md')
$reader = Join-Path $skillRoot 'scripts/get-editorconfig-assignment.ps1'
$planner = Join-Path $skillRoot 'scripts/get-remediation-plan.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotnet-audit-contract-' + [guid]::NewGuid().ToString('N'))

function Assert-Equal($actual, $expected, [string] $because) {
    $actualText = @($actual) -join "`n"
    $expectedText = @($expected) -join "`n"
    if ($actualText -ne $expectedText) {
        throw "$because`nExpected: $expectedText`nActual: $actualText"
    }
}

try {
    foreach ($requiredPerformanceCoverageContract in @(
        '### Performance audit coverage \(informational, non-graded\)',
        '(?s)Group pairs by the filename timestamp and\s+select the latest minute\. Validate every manifest in that minute; if any fails, classify\s+the coverage `Not assessed` without falling back\.',
        '(?s)select the greatest\s+`audit\.completedUtc`.*breaking an exact tie by ordinal full filename, then compare\s+`repository\.head` with the estate audit''s HEAD',
        '(?s)`Current`.*`Stale`.*`Not found`.*`Not assessed`',
        '(?s)Performance audit coverage never changes a check result, repository verdict, finding, or\s+remediation prompt\.',
        '(?s)Never invoke `audit-dotnet-performance`, build, test, benchmark, or\s+profile to fill a coverage gap'
    )) {
        if ($skill -notmatch $requiredPerformanceCoverageContract) {
            throw "The estate report contract must match '$requiredPerformanceCoverageContract'."
        }
    }
    if ($skill -match 'user-overridden location') {
        throw 'The estate contract must not promise a performance-report location override that the source skill does not define.'
    }

    $sourceRoot = Join-Path $tempRoot 'src'
    $nestedRoot = Join-Path $sourceRoot 'Nested'
    New-Item -ItemType Directory -Path $nestedRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot 'Existing.sln') -Value 'Microsoft Visual Studio Solution File'
    $rootFile = Join-Path $tempRoot 'Root.cs'
    $sourceFile = Join-Path $sourceRoot 'Program.cs'
    $nestedFile = Join-Path $nestedRoot 'Nested.cs'
    Set-Content -LiteralPath $rootFile -Value 'class Root { }'
    Set-Content -LiteralPath $sourceFile -Value 'class Program { }'
    Set-Content -LiteralPath $nestedFile -Value 'class Nested { }'

    $editorConfig = Join-Path $tempRoot '.editorconfig'
    @'
root = true

[*.cs]
# Adding max_line_length = 120 would reformat the tree.
max_line_length = 100

[*.csproj]
max_line_length = 70

[*.cshtml]
max_line_length = 75

[*{.cs,.vb}]
indent_size = 4

[src/{Program,Other}.cs]
max_line_length = 120

[*.cs]
dotnet_diagnostic.IDE0055.severity = error
'@ | Set-Content -LiteralPath $editorConfig

    @'
[*.cs]
max_line_length = 90
'@ | Set-Content -LiteralPath (Join-Path $sourceRoot '.editorconfig')

    @'
[*.cs]
max_line_length = 80
'@ | Set-Content -LiteralPath (Join-Path $nestedRoot '.editorconfig')

    $sourceWidth = @(& $reader -Path $sourceFile -Key max_line_length)
    Assert-Equal $sourceWidth.Count 1 'A concrete C# file must resolve to one effective assignment.'
    Assert-Equal $sourceWidth[0].Value '90' 'A nearer EditorConfig must override parent sections.'

    $nestedWidth = @(& $reader -Path $nestedFile -Key max_line_length)
    Assert-Equal $nestedWidth.Count 1 'Nested precedence must resolve one effective assignment.'
    Assert-Equal $nestedWidth[0].Value '80' 'The nearest nested EditorConfig must win.'

    $rootWidth = @(& $reader -Path $rootFile -Key max_line_length)
    Assert-Equal $rootWidth.Count 1 'Prefix-collision sections must not apply to a C# file.'
    Assert-Equal $rootWidth[0].Value '100' '*.csproj and *.cshtml must not match Root.cs.'

    $indent = @(& $reader -Path $sourceFile -Key indent_size)
    Assert-Equal $indent.Count 1 'Brace globs must apply to a concrete C# file.'
    Assert-Equal $indent[0].Value '4' 'The brace-glob assignment must be returned.'

    $competingRule = @(& $reader -Path $sourceFile -Key dotnet_diagnostic.IDE0055.severity)
    Assert-Equal $competingRule.Count 1 'The CSharpier migration fixture must retain its separate analyzer finding.'
    Assert-Equal $competingRule[0].Value 'error' 'The separate finding must be collected independently of print width.'

    if (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'Existing.sln'))) {
        throw 'The existing .sln fixture must remain intact while collecting evidence.'
    }

    $slnxRoot = Join-Path $tempRoot 'slnx'
    New-Item -ItemType Directory -Path $slnxRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $slnxRoot 'Current.slnx') -Value '<Solution />'

    $planCases = @(
        @{
            Name = 'existing sln without authorized migration'
            Root = $tempRoot
            MigrationAuthorized = $false
            WidthMigration = $false
            OtherFindings = $true
            ExpectedSolutionAction = 'PreserveExistingSln'
            ExpectedPrs = @('AllFindings')
        },
        @{
            Name = 'existing sln with authorized migration'
            Root = $tempRoot
            MigrationAuthorized = $true
            WidthMigration = $false
            OtherFindings = $true
            ExpectedSolutionAction = 'MigrateToSlnx'
            ExpectedPrs = @('AllFindings')
        },
        @{
            Name = 'CSharpier migration plus another finding'
            Root = $slnxRoot
            MigrationAuthorized = $false
            WidthMigration = $true
            OtherFindings = $true
            ExpectedSolutionAction = 'PreserveSlnx'
            ExpectedPrs = @('CSharpierFormatting', 'RemainingFindings')
        },
        @{
            Name = 'CSharpier migration plus authorized solution migration'
            Root = $tempRoot
            MigrationAuthorized = $true
            WidthMigration = $true
            OtherFindings = $false
            ExpectedSolutionAction = 'MigrateToSlnx'
            ExpectedPrs = @('CSharpierFormatting', 'RemainingFindings')
        },
        @{
            Name = 'CSharpier migration only'
            Root = $slnxRoot
            MigrationAuthorized = $false
            WidthMigration = $true
            OtherFindings = $false
            ExpectedSolutionAction = 'PreserveSlnx'
            ExpectedPrs = @('CSharpierFormatting')
        },
        @{
            Name = 'non-formatting findings only'
            Root = $slnxRoot
            MigrationAuthorized = $false
            WidthMigration = $false
            OtherFindings = $true
            ExpectedSolutionAction = 'PreserveSlnx'
            ExpectedPrs = @('AllFindings')
        }
    )

    foreach ($case in $planCases) {
        $format = if (Get-ChildItem -LiteralPath $case.Root -Filter '*.slnx' -File) { 'slnx' } else { 'sln' }
        $plan = & $planner -SolutionFormat $format `
            -SolutionMigrationAuthorized $case.MigrationAuthorized `
            -CSharpierWidthMigration $case.WidthMigration `
            -HasOtherFindings $case.OtherFindings

        Assert-Equal $plan.SolutionAction $case.ExpectedSolutionAction "$($case.Name): wrong solution action."
        Assert-Equal @($plan.PullRequests.Purpose) $case.ExpectedPrs "$($case.Name): wrong remediation PR plan."
        if ($case.WidthMigration -and -not @($plan.PullRequests | Where-Object Purpose -eq 'CSharpierFormatting')[0].Standalone) {
            throw "$($case.Name): CSharpier formatting must be standalone."
        }
    }

    'audit-dotnet-estate contract OK'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
