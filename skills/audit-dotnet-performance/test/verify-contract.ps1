#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-That {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Inventory {
    param([string] $Repository, [string] $ToolPath)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command pwsh).Source
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add('-NoProfile')
    $start.ArgumentList.Add('-File')
    $start.ArgumentList.Add($scriptPath)
    $start.ArgumentList.Add('-RepositoryPath')
    $start.ArgumentList.Add($Repository)
    if ($ToolPath) { $start.Environment['PATH'] = "$ToolPath$([IO.Path]::PathSeparator)$env:PATH" }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{ stdout = $stdout; stderr = $stderr; exitCode = $process.ExitCode }
}

function Invoke-Manifest {
    param([string] $ManifestPath, [string] $Mode = 'Publication', [string] $Id)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command pwsh).Source
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add('-NoProfile')
    $start.ArgumentList.Add('-File')
    $start.ArgumentList.Add($manifestScriptPath)
    $start.ArgumentList.Add('-Path')
    $start.ArgumentList.Add($ManifestPath)
    $start.ArgumentList.Add('-Mode')
    $start.ArgumentList.Add($Mode)
    if ($Id) { $start.ArgumentList.Add('-FindingId'); $start.ArgumentList.Add($Id) }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{ stdout = $stdout; stderr = $stderr; exitCode = $process.ExitCode }
}

function Invoke-ManagedBoundary {
    param([string] $Repository, [string] $BaseRef = 'HEAD', [string[]] $ProductPath = @('.'))
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command pwsh).Source
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add('-NoProfile')
    $start.ArgumentList.Add('-File')
    $start.ArgumentList.Add($boundaryScriptPath)
    $start.ArgumentList.Add('-RepositoryPath')
    $start.ArgumentList.Add($Repository)
    $start.ArgumentList.Add('-BaseRef')
    $start.ArgumentList.Add($BaseRef)
    foreach ($path in $ProductPath) {
        $start.ArgumentList.Add('-ProductPath')
        $start.ArgumentList.Add($path)
    }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{ stdout = $stdout; stderr = $stderr; exitCode = $process.ExitCode }
}

