$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$skill = Get-Content -Raw (Join-Path $skillRoot 'SKILL.md')
$timing = Get-Content -Raw (Join-Path $skillRoot 'references' 'async-and-timing.md')
$budgets = Get-Content -Raw (Join-Path $skillRoot 'references' 'ci-test-budgets.md')
# The canonical traps note lives OUTSIDE this repository, so it is absent on CI and on
# any machine that is not this estate. $HOME, not $env:USERPROFILE: the latter is
# undefined off Windows and Join-Path rejects a null -Path.
# $null means ABSENT (skip); an empty string means present-but-empty, which must still be
# asserted against and fail. Gating on truthiness would turn a truncated note into a pass.
$trapsPath = Join-Path $HOME '.agents' 'notes' 'dotnet-runtime-traps.md'
$traps = if (Test-Path -LiteralPath $trapsPath) { [string](Get-Content -Raw -LiteralPath $trapsPath) } else {
    Write-Host "SKIP: canonical note not present on this host - $trapsPath"
    $null
}
$allGuidance = "$skill`n$timing`n$budgets"

function Require([string] $Text, [string] $Pattern, [string] $Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Forbid([string] $Text, [string] $Pattern, [string] $Message) {
    if ($Text -match $Pattern) { throw $Message }
}

Forbid $skill 'Substitute\.For<IFusionCache>' 'Do not mock FusionCache extension methods.'
Require $skill 'Substitute\.For<IFruitCache>' 'The mocking example must use an app-owned interceptable interface.'
Forbid $skill '(?m)^\s*Assert\.' 'All sample assertions must use AwesomeAssertions.'
Require $skill 'false\.Should\(\)\.BeTrue' 'The timeout diagnostic must fail through AwesomeAssertions.'

$frameworkCases = @(
    @{ Name = 'xUnit v2'; Pattern = '(?im)^\|\s*xUnit v2\s*\|.*?\bKeep\b' },
    @{ Name = 'xUnit v3'; Pattern = '(?im)^\|\s*xUnit v3\s*\|.*?\bKeep\b' },
    @{ Name = 'NUnit'; Pattern = '(?im)^\|\s*NUnit\s*\|.*?\bKeep\b' }
)

foreach ($case in $frameworkCases) {
    Require $skill $case.Pattern "Existing $($case.Name) projects must keep their established framework."
}

Require $skill '(?is)inspect.*?(?:PackageReference|Directory\.Packages\.props).*?(?:xunit|nunit)' 'Framework detection must inspect existing project or central package declarations.'
Require $skill '(?is)no existing test framework.*?xunit\.v3' 'xUnit v3 must be the default only when no existing framework is found.'
Require $skill '(?is)xunit\.v3.*?new (?:solution|project)' 'xUnit v3 package and layout guidance must be scoped to new projects.'
Forbid $skill '(?im)^\|\s*NUnit\s*\|[^\r\n]*xunit' 'NUnit preservation must not add xUnit packages.'
Require $skill '(?s)public sealed class Fruit.*?public interface IFruitCache.*?public sealed class FruitLookup.*?public sealed class FruitLookupTests' 'The sample must be one self-contained example with app-owned stubs and a test.'
Require $skill 'found\.Should\(\)\.Be\(expected\)' 'The self-contained example must assert the SUT result through AwesomeAssertions.'
$sampleMatch = [regex]::Match($skill, '(?s)xUnit example \(v2/v3 only\):\s*```csharp\r?\n(?<code>.*?)\r?\n```')
if (-not $sampleMatch.Success) { throw 'The xUnit compatibility example code block is missing.' }
$sample = $sampleMatch.Groups['code'].Value
Require $sample '(?m)^using System\.Threading;$' 'The compatibility example must import CancellationToken without implicit usings.'
Require $sample '(?m)^using System\.Threading\.Tasks;$' 'The compatibility example must import Task without implicit usings.'
Forbid $sample '\bFruit\?' 'The compatibility example must not require nullable-reference settings.'
Forbid $skill '(?im)^-\s*Prefer one \[Theory\]' 'xUnit-only theory guidance must not be global.'
Require $skill '(?is)In xUnit.*?\[Theory\].*?\[InlineData\].*?NUnit.*?\[Test\].*?\[TestCase\]' 'xUnit and NUnit parameterized-test syntax must be scoped explicitly.'
Require $skill '(?is)xUnit example.*?using Xunit.*?\[Fact\]' 'The xUnit sample must be labelled as xUnit-specific.'
Require $skill '(?is)existing.*?NSubstitute.*?AwesomeAssertions.*?if absent.*?(?:without|do not).*?(?:upgrade|convert).*?(?:framework|runner)' 'Existing suites may add compatible assertion and substitute packages without framework conversion.'

Require $allGuidance 'WaitAsync\(TimeSpan' 'Operation-local WaitAsync deadlines must be allowed.'
Require $allGuidance 'CancelAfter' 'Cancellation-token-backed deadlines must be allowed.'
Require $allGuidance '(?i)conservative' 'Framework timeouts must require xUnit conservative scheduling.'
Require $allGuidance '(?i)aggressive' 'The xUnit aggressive-scheduling hazard must be named.'
Require $allGuidance '(?i)parallelization (?:is )?disabled' 'Disabled parallelism must be documented as the other safe framework-timeout mode.'
Require $allGuidance 'https://xunit.net/docs/running-tests-in-parallel' 'The timing reference must link to the official xUnit parallelism documentation.'
Require $skill 'references/async-and-timing\.md' 'Detailed timing guidance belongs in one supporting reference.'
Require $skill 'references/ci-test-budgets\.md' 'CI eligibility and lane budgets belong in one supporting reference.'
Require $skill '(?i)common mistakes' 'The main skill needs a compact common-mistakes section.'

Require $budgets '(?i)30 seconds' 'A PR test case must have a 30-second hard ceiling.'
Require $budgets '(?i)10 minutes' 'A substantive required PR job must have a 10-minute hard ceiling.'
Require $budgets '(?i)15 aggregate runner-minutes' 'PR CI must state the aggregate runner-minute target.'
Require $budgets '(?i)45 minutes' 'A weekly extended-test job must have a 45-minute hard ceiling.'
Require $budgets '(?is)end-to-end.*stress.*load.*soak' 'Inherently expensive test kinds must be named as extended-lane work.'
Require $budgets '(?i)separate test project' 'PR and extended lanes must be separated structurally.'
Require $budgets '(?is)(weekly.*workflow_dispatch|workflow_dispatch.*weekly)' 'Extended tests must be weekly and manually runnable.'
Require $budgets '(?i)never retry|not retry' 'A budget failure must not be hidden by a retry.'
Require $budgets '(?i)never (?:a )?required PR gate' 'Manual extended runs must not become a hidden per-PR requirement.'
Require $budgets '--blame-hang-timeout 30s' 'VSTest PR commands must use the native per-test ceiling.'
Require $budgets '--blame-hang-dump-type none' 'VSTest timeouts must avoid paid dump collection.'

if ($null -ne $traps) {
    Require $traps '### Canonical test deadline policy' 'The canonical runtime traps note must carry the same timeout policy.'
    Require $traps 'WaitAsync\(timeout\)' 'The canonical policy must permit operation-local deadlines.'
    Require $traps '(?i)Conservative' 'The canonical policy must constrain xUnit framework timeouts.'
}

$wordCount = ([regex]::Matches($skill, '\b[\p{L}\p{N}][\p{L}\p{N}''.-]*\b')).Count
if ($wordCount -gt 900) { throw "SKILL.md is still too large ($wordCount words); move timing rationale to the reference." }

Write-Host "PASS: scaffold-tests contract ($wordCount words)"
