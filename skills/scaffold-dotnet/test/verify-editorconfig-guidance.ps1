$ErrorActionPreference = 'Stop'

$skill = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw) -replace '\s+', ' '
foreach ($required in @('active assignment', 'comments and examples do not count', 'applicable C# section')) {
    if (-not $skill.Contains($required, [StringComparison]::OrdinalIgnoreCase)) {
        throw "scaffold-dotnet guidance is missing required contract text: $required"
    }
}

'scaffold-dotnet editorconfig guidance OK'
