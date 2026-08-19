$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw

foreach ($stale in 'All NuGet packages must be updated to latest release versions that support .NET 10',
                    'dotnet add package <YourOrg.CodeStyle>',
                    'look up the current release on NuGet.org',
                    'charset, indent, EOL, spacing, wrapping',
                    'Sonar S-rules stay advisory (warning,',
                    'Example — greenfield solution') {
    if ($text -match [regex]::Escape($stale)) {
        throw "scaffold-dotnet retains stale package guidance: $stale"
    }
}

foreach ($needle in '~/.agents/notes/dotnet-runtime-traps.md',
                    'restore, build, and test',
                    'Microsoft.OpenApi', '2.x',
                    'GitHub Packages', 'Directory.Packages.props',
                    '<PackageVersion Include="<YourOrg.CodeStyle>"',
                    'layout primitives', 'max-line-length',
                    'Sonar S-rules are warning-level by default',
                    'TreatWarningsAsErrors', 'build-blocking',
                    'Example — minimal CLI skeleton', 'intentionally omits') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "scaffold-dotnet missing package compatibility contract: $needle"
    }
}

foreach ($stale in 'Existing projects should be updated to match these preferences.',
                    'Migrate existing `.sln` files with `dotnet solution <file>.sln migrate`.',
                    'Existing projects must be moved into the appropriate folder',
                    'Existing projects must be updated to `net10.0`',
                    'All projects target `net10.0`') {
    if ($text -match [regex]::Escape($stale)) {
        throw "scaffold-dotnet overwrites an existing project contract: $stale"
    }
}

foreach ($needle in 'Existing-project normalization preserves its target frameworks and layout unless a migration is explicitly authorized.',
                    'netstandard2.0',
                    'do not assume C# 12 features.') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "scaffold-dotnet missing target and routing contract: $needle"
    }
}

if ($text -notmatch 'For a new minimal API, run\s+`scaffold-dotnet` first and then\s+`scaffold-minimal`\.') {
    throw 'scaffold-dotnet must route new minimal APIs through scaffold-dotnet before scaffold-minimal'
}

'scaffold-dotnet package contract OK'
