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

foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^\s*[#;]') { continue }
    if ($line -match '^\s*\[(.+)\]\s*$') {
        $section = $Matches[1]
        $sectionMatches = $section -match $SectionPattern
        continue
    }
    if ($sectionMatches -and $line -match $keyPattern) {
        [pscustomobject]@{ Section = $section; Key = $Key; Value = $Matches[1] }
    }
}
