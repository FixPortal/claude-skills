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
                    '<PackageVersion Include="YourOrg.CodeStyle"',
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

# Every xml snippet here is meant to be pasted into a project file, so it has to PARSE.
# An angle-bracket placeholder is fine in prose and fatal inside an attribute value:
# Include="<YourOrg.CodeStyle>" fails with "'<', hexadecimal value 0x3C, is an invalid
# attribute character", so the reader's first copy-paste is a parse error. Sanitisation
# put it there, which is why a string needle is not enough - parse the block instead.
# Fences in this file are indented under list items, so both delimiters have to tolerate
# leading whitespace. Anchoring the closing fence at column 0 silently swallows the prose
# between one block and the next, which parses as nothing and "fails" for the wrong reason.
$xmlBlocks = [regex]::Matches($text, '(?sm)^[ \t]*```xml[ \t]*\r?\n(?<body>.*?)\r?\n[ \t]*```')
if ($xmlBlocks.Count -eq 0) { throw 'no xml example blocks found; the parse check is vacuous' }
foreach ($block in $xmlBlocks) {
    $body = $block.Groups['body'].Value
    try {
        # Most snippets are fragments (a bare ItemGroup, a bare PackageVersion) and need a
        # root before parsing. A snippet that opens with its own XML declaration is already
        # a whole document, and wrapping that would move the declaration off the first line,
        # failing for a reason the snippet did not commit.
        $doc = if ($body.TrimStart() -like '<?xml*') { $body } else { "<root>$body</root>" }
        $null = [xml]$doc
    }
    catch {
        throw "an xml example does not parse: $($_.Exception.Message)`n$body"
    }
}

'scaffold-dotnet package contract OK'
