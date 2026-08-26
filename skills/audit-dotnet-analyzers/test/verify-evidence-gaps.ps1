#Requires -Version 7
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path $PSScriptRoot -Parent
$inventory = Join-Path $skillRoot 'scripts/inventory-dotnet-analysis.ps1'
$tempRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "audit-dotnet-evidence-$([guid]::NewGuid())"))
$oldPackages = $env:NUGET_PACKAGES

try {
    New-Item -ItemType Directory -Path (Join-Path $tempRoot '.git'), (Join-Path $tempRoot 'src') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot 'Directory.Build.props') -Value '<Project><PropertyGroup>'
    Set-Content -LiteralPath (Join-Path $tempRoot 'src/Test.csproj') -Value @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Broken.Analyzer" Version="1.0.0" />
  </ItemGroup>
</Project>
'@

    $env:NUGET_PACKAGES = Join-Path $tempRoot 'packages'
    $packageRoot = Join-Path $env:NUGET_PACKAGES 'broken.analyzer/1.0.0'
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $packageRoot 'broken.analyzer.nuspec') -Value '<package><metadata>'

    $result = & $inventory -Path $tempRoot | ConvertFrom-Json
    $repo = $result.Repositories[0]

    foreach ($probeName in 'GitStatusBefore', 'GitStatusAfter') {
        $probe = $repo.$probeName
        if ($probe.Success -ne $false -or $probe.ExitCode -eq 0 -or [string]::IsNullOrWhiteSpace($probe.Error)) {
            throw "$probeName must preserve failed Git evidence with success, exit code, and error."
        }
        if ($null -eq $probe.Status) {
            throw "$probeName must expose a Status field even when the probe fails."
        }
    }
    if ($null -ne $repo.Mutated -or $repo.MutationState -ne 'Unknown') {
        throw 'Mutation must remain unknown when either Git status probe fails.'
    }

    $parseErrors = @($repo.ParseErrors)
    if ($parseErrors.Count -ne 2) {
        throw "Expected project XML and nuspec parse errors; got $($parseErrors.Count)."
    }
    foreach ($errorRecord in $parseErrors) {
        if ([string]::IsNullOrWhiteSpace($errorRecord.Path) -or [string]::IsNullOrWhiteSpace($errorRecord.Error)) {
            throw 'Every parse error must retain its path and error.'
        }
    }
    if (-not (@($parseErrors.Kind) -contains 'ProjectXml') -or -not (@($parseErrors.Kind) -contains 'NuspecXml')) {
        throw "Expected ProjectXml and NuspecXml gaps; got $(@($parseErrors.Kind) -join ', ')."
    }

    $brokenAnalyzer = @($repo.BundledAnalyzers | Where-Object Id -eq 'Broken.Analyzer')
    if ($brokenAnalyzer.Count -ne 1) {
        throw "Expected one Broken.Analyzer result; got $($brokenAnalyzer.Count)."
    }
    if ($null -ne $brokenAnalyzer[0].Dependencies) {
        throw 'Malformed nuspec dependencies must remain unknown, not become an empty list.'
    }

    Write-Host 'Evidence-gap verification passed.'
}
finally {
    $env:NUGET_PACKAGES = $oldPackages
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
