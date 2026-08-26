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
    # The fixture's .git is an empty directory, so `git status` FAILS there by design.
    $failed = $result.Repositories[0]
    if ($failed.GitStatusBefore.Success -or $failed.GitStatusAfter.Success -or
        $failed.MutationState -ne 'Unknown' -or $null -ne $failed.Mutated) {
        throw 'A repo whose git status cannot be read must retain both failed probes and MutationState=Unknown'
    }

    # A REAL clean repo: `git status --porcelain` exits 0 with NO output. The status
    # capture must read that as success (Mutated=$false), not collapse it into the
    # failed-capture shape -- an empty status array unrolls to $null on the pipeline,
    # which is exactly the regression this guards.
    $cleanRepo = Join-Path $tempRoot 'clean-repo'
    New-Item -ItemType Directory -Path $cleanRepo | Out-Null
    git -C $cleanRepo init --quiet
    if ($LASTEXITCODE -ne 0) { throw "fixture git init failed (exit $LASTEXITCODE)" }
    git -C $cleanRepo config user.email 'you@example.com'
    git -C $cleanRepo config user.name 'Prune Fixture'
    Set-Content -LiteralPath (Join-Path $cleanRepo 'Directory.Build.props') -Value '<Project><PropertyGroup><LangVersion>latest</LangVersion></PropertyGroup></Project>'
    git -C $cleanRepo add Directory.Build.props
    if ($LASTEXITCODE -ne 0) { throw "fixture git add failed (exit $LASTEXITCODE)" }
    git -C $cleanRepo commit --quiet -m 'chore: fixture'
    if ($LASTEXITCODE -ne 0) { throw "fixture git commit failed (exit $LASTEXITCODE)" }

    $cleanResult = & $inventory -Path $cleanRepo 3>$null | ConvertFrom-Json
    $clean = $cleanResult.Repositories[0]
    if (-not $clean.GitStatusBefore.Success -or -not $clean.GitStatusAfter.Success) {
        throw 'A CLEAN repo must retain both successful empty git-status probes'
    }
    if ($clean.Mutated -ne $false -or $clean.MutationState -ne 'Unchanged') {
        throw "A clean repo must report Mutated=`$false and MutationState=Unchanged, got '$($clean.Mutated)'/'$($clean.MutationState)'"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host 'Pruned traversal verification passed.'

# The inventory child runs git inside a fixture with an empty .git — asserted, not
# fatal. Clear its native status so a caller that checks $LASTEXITCODE after a PASS does
# not read the child's failure.
$global:LASTEXITCODE = 0
