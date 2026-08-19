[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RepositoryRoot
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$workflowRoot = Join-Path $root '.github/workflows'
if (-not (Test-Path -LiteralPath $workflowRoot -PathType Container)) { return }

@(
    Get-ChildItem -LiteralPath $workflowRoot -File -Filter '*.yml'
    Get-ChildItem -LiteralPath $workflowRoot -File -Filter '*.yaml'
) |
    Sort-Object FullName -Unique |
    ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/') }
