[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ActualPath,

    [Parameter(Mandatory)]
    [string] $CanonicalPath,

    [switch] $IgnoreLineEndings
)

$ErrorActionPreference = 'Stop'
$actual = (Resolve-Path -LiteralPath $ActualPath).Path
$canonical = (Resolve-Path -LiteralPath $CanonicalPath).Path

if ($IgnoreLineEndings) {
    $actualContent = ([IO.File]::ReadAllText($actual) -replace "\r\n?|\n", "`n")
    $canonicalContent = ([IO.File]::ReadAllText($canonical) -replace "\r\n?|\n", "`n")
    $matches = $actualContent -ceq $canonicalContent
}
else {
    $actualHash = (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash
    $canonicalHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
    $matches = $actualHash -ceq $canonicalHash
}

if (-not $matches) {
    $actualHash = (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash
    $canonicalHash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
    throw "Canonical asset drift: '$actual' ($actualHash) differs from '$canonical' ($canonicalHash)."
}

"Canonical asset matches: $actual"
