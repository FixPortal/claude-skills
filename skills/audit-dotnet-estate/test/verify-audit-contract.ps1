$ErrorActionPreference = 'Stop'

$skillRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$reader = Join-Path $skillRoot 'scripts/get-editorconfig-assignment.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotnet-audit-contract-' + [guid]::NewGuid().ToString('N'))

function Assert-Equal($actual, $expected, [string] $because) {
    $actualText = @($actual) -join "`n"
    $expectedText = @($expected) -join "`n"
    if ($actualText -ne $expectedText) {
        throw "$because`nExpected: $expectedText`nActual: $actualText"
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $editorConfig = Join-Path $tempRoot '.editorconfig'
    @'
[*.cs]
# Adding max_line_length = 120 would reformat the tree.
indent_size = 4

[*.md]
max_line_length = 80

[**/*.cs]
max_line_length = 100
'@ | Set-Content -LiteralPath $editorConfig

    $assignments = @(& $reader -Path $editorConfig -Key max_line_length -SectionPattern '\*\.cs')
    Assert-Equal $assignments.Count 1 'Commented and unrelated assignments must not count.'
    Assert-Equal $assignments[0].Value '100' 'The active C# assignment must be returned.'

    $skill = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw
    foreach ($required in @('Audit mode', 'Evidence origin', 'Inherited evidence is not independent corroboration', 'non-zero', 'dependency advisory', 'flaky test')) {
        if (-not $skill.Contains($required, [StringComparison]::OrdinalIgnoreCase)) {
            throw "audit-dotnet-estate guidance is missing required contract text: $required"
        }
    }

    'audit-dotnet-estate contract OK'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
