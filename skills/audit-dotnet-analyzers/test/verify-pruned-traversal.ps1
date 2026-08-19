#Requires -Version 7
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path $PSScriptRoot -Parent
$inventory = Join-Path $skillRoot 'scripts/inventory-dotnet-analysis.ps1'
# Extract Get-Tree via the AST, not a regex window. `(?s)function Get-Tree \{.*?\n\}`
# stops at the first line beginning with '}' in column 0, so it only ever worked because
# every internal brace happened to be indented: reformat the function, or put a closing
# brace at column 0 inside it (a here-string, a nested scriptblock), and the window either
# truncates - hiding a -Recurse that IS there - or swallows the rest of the file. A guard
# whose scope depends on formatting is not a guard.
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($inventory, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw "inventory-dotnet-analysis.ps1 does not parse: $($parseErrors[0].Message)" }
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-Tree' }, $true)
if (-not $fn) { throw 'Get-Tree function not found in inventory-dotnet-analysis.ps1' }
$getTree = $fn.Extent.Text
if ($getTree -match 'Get-ChildItem[^\r\n]*-Recurse') {
    throw 'Get-Tree must prune excluded directories before descent.'
}

$tempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "audit-dotnet-prune-$([guid]::NewGuid())"))
if (-not $tempRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe temporary path: $tempRoot"
}

try {
    New-Item -ItemType Directory -Path (Join-Path $tempRoot '.git'), (Join-Path $tempRoot 'node_modules/ignored') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot 'Directory.Build.props') -Value '<Project><PropertyGroup><LangVersion>latest</LangVersion></PropertyGroup></Project>'
    Set-Content -LiteralPath (Join-Path $tempRoot 'node_modules/ignored/Directory.Build.props') -Value '<Project><PropertyGroup><LangVersion>should-not-appear</LangVersion></PropertyGroup></Project>'

    $result = & $inventory -Path $tempRoot | ConvertFrom-Json
    $values = @($result.Repositories[0].PolicyProperties.Value)
    if ('latest' -notin $values -or 'should-not-appear' -in $values) {
        throw "Traversal did not prune node_modules before inventory: $($values -join ', ')"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host 'Pruned traversal verification passed.'
