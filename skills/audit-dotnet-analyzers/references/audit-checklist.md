# Audit checklist — evidence and effective configuration

Read when performing a repository or workspace audit.

## Evidence inventory

Inspect where present. Absence is itself evidence — record it.

**SDK / language**
`global.json` · `TargetFramework(s)` · `LangVersion` · installed SDK actually selected

**MSBuild layers**
`Directory.Build.props` / `.targets` · `Directory.Packages.props` · `Directory.Build.rsp` · `*.csproj` / `*.fsproj` · `*.sln` / `*.slnx`

**Analyzer / style config**
Every `.editorconfig` in the hierarchy (root-most down) · `*.globalconfig` · `.ruleset` files · rules shipped **inside** analyzer packages

**Packages**
`SonarAnalyzer.CSharp` · `Microsoft.CodeAnalysis.NetAnalyzers` · StyleCop · Roslynator · Meziantou · shared in-house CodeStyle packages · `packages.lock.json` · `NuGet.config`

**Policy properties**
`TreatWarningsAsErrors` · `WarningsAsErrors` · `WarningsNotAsErrors` · `NoWarn` · `AnalysisLevel` · `AnalysisMode` · `EnableNETAnalyzers` · `EnforceCodeStyleInBuild` · `Nullable`

**Elsewhere**
CI workflows running analyzers, formatters or gates · ReSharper/Rider CLI inspection config · repo instructions telling agents how to treat findings

## Bundled analyzers — the attribution trap

A shared CodeStyle package can carry SonarAnalyzer, a global AnalyzerConfig, and `EnforceCodeStyleInBuild` all at once, via a single `GlobalPackageReference`. Sonar rules then apply with **no `SonarAnalyzer.CSharp` reference anywhere in the repo**.

Grepping the repo for analyzer package names will miss this. Resolve what the package actually ships — inspect its contents in the NuGet cache (`~/.nuget/packages/<id>/<version>/`): its `.nuspec` dependencies and any `*.globalconfig` it carries.

## Resolving effective severity

A rule's effective severity is the product of layers, not of any single file. Establish, in order:

1. **Analyzer default** — the severity the rule ships with when nothing configures it.
2. **Global AnalyzerConfig** (`is_global = true`, ranked by `global_level`) — typically from a package.
3. **`.editorconfig`** — path-specific; more specific paths win.
4. **MSBuild** — `NoWarn`, `WarningsAsErrors`, `WarningsNotAsErrors`, `TreatWarningsAsErrors`.

Do **not** assert the precedence between a global AnalyzerConfig and `.editorconfig` from memory. Verify it for the SDK in play — the answer has changed across Roslyn versions.

**The common contradiction:** a style layer sets a modern-idiom rule to `suggestion` (advisory, never breaks a build) while an unconfigured analyzer rule pulling the *opposite* way keeps its default `warning` — which `TreatWarningsAsErrors` then promotes to a build-breaking **error**. The error wins, the suggestion loses, and the repo enforces the reverse of its stated policy. A rule absent from every config file is not "off"; it is at its default, and TWAE may be arming it.

Prefer observed output over inference:

```shell
dotnet build -p:TreatWarningsAsErrors=false -v:n
dotnet msbuild -getProperty:LangVersion,TargetFramework,TreatWarningsAsErrors,WarningsNotAsErrors,EnforceCodeStyleInBuild,AnalysisLevel
```

Keep commands proportionate. A config audit is not a test campaign.

## Per-project questions

- Do production and test projects differ — intentionally, or by accident?
- Do local and CI enforcement differ?
- Are settings redundant, contradictory or shadowed?
- Are IDE style rules enforced at build (`EnforceCodeStyleInBuild`) or advisory only?

## Modern-idiom sweep

Does effective configuration encourage, permit, discourage, or *accidentally block*: collection expressions · target-typed `new` · switch expressions and patterns · primary constructors · records · file-scoped namespaces · global usings · nullable reference types · required members · init-only properties · expression-bodied members · current argument-validation · async/cancellation analysis · spans · generated regex · current BCL APIs for the TFM.

Assess clarity, correctness, semantics, maintainability — not modernity for its own sake.

## Workspace mode

Discover repos by locating `.git` directories; respect nested-repository boundaries. Audit each, then compare: SDK, TFM, LangVersion, analyzer package versions, warning policy, shared-package version. Drift in the *shared CodeStyle package version* across repos is a finding in its own right.
