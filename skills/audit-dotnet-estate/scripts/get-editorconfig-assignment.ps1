<#
.SYNOPSIS
  Read the active assignment of one .editorconfig key within matching sections.

.PARAMETER SectionPattern
  Regex matched against the WHOLE section glob (anchored at both ends). '\*\.cs'
  matches [*.cs] only - never [*.csproj] or [*.csx]. Unanchored matching would lift a
  value from an unrelated section and report it as the effective C# assignment.

.NOTES
  When several matching sections assign the same key, every assignment is emitted in
  file order. .editorconfig precedence is last-wins, so the LAST emitted row is the
  effective value.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [Parameter(Mandatory)]
    [string] $Key,

    [Parameter(Mandatory)]
    [string] $SectionPattern
)

$ErrorActionPreference = 'Stop'
$section = $null
$sectionMatches = $false
$keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*?)\s*$'
$anchoredSectionPattern = '^(?:' + $SectionPattern + ')$'

foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^\s*[#;]') { continue }
    if ($line -match '^\s*\[(.+)\]\s*$') {
        $section = $Matches[1]
        $sectionMatches = $section -match $anchoredSectionPattern
        continue
    }
    if ($sectionMatches -and $line -match $keyPattern) {
        [pscustomobject]@{ Section = $section; Key = $Key; Value = $Matches[1] }
    }
}
