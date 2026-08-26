#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('sln', 'slnx')]
    [string] $SolutionFormat,

    [Parameter(Mandatory)]
    [bool] $SolutionMigrationAuthorized,

    [Parameter(Mandatory)]
    [bool] $CSharpierWidthMigration,

    [Parameter(Mandatory)]
    [bool] $HasOtherFindings
)

$solutionAction = if ($SolutionFormat -eq 'sln' -and $SolutionMigrationAuthorized) {
    'MigrateToSlnx'
} elseif ($SolutionFormat -eq 'sln') {
    'PreserveExistingSln'
} else {
    'PreserveSlnx'
}

$pullRequests = @(
    if ($CSharpierWidthMigration) {
        [pscustomobject]@{ Purpose = 'CSharpierFormatting'; Standalone = $true }
        if ($HasOtherFindings -or $solutionAction -eq 'MigrateToSlnx') {
            [pscustomobject]@{ Purpose = 'RemainingFindings'; Standalone = $false }
        }
    } else {
        [pscustomobject]@{ Purpose = 'AllFindings'; Standalone = $false }
    }
)

[pscustomobject]@{
    SolutionAction = $solutionAction
    PullRequests   = $pullRequests
}