$scriptPath = Join-Path $PSScriptRoot '..\scripts\inventory-dotnet-performance.ps1'
$manifestScriptPath = Join-Path $PSScriptRoot '..\scripts\test-performance-manifest.ps1'
$boundaryScriptPath = Join-Path $PSScriptRoot '..\scripts\test-managed-product-boundary.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Expected production inventory script at '$scriptPath'."
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ("performance-inventory-" + [guid]::NewGuid())
$notARepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-not-a-repo-" + [guid]::NewGuid())
$limitRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-limit-" + [guid]::NewGuid())
$markerLimitRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-marker-limit-" + [guid]::NewGuid())
$directoryRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-directories-" + [guid]::NewGuid())
$projectTruncationRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-project-depth-" + [guid]::NewGuid())
$projectScaleRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-project-scale-" + [guid]::NewGuid())
$globalJsonWithoutSdkRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-global-json-without-sdk-" + [guid]::NewGuid())
$manifestDirectory = Join-Path ([IO.Path]::GetTempPath()) ("performance-manifest-" + [guid]::NewGuid())
$boundaryRepo = Join-Path ([IO.Path]::GetTempPath()) ("performance-managed-boundary-" + [guid]::NewGuid())
$tools = Join-Path $fixture 'tools'
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'src\Library') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'bench\Benchmarks') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'BenchmarkDotNet.Artifacts\results') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'test\Library.Tests') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'broken') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'bin\decoy') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture 'obj\decoy') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture '.git\decoy') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixture '.claude\worktrees\decoy') -Force | Out-Null
    New-Item -ItemType Directory -Path $tools -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $fixture 'Sample.slnx') -Value '<Solution />'
    Set-Content -LiteralPath (Join-Path $fixture 'global.json') -Value '{"sdk":{"version":"10.0.100","rollForward":"latestFeature"}}'
    Set-Content -LiteralPath (Join-Path $fixture 'src\Library\Library.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Library</OutputType></PropertyGroup></Project>'
    Set-Content -LiteralPath (Join-Path $fixture 'bench\Benchmarks\Benchmarks.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="../../src/Library/Library.csproj" /><PackageReference Include="BenchmarkDotNet" Version="0.14.0" /></ItemGroup></Project>'
    Set-Content -LiteralPath (Join-Path $fixture 'test\Library.Tests\Library.Tests.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><IsTestProject>true</IsTestProject></PropertyGroup><ItemGroup><PackageReference Include="xunit.v3" Version="3.0.1" /></ItemGroup></Project>'
    Set-Content -LiteralPath (Join-Path $fixture 'broken\Broken.csproj') -Value '<Project><PropertyGroup>'
    Set-Content -LiteralPath (Join-Path $fixture 'bench\Benchmarks\BenchmarkConfig.cs') -Value @'
using BenchmarkDotNet.Configs;
class BenchmarkConfig : ManualConfig { }
'@
    Set-Content -LiteralPath (Join-Path $fixture 'BenchmarkDotNet.Artifacts\results\Benchmarks-report.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $fixture 'src\Library\Large.cs') -Value ("class Large {`n" + [string]::new('x', 65537))
    Set-Content -LiteralPath (Join-Path $fixture 'src\Library\Workload.cs') -Value @'
using Microsoft.EntityFrameworkCore;
using System.Net.Http;
using Microsoft.Extensions.Hosting;
class Workload : BackgroundService { DbContext Db = null!; HttpClient Client = new(); protected override Task ExecuteAsync(CancellationToken token) => Parallel.ForEachAsync([], token, (_, _) => ValueTask.CompletedTask); }
'@
    Set-Content -LiteralPath (Join-Path $fixture 'bin\decoy\Decoy.cs') -Value 'class Decoy { DbContext x; }'
    Set-Content -LiteralPath (Join-Path $fixture 'obj\decoy\Decoy.cs') -Value 'class Decoy { HttpClient x; }'
    Set-Content -LiteralPath (Join-Path $fixture '.git\decoy\Decoy.cs') -Value 'class Decoy : BackgroundService {}'
    Set-Content -LiteralPath (Join-Path $fixture '.claude\worktrees\decoy\Decoy.cs') -Value 'Parallel.ForEachAsync([], default, (_, _) => ValueTask.CompletedTask);'
    if ($IsWindows) {
        Set-Content -LiteralPath (Join-Path $tools 'dotnet.cmd') -Value @'
@echo off
if "%1"=="--version" echo 10.0.100-partial
if "%1"=="--list-runtimes" echo Microsoft.NETCore.App 10.0.0 [partial]
exit /b 7
'@
    }
    else {
        $dotnetShim = Join-Path $tools 'dotnet'
        Set-Content -LiteralPath $dotnetShim -Value @'
#!/bin/sh
if [ "$1" = "--version" ]; then printf '%s\n' '10.0.100-partial'; fi
if [ "$1" = "--list-runtimes" ]; then printf '%s\n' 'Microsoft.NETCore.App 10.0.0 [partial]'; fi
exit 7
'@
        & chmod +x $dotnetShim
    }
    & git -C $fixture init -q

    $result = Invoke-Inventory -Repository $fixture -ToolPath $tools
    Assert-That ($result.exitCode -eq 0) 'Expected inventory process to exit successfully.'
    Assert-That ([string]::IsNullOrWhiteSpace($result.stderr)) 'Expected inventory stderr to be empty.'
    Assert-That ((@($result.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one JSON document on stdout.'
    $inventory = $result.stdout | ConvertFrom-Json

    Assert-That ($inventory.schemaVersion -eq 1) 'Expected schemaVersion 1.'
    Assert-That ($inventory.repositoryPath -eq (Resolve-Path -LiteralPath $fixture).Path) 'Expected an absolute resolved repository path.'
    Assert-That ($inventory.targetFrameworks -contains 'net10.0') 'Expected net10.0 target framework evidence.'
    Assert-That (($inventory.projects | Where-Object role -eq 'library').Count -eq 1) 'Expected one library project.'
    Assert-That (($inventory.testProjects.path -match 'Library.Tests.csproj')) 'Expected test project evidence.'
    Assert-That (($inventory.benchmarkProjects.path -match 'Benchmarks.csproj')) 'Expected BenchmarkDotNet project evidence.'
    Assert-That (($inventory.benchmarkConfiguration.file -match 'BenchmarkConfig.cs')) 'Expected checked-in BenchmarkDotNet configuration evidence.'
    Assert-That ((@($inventory.benchmarkArtifacts -match 'Benchmarks-report.json')).Count -eq 1) 'Expected checked-in benchmark artifact evidence.'
    Assert-That ($inventory.sdk.globalJson.version -eq '10.0.100') 'Expected global.json SDK pin evidence.'
    Assert-That (($inventory.markers.marker -contains 'DbContext') -and ($inventory.markers.marker -contains 'HttpClient') -and ($inventory.markers.marker -contains 'BackgroundService') -and ($inventory.markers.marker -contains 'Parallel.ForEachAsync')) 'Expected source marker evidence.'
    Assert-That (($inventory.tools | Where-Object name -eq 'dotnet').Count -eq 1) 'Expected dotnet tool availability evidence.'
    Assert-That (-not ($inventory.tools.name -contains 'dotnet-gcdump')) 'Expected inventory not to advertise excluded GC-dump tooling.'
    Assert-That (-not ($inventory.tools.name -contains 'dotnet-dump')) 'Expected inventory not to advertise excluded process-dump tooling.'
    Assert-That ($inventory.completeness -eq 'partial') 'Expected malformed project to produce partial evidence.'
    Assert-That ($inventory.warnings.Count -gt 0) 'Expected malformed project warning.'
    Assert-That ((@($inventory.warnings | Where-Object { $_ -match 'Source file exceeds 65536 bytes' }).Count -eq 1)) 'Expected oversized source to be skipped with partial evidence.'
    Assert-That ((@($inventory.warnings | Where-Object { $_ -match 'Could not read dotnet SDK version' }).Count -eq 1)) "Expected failed dotnet SDK probe warning. Actual: $($inventory.warnings -join ' | ')"
    Assert-That ((@($inventory.warnings | Where-Object { $_ -match 'Could not list dotnet runtimes' }).Count -eq 1)) 'Expected failed dotnet runtime probe warning.'
    Assert-That ($inventory.probes.sdk.command -eq 'dotnet --version') 'Expected the SDK probe command in structured evidence.'
    Assert-That ($inventory.probes.sdk.exitCode -eq 7) 'Expected the SDK probe exit code in structured evidence.'
    Assert-That ($inventory.probes.sdk.output -contains '10.0.100-partial') 'Expected partial SDK stdout to survive a non-zero exit.'
    Assert-That ($inventory.probes.sdk.reason -match 'exit code 7') 'Expected the SDK probe failure reason.'
    Assert-That ($inventory.probes.runtime.command -eq 'dotnet --list-runtimes') 'Expected the runtime probe command in structured evidence.'
    Assert-That ($inventory.probes.runtime.exitCode -eq 7) 'Expected the runtime probe exit code in structured evidence.'
    Assert-That ($inventory.probes.runtime.output -contains 'Microsoft.NETCore.App 10.0.0 [partial]') 'Expected partial runtime stdout to survive a non-zero exit.'
    Assert-That ($inventory.probes.runtime.reason -match 'exit code 7') 'Expected the runtime probe failure reason.'
    Assert-That (-not (($inventory.markers.file -join "`n") -match '(?i)(^|[\\/])(bin|obj|\.git|worktrees)([\\/]|$)')) 'Expected pruned decoys to be excluded.'

    New-Item -ItemType Directory -Path $notARepo | Out-Null
    $outsideResult = Invoke-Inventory -Repository $notARepo
    $outside = $outsideResult.stdout | ConvertFrom-Json
    Assert-That ($outside.completeness -eq 'partial') 'Expected a non-repository directory to be partial.'
    Assert-That ($outside.warnings.Count -gt 0) 'Expected non-repository warning evidence.'

    New-Item -ItemType Directory -Path $limitRepo | Out-Null
    1..65 | ForEach-Object { Set-Content -LiteralPath (Join-Path $limitRepo "file$_.cs") -Value 'class Filler { }' }
    $limitResult = Invoke-Inventory -Repository $limitRepo
    $limit = $limitResult.stdout | ConvertFrom-Json
    Assert-That ((@($limit.warnings | Where-Object { $_ -match 'Source-marker scan stopped: maximum file count 64 reached' }).Count -eq 1)) 'Expected fixed source-marker file ceiling warning.'

    New-Item -ItemType Directory -Path $markerLimitRepo | Out-Null
    Set-Content -LiteralPath (Join-Path $markerLimitRepo 'Markers.cs') -Value @(1..501 | ForEach-Object { 'class Marker { DbContext Context; }' })
    $markerLimitResult = Invoke-Inventory -Repository $markerLimitRepo
    Assert-That ($markerLimitResult.exitCode -eq 0) "Expected marker-capped inventory to exit successfully: $($markerLimitResult.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($markerLimitResult.stderr)) 'Expected marker-capped inventory stderr to be empty.'
    $markerLimit = $markerLimitResult.stdout | ConvertFrom-Json
    Assert-That ($markerLimit.markers.Count -eq 500) 'Expected exactly 500 retained source markers.'
    Assert-That ((@($markerLimit.warnings | Where-Object { $_ -match 'Marker scan stopped: maximum marker count 500 reached' }).Count -eq 1)) 'Expected one marker ceiling warning.'

    New-Item -ItemType Directory -Path $directoryRepo | Out-Null
    1..65 | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $directoryRepo "directory$_") | Out-Null }
    & git -C $directoryRepo init -q
    $directoryResult = Invoke-Inventory -Repository $directoryRepo
    $directories = $directoryResult.stdout | ConvertFrom-Json
    Assert-That ((@($directories.warnings | Where-Object { $_ -match 'Source-marker scan stopped: maximum directory count 64 reached' }).Count -eq 1)) 'Expected source-marker directory ceiling warning.'
    Assert-That ($directories.completeness -eq 'partial') 'Expected directory ceiling to produce partial evidence.'
    Assert-That $directories.projectInventoryComplete 'Expected the project-aware pass not to share the small source-directory ceiling.'

    New-Item -ItemType Directory -Path $projectTruncationRepo | Out-Null
    $deepProjectDirectory = $projectTruncationRepo
    1..34 | ForEach-Object {
        $deepProjectDirectory = Join-Path $deepProjectDirectory ("d{0:D2}" -f $_)
        New-Item -ItemType Directory -Path $deepProjectDirectory | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $deepProjectDirectory 'Deep.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk" />'
    & git -C $projectTruncationRepo init -q
    $projectTruncationResult = Invoke-Inventory -Repository $projectTruncationRepo -ToolPath $tools
    $projectTruncation = $projectTruncationResult.stdout | ConvertFrom-Json
    Assert-That (-not $projectTruncation.projectInventoryComplete) 'Expected project-inventory truncation to be explicit.'
    Assert-That ((@($projectTruncation.stoppingConditions | Where-Object { $_ -match 'project inventory' }).Count -eq 1)) 'Expected project-inventory truncation to be a stopping condition.'

    New-Item -ItemType Directory -Path $projectScaleRepo | Out-Null
    1..70 | ForEach-Object { Set-Content -LiteralPath (Join-Path $projectScaleRepo ("{0:D3}-source.cs" -f $_)) -Value 'class Filler { }' }
    Set-Content -LiteralPath (Join-Path $projectScaleRepo 'Scale.slnx') -Value '<Solution />'
    Set-Content -LiteralPath (Join-Path $projectScaleRepo 'Library.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    Set-Content -LiteralPath (Join-Path $projectScaleRepo 'Web.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    Set-Content -LiteralPath (Join-Path $projectScaleRepo 'Worker.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk.Worker"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    & git -C $projectScaleRepo init -q
    $projectScaleResult = Invoke-Inventory -Repository $projectScaleRepo -ToolPath $tools
    $projectScale = $projectScaleResult.stdout | ConvertFrom-Json
    Assert-That ($projectScale.projects.Count -eq 3) 'Expected project discovery not to share the source-marker file cap.'
    Assert-That (($projectScale.projects | Where-Object role -eq 'library').Count -eq 1) 'Expected SDK library role detection without OutputType.'
    Assert-That (($projectScale.projects | Where-Object role -eq 'web').Count -eq 1) 'Expected Microsoft.NET.Sdk.Web role detection without OutputType.'
    Assert-That (($projectScale.projects | Where-Object role -eq 'worker').Count -eq 1) 'Expected Microsoft.NET.Sdk.Worker role detection without OutputType.'
    Assert-That ($projectScale.solutions -contains 'Scale.slnx') 'Expected solution discovery beyond the source-marker cap.'
    Assert-That $projectScale.projectInventoryComplete 'Expected complete project inventory when only source-marker scanning is capped.'

    New-Item -ItemType Directory -Path (Join-Path $globalJsonWithoutSdkRepo 'src') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $globalJsonWithoutSdkRepo 'global.json') -Value '{"test":{"runner":"Microsoft.Testing.Platform"}}'
    Set-Content -LiteralPath (Join-Path $globalJsonWithoutSdkRepo 'src\Worker.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    & git -C $globalJsonWithoutSdkRepo init -q
    $globalJsonWithoutSdk = Invoke-Inventory -Repository $globalJsonWithoutSdkRepo -ToolPath $tools
    Assert-That ($globalJsonWithoutSdk.exitCode -eq 0) "Expected a global.json without sdk to inventory successfully: $($globalJsonWithoutSdk.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($globalJsonWithoutSdk.stderr)) 'Expected a global.json without sdk not to write stderr.'
    Assert-That ((@($globalJsonWithoutSdk.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one global.json-without-sdk inventory JSON document on stdout.'
    $globalJsonWithoutSdkInventory = $globalJsonWithoutSdk.stdout | ConvertFrom-Json
    Assert-That ($null -eq $globalJsonWithoutSdkInventory.sdk.globalJson) 'Expected missing global.json sdk configuration to be null.'
    Assert-That ($globalJsonWithoutSdkInventory.targetFrameworks -contains 'net10.0') 'Expected project inventory to remain usable without global.json sdk configuration.'

    New-Item -ItemType Directory -Path $manifestDirectory | Out-Null
    $canonicalBoundaryExclusions = @('unsafe', 'System.Runtime.Intrinsics', 'DllImport', 'LibraryImport', 'PInvoke', 'native binaries', 'native-dependent packages', 'custom native allocators', 'undocumented runtime switches', 'runtime-private APIs', 'reflection/runtime patching')
    $validManifest = [ordered]@{
        schemaVersion = 1
        repository = [ordered]@{ path = '<workdir>\sample'; head = '0123456789abcdef'; branch = 'main' }
        audit = [ordered]@{ startedUtc = '2026-08-26T09:00:00Z'; completedUtc = '2026-08-26T09:05:00Z'; targetStateUnchanged = $true }
        findings = @(
            [ordered]@{ id = 'PERF-001'; title = 'First'; classification = 'Observed bottleneck'; confidence = 'High'; resolutionState = 'unresolved'; evidence = @('Benchmark: 20 ms', 'Trace: request handler'); project = 'src/Library'; files = @('src/Library/Workload.cs'); symbols = @('Workload.Execute'); workload = [ordered]@{ id = 'request'; baseline = '20 ms p95' }; attributedMechanism = 'Allocation on the request path.'; proposedExperiment = 'Measure the representative request.'; correctnessInvariants = @('Existing integration test'); expectedTradeoffs = @('Retains one cached string.'); materialityThreshold = 'At least 5 percent.'; commands = [ordered]@{ baseline = 'dotnet run -- baseline'; candidate = 'dotnet run -- candidate' }; requiredTools = @('dotnet'); requiredArtifacts = @('raw/benchmark.json'); cost = [ordered]@{ inputs = @('cpu-seconds / operation'); missingInputs = @('currency rate') }; productBoundary = [ordered]@{ allowed = 'managed-public-api'; exclusions = $canonicalBoundaryExclusions }; acceptanceConditions = @('Correctness passes and benefit exceeds threshold.'); rejectionConditions = @('Regression, boundary failure, or no material benefit.'); rollbackExpectation = 'Remove the candidate change.' },
            [ordered]@{ id = 'PERF-002'; title = 'Second'; classification = 'Static opportunity'; confidence = 'Moderate'; resolutionState = 'unresolved'; evidence = @('Source inspection', 'Allocation counter'); project = 'src/Library'; files = @('src/Library/Parser.cs'); symbols = @('Parser.Parse'); workload = [ordered]@{ id = 'parse'; baseline = '10 ms p95' }; attributedMechanism = 'Repeated parsing.'; proposedExperiment = 'Benchmark the representative request.'; correctnessInvariants = @('Existing unit test'); expectedTradeoffs = @('Adds a cache entry.'); materialityThreshold = 'At least 5 percent.'; commands = [ordered]@{ baseline = 'dotnet run -- baseline'; candidate = 'dotnet run -- candidate' }; requiredTools = @('dotnet'); requiredArtifacts = @('raw/benchmark.json'); cost = [ordered]@{ inputs = @('allocated-bytes / operation'); missingInputs = @('currency rate') }; productBoundary = [ordered]@{ allowed = 'managed-public-api'; exclusions = $canonicalBoundaryExclusions }; acceptanceConditions = @('Correctness passes and benefit exceeds threshold.'); rejectionConditions = @('Regression, boundary failure, or no material benefit.'); rollbackExpectation = 'Remove the candidate change.' }
        )
    }
    $validManifestPath = Join-Path $manifestDirectory 'valid.manifest.json'
    $validManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validManifestPath -NoNewline
    $beforeHash = (Get-FileHash -LiteralPath $validManifestPath).Hash

    $emptyFindingsManifest = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $emptyFindingsManifest.findings = @()
    $emptyFindingsManifestPath = Join-Path $manifestDirectory 'empty-findings.manifest.json'
    $emptyFindingsManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $emptyFindingsManifestPath -NoNewline
    $emptyPublication = Invoke-Manifest -ManifestPath $emptyFindingsManifestPath
    Assert-That ($emptyPublication.exitCode -eq 0) "Expected a valid publication with no findings to pass: $($emptyPublication.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($emptyPublication.stderr)) 'Expected empty-findings publication stderr to be empty.'
    Assert-That ((@($emptyPublication.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one empty-findings validation JSON document on stdout.'
    Assert-That (($emptyPublication.stdout | ConvertFrom-Json).valid) 'Expected empty-findings publication validation result to be valid.'

    $singleFindingManifest = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $singleFindingManifest.findings = @($singleFindingManifest.findings[0])
    $singleFindingManifestPath = Join-Path $manifestDirectory 'single-finding.manifest.json'
    $singleFindingManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $singleFindingManifestPath -NoNewline
    $singlePublication = Invoke-Manifest -ManifestPath $singleFindingManifestPath
    Assert-That ($singlePublication.exitCode -eq 0) "Expected a valid publication with one finding to pass: $($singlePublication.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($singlePublication.stderr)) 'Expected single-finding publication stderr to be empty.'
    Assert-That ((@($singlePublication.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one single-finding validation JSON document on stdout.'
    Assert-That (($singlePublication.stdout | ConvertFrom-Json).valid) 'Expected single-finding publication validation result to be valid.'

    $publication = Invoke-Manifest -ManifestPath $validManifestPath
    Assert-That ($publication.exitCode -eq 0) "Expected valid publication to pass: $($publication.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($publication.stderr)) 'Expected valid publication stderr to be empty.'
    Assert-That ((@($publication.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one validation JSON document on stdout.'
    Assert-That (($publication.stdout | ConvertFrom-Json).valid) 'Expected publication validation result to be valid.'
    Assert-That ((Get-FileHash -LiteralPath $validManifestPath).Hash -eq $beforeHash) 'Expected publication validation not to rewrite the manifest.'

    $finding = Invoke-Manifest -ManifestPath $validManifestPath -Mode Finding -Id 'PERF-002'
    Assert-That ($finding.exitCode -eq 0) "Expected known finding extraction to pass: $($finding.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($finding.stderr)) 'Expected known finding extraction stderr to be empty.'
    Assert-That ((@($finding.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one finding JSON document on stdout.'
    $findingOutput = $finding.stdout | ConvertFrom-Json
    Assert-That (($findingOutput.PSObject.Properties.Name -join ',') -eq 'repository,finding') 'Expected finding output to contain only repository and finding.'
    Assert-That ($findingOutput.repository.path -eq '<workdir>\sample') 'Expected finding output repository identity.'
    Assert-That ($findingOutput.finding.id -eq 'PERF-002') 'Expected only requested finding output.'
    $singleFinding = Invoke-Manifest -ManifestPath $singleFindingManifestPath -Mode Finding -Id 'PERF-001'
    Assert-That ($singleFinding.exitCode -eq 0) "Expected one-finding extraction to pass: $($singleFinding.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($singleFinding.stderr)) 'Expected one-finding extraction stderr to be empty.'
    Assert-That ((@($singleFinding.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one one-finding JSON document on stdout.'
    Assert-That (($singleFinding.stdout | ConvertFrom-Json).finding.id -eq 'PERF-001') 'Expected one-finding extraction to preserve the selected finding.'
    $unknownFinding = Invoke-Manifest -ManifestPath $validManifestPath -Mode Finding -Id 'PERF-999'
    Assert-That ($unknownFinding.exitCode -ne 0 -and $unknownFinding.stderr -match 'PERF-999') 'Expected unknown finding ID to fail precisely.'

    $invalidCases = @(
        @{ name = 'root-array'; mutate = { param($m) }; error = 'JSON object'; rootArray = $true },
        @{ name = 'schema-version-null'; mutate = { param($m) $m.schemaVersion = $null }; error = 'manifest.schemaVersion' },
        @{ name = 'schema-version-string'; mutate = { param($m) $m.schemaVersion = '1' }; error = 'schemaVersion' },
        @{ name = 'duplicate'; mutate = { param($m) $m.findings[1].id = 'PERF-001' }; error = 'duplicate' },
        @{ name = 'evidence'; mutate = { param($m) $m.findings[0].classification = 'Invented evidence' }; error = 'classification' },
        @{ name = 'classification-casing'; mutate = { param($m) $m.findings[0].classification = 'observed bottleneck' }; error = 'classification' },
        @{ name = 'confidence'; mutate = { param($m) $m.findings[0].confidence = 'Certain' }; error = 'confidence' },
        @{ name = 'confidence-casing'; mutate = { param($m) $m.findings[0].confidence = 'high' }; error = 'confidence' },
        @{ name = 'resolved'; mutate = { param($m) $m.findings[0].resolutionState = 'resolved' }; error = 'unresolved' },
        @{ name = 'repository-path'; mutate = { param($m) $m.repository.PSObject.Properties.Remove('path') }; error = 'repository.path' },
        @{ name = 'repository-head'; mutate = { param($m) $m.repository.PSObject.Properties.Remove('head') }; error = 'repository.head' },
        @{ name = 'repository-branch'; mutate = { param($m) $m.repository.PSObject.Properties.Remove('branch') }; error = 'repository.branch' },
        @{ name = 'audit-started'; mutate = { param($m) $m.audit.PSObject.Properties.Remove('startedUtc') }; error = 'audit.startedUtc' },
        @{ name = 'audit-completed'; mutate = { param($m) $m.audit.PSObject.Properties.Remove('completedUtc') }; error = 'audit.completedUtc' },
        @{ name = 'audit-started-non-iso'; mutate = { param($m) $m.audit.startedUtc = '26/08/2026 09:00' }; error = 'audit.startedUtc' },
        @{ name = 'audit-completed-without-offset'; mutate = { param($m) $m.audit.completedUtc = '2026-08-26T09:05:00' }; error = 'audit.completedUtc' },
        @{ name = 'audit-completed-before-started'; mutate = { param($m) $m.audit.completedUtc = '2026-08-26T08:59:59Z' }; error = 'completedUtc' },
        @{ name = 'unchanged-state'; mutate = { param($m) $m.audit.PSObject.Properties.Remove('targetStateUnchanged') }; error = 'audit.targetStateUnchanged' },
        @{ name = 'finding-id'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('id') }; error = 'finding.id' },
        @{ name = 'finding-title'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('title') }; error = 'finding.title' },
        @{ name = 'finding-classification'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('classification') }; error = 'finding.classification' },
        @{ name = 'finding-confidence'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('confidence') }; error = 'finding.confidence' },
        @{ name = 'finding-resolution'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('resolutionState') }; error = 'finding.resolutionState' },
        @{ name = 'finding-evidence'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('evidence') }; error = 'finding.evidence' },
        @{ name = 'project'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('project') }; error = 'finding.project' },
        @{ name = 'files-scalar'; mutate = { param($m) $m.findings[0].files = 'src/Library/Workload.cs' }; error = 'finding.files' },
        @{ name = 'symbols-empty'; mutate = { param($m) $m.findings[0].symbols = @() }; error = 'finding.symbols' },
        @{ name = 'workload-scalar'; mutate = { param($m) $m.findings[0].workload = 'request' }; error = 'finding.workload' },
        @{ name = 'workload-baseline'; mutate = { param($m) $m.findings[0].workload.PSObject.Properties.Remove('baseline') }; error = 'finding.workload.baseline' },
        @{ name = 'attributed-mechanism'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('attributedMechanism') }; error = 'finding.attributedMechanism' },
        @{ name = 'proposed-experiment'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('proposedExperiment') }; error = 'finding.proposedExperiment' },
        @{ name = 'correctness-invariants-scalar'; mutate = { param($m) $m.findings[0].correctnessInvariants = 'Existing integration test' }; error = 'finding.correctnessInvariants' },
        @{ name = 'expected-tradeoffs'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('expectedTradeoffs') }; error = 'finding.expectedTradeoffs' },
        @{ name = 'materiality-threshold'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('materialityThreshold') }; error = 'finding.materialityThreshold' },
        @{ name = 'commands-scalar'; mutate = { param($m) $m.findings[0].commands = 'dotnet run' }; error = 'finding.commands' },
        @{ name = 'candidate-command'; mutate = { param($m) $m.findings[0].commands.PSObject.Properties.Remove('candidate') }; error = 'finding.commands.candidate' },
        @{ name = 'required-tools-scalar'; mutate = { param($m) $m.findings[0].requiredTools = 'dotnet' }; error = 'finding.requiredTools' },
        @{ name = 'required-artifacts'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('requiredArtifacts') }; error = 'finding.requiredArtifacts' },
        @{ name = 'cost-scalar'; mutate = { param($m) $m.findings[0].cost = 'unknown' }; error = 'finding.cost' },
        @{ name = 'cost-missing-inputs'; mutate = { param($m) $m.findings[0].cost.PSObject.Properties.Remove('missingInputs') }; error = 'finding.cost.missingInputs' },
        @{ name = 'product-boundary-scalar'; mutate = { param($m) $m.findings[0].productBoundary = 'managed-public-api' }; error = 'finding.productBoundary' },
        @{ name = 'product-boundary-wrong-allowed'; mutate = { param($m) $m.findings[0].productBoundary.allowed = 'internal-worker' }; error = 'finding.productBoundary.allowed' },
        @{ name = 'product-boundary-exclusions'; mutate = { param($m) $m.findings[0].productBoundary.PSObject.Properties.Remove('exclusions') }; error = 'finding.productBoundary.exclusions' },
        @{ name = 'acceptance-conditions'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('acceptanceConditions') }; error = 'finding.acceptanceConditions' },
        @{ name = 'rejection-conditions'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('rejectionConditions') }; error = 'finding.rejectionConditions' },
        @{ name = 'rollback-expectation'; mutate = { param($m) $m.findings[0].PSObject.Properties.Remove('rollbackExpectation') }; error = 'finding.rollbackExpectation' },
        @{ name = 'finding-id-array'; mutate = { param($m) $m.findings[0].id = @('PERF-001') }; error = 'finding.id' },
        @{ name = 'finding-title-array'; mutate = { param($m) $m.findings[0].title = @('First') }; error = 'finding.title' },
        @{ name = 'finding-classification-array'; mutate = { param($m) $m.findings[0].classification = @('Observed bottleneck') }; error = 'finding.classification' },
        @{ name = 'finding-confidence-array'; mutate = { param($m) $m.findings[0].confidence = @('High') }; error = 'finding.confidence' },
        @{ name = 'finding-resolution-array'; mutate = { param($m) $m.findings[0].resolutionState = @('unresolved') }; error = 'finding.resolutionState' },
        @{ name = 'proposed-experiment-array'; mutate = { param($m) $m.findings[0].proposedExperiment = @('Measure the representative request.') }; error = 'finding.proposedExperiment' },
        @{ name = 'rollback-expectation-array'; mutate = { param($m) $m.findings[0].rollbackExpectation = @('Remove the candidate change.') }; error = 'finding.rollbackExpectation' }
    )
    foreach ($exclusion in $canonicalBoundaryExclusions) {
        $invalidCases += @{ name = "product-boundary-missing-$exclusion"; mutate = { param($m, $excluded) $m.findings[0].productBoundary.exclusions = @($m.findings[0].productBoundary.exclusions | Where-Object { $_ -cne $excluded }) }.GetNewClosure(); error = 'finding.productBoundary.exclusions'; excluded = $exclusion }
    }
    foreach ($case in $invalidCases) {
        $manifest = $validManifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $excluded = if ($case.ContainsKey('excluded')) { $case.excluded } else { $null }
        & $case.mutate $manifest $excluded
        $caseFileName = $case.name -replace '[\\/:*?"<>|]', '-'
        $path = Join-Path $manifestDirectory "$caseFileName.manifest.json"
        if ($case.ContainsKey('rootArray')) {
            ConvertTo-Json -InputObject @($manifest) -Depth 8 | Set-Content -LiteralPath $path -NoNewline
        }
        else {
            $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -NoNewline
        }
        $invalid = Invoke-Manifest -ManifestPath $path
        Assert-That ($invalid.exitCode -ne 0) "Expected $($case.name) manifest to fail."
        Assert-That ($invalid.stderr -match $case.error) "Expected $($case.name) failure to identify $($case.error): $($invalid.stderr)"
    }

    New-Item -ItemType Directory -Path (Join-Path $boundaryRepo 'src') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Product.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Worker.cs') -Value 'class Worker { }'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\MultiHunk.cs') -Value @(
        'class MultiHunk',
        '{',
        '    void First() { }',
        '    /* existing block',
        '    still comment',
        '    */',
        '    void Second() { }',
        '}'
    )
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'README.md') -Value @('heading', 'context', 'baseline')
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\preexisting.dll') -Value 'harmless baseline text'
    & git -C $boundaryRepo init -q
    & git -C $boundaryRepo config user.email 'contract@example.test'
    & git -C $boundaryRepo config user.name 'Contract Test'
    & git -C $boundaryRepo add .
    & git -C $boundaryRepo commit -qm 'baseline'

    $invalidBoundary = Invoke-ManagedBoundary -Repository $boundaryRepo -BaseRef 'missing-base'
    Assert-That ($invalidBoundary.exitCode -eq 2) 'Expected an invalid base ref to be an invocation error.'
    Assert-That ([string]::IsNullOrWhiteSpace($invalidBoundary.stdout)) 'Expected invocation errors not to emit JSON stdout.'
    Assert-That ($invalidBoundary.stderr -match 'Managed product boundary invocation error') 'Expected a precise invocation error on stderr.'

    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Worker.cs') -Value 'class Worker { int Count() => System.Math.Clamp(2, 0, 3); }'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'README.md') -Value @('heading', 'context', 'updated')
    & git -C $boundaryRepo add .
    $safe = Invoke-ManagedBoundary -Repository $boundaryRepo
    Assert-That ($safe.exitCode -eq 0) "Expected managed BCL addition audit to complete: $($safe.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($safe.stderr)) 'Expected managed BCL addition stderr to be empty.'
    Assert-That ((@($safe.stdout -split "`r?`n" | Where-Object { $_.Trim() }).Count -eq 1)) 'Expected exactly one managed-boundary JSON document on stdout.'
    $safeOutput = $safe.stdout | ConvertFrom-Json
    Assert-That ($safeOutput.manualReviewLimitations -contains 'Concurrent working-tree mutation during the scan invalidates its result.') 'Expected concurrent working-tree mutation to be an explicit boundary limitation.'
    Assert-That $safeOutput.passed 'Expected ordinary managed BCL addition to pass.'
    Assert-That ($safeOutput.reviewedRange -match '\.\.working-tree$') 'Expected an explicit reviewed working-tree range.'
    Assert-That ($safeOutput.manualReviewLimitations -contains 'Generated code requires manual review.') 'Expected generated-code manual-review limitation.'

    & git -C $boundaryRepo reset --hard -q HEAD
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\MultiHunk.cs') -Value @(
        'class MultiHunk',
        '{',
        '    /* added block opener',
        '    /* existing block',
        '    still comment',
        '    */',
        '    unsafe void Second() { }',
        '}'
    )
    $multiHunk = Invoke-ManagedBoundary -Repository $boundaryRepo
    $multiHunkOutput = $multiHunk.stdout | ConvertFrom-Json
    Assert-That ($multiHunk.exitCode -eq 0 -and -not $multiHunkOutput.passed) "Expected lexical state to follow unchanged lines between diff hunks: $($multiHunk.stderr)"
    Assert-That (@($multiHunkOutput.violations | Where-Object { $_.path -eq 'src/MultiHunk.cs' -and $_.line -eq 7 -and $_.rule -eq 'unsafe-code' }).Count -eq 1) 'Expected unsafe code in the later hunk to be detected at its working-tree line.'

    & git -C $boundaryRepo reset --hard -q HEAD
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\UntrackedUnsafe.cs') -Value 'class UntrackedUnsafe { void Run() { var u = "http://x"; unsafe { } } }'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\untracked.dll') -Value 'harmless untracked text'
    $untracked = Invoke-ManagedBoundary -Repository $boundaryRepo
    $untrackedOutput = $untracked.stdout | ConvertFrom-Json
    Assert-That ($untracked.exitCode -eq 0 -and -not $untrackedOutput.passed) "Expected untracked unsafe source and native extension to fail without staging: $($untracked.stderr)"
    Assert-That (($untrackedOutput.violations.path -contains 'src/UntrackedUnsafe.cs') -and ($untrackedOutput.violations.path -contains 'src/untracked.dll') -and $untrackedOutput.violations.rule -contains 'unsafe-code') 'Expected untracked source, URL-following unsafe code, and native path evidence.'

    & git -C $boundaryRepo reset --hard -q HEAD
    Remove-Item -LiteralPath (Join-Path $boundaryRepo 'src\UntrackedUnsafe.cs') -Force
    Remove-Item -LiteralPath (Join-Path $boundaryRepo 'src\untracked.dll') -Force
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Worker.cs') -Value 'class Worker { string Note = "DllImport LibraryImport NativeLibrary PInvoke unsafe System.Runtime.Intrinsics http://x"; }'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\preexisting.dll') -Value 'modified harmless text'
    & git -C $boundaryRepo add .
    $stringOnly = Invoke-ManagedBoundary -Repository $boundaryRepo
    $stringOnlyOutput = $stringOnly.stdout | ConvertFrom-Json
    Assert-That ($stringOnly.exitCode -eq 0 -and $stringOnlyOutput.passed) "Expected forbidden words in a string and modification of a pre-existing native extension to pass: $($stringOnly.stderr)"

    & git -C $boundaryRepo reset --hard -q HEAD
    Remove-Item -LiteralPath (Join-Path $boundaryRepo 'src\preexisting.dll') -Force
    $deletedNative = Invoke-ManagedBoundary -Repository $boundaryRepo
    $deletedNativeOutput = $deletedNative.stdout | ConvertFrom-Json
    Assert-That ($deletedNative.exitCode -eq 0 -and $deletedNativeOutput.passed) "Expected deletion of a pre-existing native extension not to fail: $($deletedNative.stderr)"

    $interopCases = @(
        @{ name = 'AllowUnsafeBlocks'; content = '<AllowUnsafeBlocks>true</AllowUnsafeBlocks>'; rule = 'unsafe-code' },
        @{ name = 'DllImport'; content = '[DllImport("native")] static extern int Call();'; rule = 'native-interop' },
        @{ name = 'LibraryImport'; content = '[LibraryImport("native")] static partial void Call();'; rule = 'native-interop' },
        @{ name = 'NativeLibrary'; content = 'var handle = NativeLibrary.Load("native");'; rule = 'native-interop' },
        @{ name = 'PInvoke'; content = 'PInvoke.Call();'; rule = 'native-interop' }
    )
    & git -C $boundaryRepo reset --hard -q HEAD
    foreach ($case in $interopCases) {
        Set-Content -LiteralPath (Join-Path $boundaryRepo "src\$($case.name).cs") -Value $case.content
    }
    & git -C $boundaryRepo add .
    $interop = Invoke-ManagedBoundary -Repository $boundaryRepo
    $interopOutput = $interop.stdout | ConvertFrom-Json
    foreach ($case in $interopCases) {
        Assert-That ($interop.exitCode -eq 0 -and -not $interopOutput.passed -and (@($interopOutput.violations | Where-Object { $_.path -eq "src/$($case.name).cs" -and $_.rule -eq $case.rule }).Count -eq 1)) "Expected $($case.name) to independently trigger $($case.rule): $($interopOutput | ConvertTo-Json -Depth 6 -Compress) $($interop.stderr)"
    }

    & git -C $boundaryRepo reset --hard -q HEAD
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Unsafe.cs') -Value 'unsafe class UnsafeWorker { }'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Intrinsic.cs') -Value 'using System.Runtime.Intrinsics; class IntrinsicWorker { }'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Interop.cs') -Value '[System.Runtime.InteropServices.DllImport("native")] [System.Runtime.InteropServices.LibraryImport("native")] static partial void Call(); var handle = System.Runtime.InteropServices.NativeLibrary.Load("native"); // PInvoke declaration'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\native.dll') -Value 'not-a-real-binary'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\native.so') -Value 'not-a-real-binary'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\native.dylib') -Value 'not-a-real-binary'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\native.a') -Value 'not-a-real-binary'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\native.lib') -Value 'not-a-real-binary'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\native.exe') -Value 'not-a-real-binary'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Product.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><PackageReference Include="Fast.Native" Version="1.0.0" /><ProjectReference Include="../other/Other.csproj" /></ItemGroup></Project>'
    & git -C $boundaryRepo add .
    $unsafe = Invoke-ManagedBoundary -Repository $boundaryRepo
    Assert-That ($unsafe.exitCode -eq 0) "Expected boundary violations to return JSON, not an invocation failure: $($unsafe.stderr)"
    Assert-That ([string]::IsNullOrWhiteSpace($unsafe.stderr)) 'Expected boundary violations stderr to be empty.'
    $unsafeOutput = $unsafe.stdout | ConvertFrom-Json
    Assert-That (-not $unsafeOutput.passed) 'Expected unsafe, intrinsics, interop, and native binary changes to fail.'
    Assert-That (($unsafeOutput.violations.rule -contains 'unsafe-code') -and ($unsafeOutput.violations.rule -contains 'runtime-intrinsics') -and ($unsafeOutput.violations.rule -contains 'native-interop') -and ($unsafeOutput.violations.rule -contains 'native-binary')) 'Expected each prohibited boundary category to be reported.'
    Assert-That ((@($unsafeOutput.violations | Where-Object rule -eq 'native-binary').Count -eq 6)) 'Expected every prohibited native binary extension to be reported.'
    Assert-That (($unsafeOutput.warnings.rule -contains 'dependency-change') -and ($unsafeOutput.warnings.rule -contains 'project-dependency')) 'Expected added package and project dependencies to require manual confirmation.'
    Assert-That $unsafeOutput.warningDispositionRequired 'Expected warnings to require explicit disposition before acceptance.'

    & git -C $boundaryRepo reset --hard -q HEAD
    Get-ChildItem -LiteralPath (Join-Path $boundaryRepo 'src') -File | Where-Object Name -ne 'preexisting.dll' | Remove-Item -Force
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Untracked.fs') -Value 'let handle = NativeLibrary.Load("native")'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Untracked.vb') -Value 'Declare Auto Function NativeCall Lib "native" () As Integer'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Generated.g.fs') -Value '[<DllImport("native")>] extern int NativeCall()'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Generated.generated.vb') -Value 'Declare Function GeneratedCall Lib "native" () As Integer'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Added.fsproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><PackageReference Include="Ambiguous.Dependency" Version="1.0.0" /></ItemGroup></Project>'
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Added.vbproj') -Value '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup><ProjectReference Include="..\Other\Other.vbproj" /></ItemGroup></Project>'
    $languageBoundary = Invoke-ManagedBoundary -Repository $boundaryRepo
    $languageOutput = $languageBoundary.stdout | ConvertFrom-Json
    Assert-That ($languageBoundary.exitCode -eq 0 -and -not $languageOutput.passed) "Expected untracked F#, VB, generated interop, and project inputs to be inspected: $($languageBoundary.stderr)"
    foreach ($path in @('src/Untracked.fs', 'src/Untracked.vb', 'src/Generated.g.fs', 'src/Generated.generated.vb')) {
        Assert-That (($languageOutput.violations | Where-Object path -eq $path).Count -eq 1) "Expected native interop evidence for $path."
    }
    Assert-That (($languageOutput.warnings | Where-Object rule -eq 'generated-code-review').Count -eq 2) 'Expected generated F#/VB inputs to require manual review.'
    Assert-That (($languageOutput.warnings | Where-Object rule -eq 'dependency-change').Count -eq 1) 'Expected an F# package dependency to require manual review.'
    Assert-That (($languageOutput.warnings | Where-Object rule -eq 'project-dependency').Count -eq 1) 'Expected a VB project dependency to require manual review.'
    Assert-That $languageOutput.warningDispositionRequired 'Expected ambiguous native dependencies and generated inputs to require explicit warning disposition.'

    & git -C $boundaryRepo reset --hard -q HEAD
    Remove-Item -LiteralPath @(
        (Join-Path $boundaryRepo 'src\Untracked.fs'),
        (Join-Path $boundaryRepo 'src\Untracked.vb'),
        (Join-Path $boundaryRepo 'src\Generated.g.fs'),
        (Join-Path $boundaryRepo 'src\Generated.generated.vb'),
        (Join-Path $boundaryRepo 'src\Added.fsproj'),
        (Join-Path $boundaryRepo 'src\Added.vbproj')
    ) -Force
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'src\Worker.cs') -Value '// DllImport NativeLibrary System.Runtime.Intrinsics unsafe PInvoke`nclass Worker { }'
    & git -C $boundaryRepo add .
    $comment = Invoke-ManagedBoundary -Repository $boundaryRepo
    $commentOutput = $comment.stdout | ConvertFrom-Json
    Assert-That ($comment.exitCode -eq 0 -and $commentOutput.passed) "Expected forbidden terms in a comment alone not to fail: $($comment.stderr)"

    & git -C $boundaryRepo reset --hard -q HEAD
    New-Item -ItemType Directory -Path (Join-Path $boundaryRepo 'outside') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $boundaryRepo 'outside\Unsafe.cs') -Value 'unsafe class Outside { }'
    & git -C $boundaryRepo add .
    $scoped = Invoke-ManagedBoundary -Repository $boundaryRepo -ProductPath @('src')
    $scopedOutput = $scoped.stdout | ConvertFrom-Json
    Assert-That ($scoped.exitCode -eq 0 -and $scopedOutput.passed) "Expected ProductPath scope to exclude changes outside src: $($scoped.stderr)"

    if (-not $IsWindows) {
        $caseVariant = $boundaryRepo.ToUpperInvariant()
        $caseSensitiveScope = Invoke-ManagedBoundary -Repository $boundaryRepo -ProductPath @($caseVariant)
        Assert-That ($caseSensitiveScope.exitCode -eq 2) 'Expected non-Windows path containment to use ordinal case-sensitive comparison.'
    }

    Write-Host 'PASS: inventory and manifest contracts verified.'
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
    if (Test-Path -LiteralPath $notARepo) {
        Remove-Item -LiteralPath $notARepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $limitRepo) {
        Remove-Item -LiteralPath $limitRepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $markerLimitRepo) {
        Remove-Item -LiteralPath $markerLimitRepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $directoryRepo) {
        Remove-Item -LiteralPath $directoryRepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $projectTruncationRepo) {
        Remove-Item -LiteralPath $projectTruncationRepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $projectScaleRepo) {
        Remove-Item -LiteralPath $projectScaleRepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $globalJsonWithoutSdkRepo) {
        Remove-Item -LiteralPath $globalJsonWithoutSdkRepo -Recurse -Force
    }
    if (Test-Path -LiteralPath $manifestDirectory) {
        Remove-Item -LiteralPath $manifestDirectory -Recurse -Force
    }
    if (Test-Path -LiteralPath $boundaryRepo) {
        Remove-Item -LiteralPath $boundaryRepo -Recurse -Force
    }
}
