$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..' 'references' 'stack-conventions.md'
$text = Get-Content $path -Raw

# nuget.org has NO package with the id `ArchUnitNET` (search PackageId:ArchUnitNET
# returns 0 hits). The real id is TngTech.ArchUnitNET. Naming the wrong id sends a
# scaffolding agent to a package that cannot be restored.
if ($text -match '(?<!TngTech\.)ArchUnitNET') {
    throw "stack-conventions.md names the bare id 'ArchUnitNET'; the real package is TngTech.ArchUnitNET"
}

if ($text -notmatch [regex]::Escape('TngTech.ArchUnitNET')) {
    throw "stack-conventions.md missing the correct package id TngTech.ArchUnitNET"
}

'audit-tests package ids OK'
