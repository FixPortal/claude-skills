#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RepositoryPath,

    [Parameter(Mandatory)]
    [string] $BaseRef,

    [string[]] $ProductPath = @('.')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exit 0 means the audit completed (including boundary violations); exit 2 means it could not run.
function Invoke-GitReadOnly {
    param([string] $Repository, [string[]] $GitArguments)

    $output = @(& git -C $Repository @GitArguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($output -join ' ')"
    }

    return @($output | ForEach-Object ToString)
}

function Get-ProductPathspec {
    param([string] $Repository, [string[]] $Paths)

    $root = [IO.Path]::GetFullPath($Repository)
    $separator = [IO.Path]::DirectorySeparatorChar
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $pathspec = foreach ($path in $Paths) {
        $fullPath = if ([IO.Path]::IsPathRooted($path)) { [IO.Path]::GetFullPath($path) } else { [IO.Path]::GetFullPath((Join-Path $root $path)) }
        if (-not $fullPath.Equals($root, $comparison) -and -not $fullPath.StartsWith("$root$separator", $comparison)) {
            throw "ProductPath '$path' is outside RepositoryPath."
        }
        $relative = [IO.Path]::GetRelativePath($root, $fullPath)
        if ($relative -eq '.') { '.' } else { $relative.Replace($separator, '/') }
    }
    return @($pathspec)
}

function Get-FSharpCode {
    param([string] $Line, [ref] $State)

    $code = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Line.Length;) {
        if ($State.Value -eq 'block') {
            if ($index + 1 -lt $Line.Length -and $Line.Substring($index, 2) -eq '*)') { $State.Value = 'code'; $index += 2 } else { $index++ }
            continue
        }
        if ($State.Value -eq 'string') {
            if ($Line[$index] -eq '\\' -and $index + 1 -lt $Line.Length) { $index += 2; continue }
            if ($Line[$index] -eq '"') { $State.Value = 'code' }
            $index++
            continue
        }
        if ($index + 1 -lt $Line.Length -and $Line.Substring($index, 2) -eq '//') { break }
        if ($index + 1 -lt $Line.Length -and $Line.Substring($index, 2) -eq '(*') { $State.Value = 'block'; $index += 2; continue }
        if ($Line[$index] -eq '"') { $State.Value = 'string'; $index++; continue }
        [void]$code.Append($Line[$index])
        $index++
    }
    if ($State.Value -eq 'string') { $State.Value = 'code' }
    return [pscustomobject]@{ code = $code.ToString(); ambiguous = $false }
}

function Get-VisualBasicCode {
    param([string] $Line, [ref] $State)

    $trimmed = $Line.TrimStart()
    if ($trimmed -match '(?i)^REM(?:\s|$)') { return [pscustomobject]@{ code = ''; ambiguous = $false } }
    $code = [Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Line.Length;) {
        if ($State.Value -eq 'string') {
            if ($Line[$index] -eq '"') {
                if ($index + 1 -lt $Line.Length -and $Line[$index + 1] -eq '"') { $index += 2; continue }
                $State.Value = 'code'
            }
            $index++
            continue
        }
        if ($Line[$index] -eq "'") { break }
        if ($Line[$index] -eq '"') { $State.Value = 'string'; $index++; continue }
        [void]$code.Append($Line[$index])
        $index++
    }
    if ($State.Value -eq 'string') { $State.Value = 'code' }
    return [pscustomobject]@{ code = $code.ToString(); ambiguous = $false }
}

function Get-CSharpCode {
    param([string] $Line, [ref] $State)

    $code = [Text.StringBuilder]::new()
    $ambiguous = $false
    for ($index = 0; $index -lt $Line.Length;) {
        if ($State.Value -eq 'block') {
            if ($index + 1 -lt $Line.Length -and $Line[$index] -eq '*' -and $Line[$index + 1] -eq '/') { $State.Value = 'code'; $index += 2 } else { $index++ }
            continue
        }
        if ($State.Value -eq 'string') {
            if ($Line[$index] -eq '\\' -and $index + 1 -lt $Line.Length) { $index += 2; continue }
            if ($Line[$index] -eq '"') { $State.Value = 'code' }
            $index++
            continue
        }
        if ($State.Value -eq 'verbatim') {
            if ($Line[$index] -eq '"') {
                if ($index + 1 -lt $Line.Length -and $Line[$index + 1] -eq '"') { $index += 2; continue }
                $State.Value = 'code'
            }
            $index++
            continue
        }
        if ($State.Value -eq 'raw') {
            if ($index + 2 -lt $Line.Length -and $Line.Substring($index, 3) -eq '"""') { $State.Value = 'code'; $index += 3 } else { $index++ }
            continue
        }

        $character = $Line[$index]
        if ($character -eq '/' -and $index + 1 -lt $Line.Length) {
            if ($Line[$index + 1] -eq '/') { break }
            if ($Line[$index + 1] -eq '*') { $State.Value = 'block'; $index += 2; continue }
        }
        if ($character -eq '"') {
            if ($index + 2 -lt $Line.Length -and $Line.Substring($index, 3) -eq '"""') { $State.Value = 'raw'; $ambiguous = $true; $index += 3; continue }
            $State.Value = 'string'; $index++; continue
        }
        if ($character -eq '@' -and $index + 1 -lt $Line.Length -and $Line[$index + 1] -eq '"') { $State.Value = 'verbatim'; $index += 2; continue }
        if ($character -eq '$' -and $index + 1 -lt $Line.Length -and $Line[$index + 1] -eq '"') { $State.Value = 'string'; $index += 2; continue }
        if ($character -eq '$' -and $index + 2 -lt $Line.Length -and $Line[$index + 1] -eq '@' -and $Line[$index + 2] -eq '"') { $State.Value = 'verbatim'; $index += 3; continue }
        if ($character -eq '@' -and $index + 2 -lt $Line.Length -and $Line[$index + 1] -eq '$' -and $Line[$index + 2] -eq '"') { $State.Value = 'verbatim'; $index += 3; continue }
        if ($character -eq "'") {
            $index++
            if ($index -lt $Line.Length -and $Line[$index] -eq '\\') { $index++ }
            if ($index -lt $Line.Length) { $index++ }
            if ($index -lt $Line.Length -and $Line[$index] -eq "'") { $index++ } else { $ambiguous = $true }
            continue
        }
        [void]$code.Append($character)
        $index++
    }
    if ($State.Value -eq 'string') { $State.Value = 'code'; $ambiguous = $true }
    return [pscustomobject]@{ code = $code.ToString(); ambiguous = $ambiguous }
}

try {
    $repository = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $repository -PathType Container)) { throw "RepositoryPath '$RepositoryPath' is not a directory." }
    if (@(Invoke-GitReadOnly -Repository $repository -GitArguments @('rev-parse', '--is-inside-work-tree'))[0] -ne 'true') { throw "RepositoryPath '$repository' is not a Git work tree." }
    $baseCommit = @(Invoke-GitReadOnly -Repository $repository -GitArguments @('rev-parse', '--verify', "$BaseRef^{commit}"))[0]
    $pathspec = Get-ProductPathspec -Repository $repository -Paths $ProductPath
    $limitations = @(
        'Generated code requires manual review.',
        'Reflection requires manual review.',
        'Package transitivity requires manual review.',
        'Ambiguous interop requires manual review.',
        'Raw or lexically ambiguous source requires manual review.',
        'Extensionless binary files require manual review.'
    )
    $violations = [Collections.Generic.List[object]]::new()
    $warnings = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    function Add-Finding {
        param([Collections.Generic.List[object]] $Target, [string] $Rule, [string] $Path, [int] $Line, [string] $Message)
        $key = "$Rule|$Path|$Line"
        if ($seen.Add($key)) {
            $Target.Add([ordered]@{ rule = $Rule; path = $Path; line = $Line; message = $Message })
        }
    }

    function Inspect-AddedLine {
        param([string] $Path, [int] $Line, [string] $Text, [ref] $LexicalState, [switch] $StateOnly)

        $extension = [IO.Path]::GetExtension($Path)
        $scrubbed = switch ($extension.ToLowerInvariant()) {
            '.fs' { Get-FSharpCode -Line $Text -State $LexicalState; break }
            '.vb' { Get-VisualBasicCode -Line $Text -State $LexicalState; break }
            default { Get-CSharpCode -Line $Text -State $LexicalState }
        }
        $code = $scrubbed.code
        if ($StateOnly) { return }
        if ($scrubbed.ambiguous) {
            Add-Finding -Target $warnings -Rule 'lexical-review' -Path $Path -Line $Line -Message 'Raw or lexically ambiguous source requires manual review; this guard did not interpret it.'
        }
        if ($code -match '(?i)\b(unsafe|AllowUnsafeBlocks)\b') {
            Add-Finding -Target $violations -Rule 'unsafe-code' -Path $Path -Line $Line -Message 'Unsafe code is outside the managed product-code boundary.'
        }
        if ($code -match '(?i)\bSystem\.Runtime\.Intrinsics\b') {
            Add-Finding -Target $violations -Rule 'runtime-intrinsics' -Path $Path -Line $Line -Message 'Runtime intrinsics are outside the managed product-code boundary.'
        }
        if ($code -match '(?i)\b(DllImport|LibraryImport|NativeLibrary|PInvoke)\b' -or $code -match '(?i)\bDeclare\b.*\bLib\b') {
            Add-Finding -Target $violations -Rule 'native-interop' -Path $Path -Line $Line -Message 'Native interop is outside the managed product-code boundary.'
        }
        if ($code -match '(?i)<\s*(PackageReference|PackageVersion|PackageDownload)\b') {
            Add-Finding -Target $warnings -Rule 'dependency-change' -Path $Path -Line $Line -Message 'Added package dependency requires manual confirmation of its managed boundary and transitive dependencies.'
        }
        if ($code -match '(?i)<\s*ProjectReference\b') {
            Add-Finding -Target $warnings -Rule 'project-dependency' -Path $Path -Line $Line -Message 'Added project dependency requires manual confirmation of its managed boundary.'
        }
        if ($code -match '(?i)\b(System\.Reflection|Type\.GetType|Activator\.CreateInstance)\b') {
            Add-Finding -Target $warnings -Rule 'reflection-review' -Path $Path -Line $Line -Message 'Reflection can obscure interop and requires manual review.'
        }
        if ($Path -match '(?i)(^|/)obj/|\.(?:g|generated)\.(?:cs|fs|vb)$' -or $code -match '(?i)\bGeneratedCode\b') {
            Add-Finding -Target $warnings -Rule 'generated-code-review' -Path $Path -Line $Line -Message 'Generated code requires manual review; this guard does not establish its managed safety.'
        }
    }

    $nameStatus = Invoke-GitReadOnly -Repository $repository -GitArguments (@('diff', '--no-ext-diff', '--name-status', $baseCommit, '--') + $pathspec)
    foreach ($entry in $nameStatus) {
        $parts = $entry -split "`t"
        $status = $parts[0]
        $path = $parts[$parts.Count - 1]
        if ($status -like 'A*' -and $path -match '(?i)\.(dll|so|dylib|a|lib|exe)$') {
            Add-Finding -Target $violations -Rule 'native-binary' -Path $path -Line 0 -Message 'Added native binary or executable is outside the managed product-code boundary.'
        }
    }

    $untracked = Invoke-GitReadOnly -Repository $repository -GitArguments (@('ls-files', '--others', '--exclude-standard', '--') + $pathspec)
    foreach ($path in $untracked) {
        if ($path -match '(?i)\.(dll|so|dylib|a|lib|exe)$') {
            Add-Finding -Target $violations -Rule 'native-binary' -Path $path -Line 0 -Message 'Untracked native binary or executable is outside the managed product-code boundary.'
            continue
        }
        if ($path -notmatch '(?i)\.(cs|fs|vb|csproj|fsproj|vbproj|props|targets)$') { continue }
        $fullPath = Join-Path $repository ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $lexicalState = 'code'
        $lineNumber = 1
        foreach ($text in [IO.File]::ReadLines($fullPath)) {
            Inspect-AddedLine -Path $path -Line $lineNumber -Text $text -LexicalState ([ref]$lexicalState)
            $lineNumber++
        }
    }

    $diff = Invoke-GitReadOnly -Repository $repository -GitArguments (@('diff', '--no-ext-diff', '--unified=0', $baseCommit, '--') + $pathspec)
    $currentPath = $null
    $nextLine = 0
    $lexicalState = 'code'
    $sourceLines = @()
    $scannedThrough = 0
    foreach ($entry in $diff) {
        if ($entry -match '^\+\+\+ b/(.+)$') {
            $candidatePath = $Matches[1]
            $currentPath = if ($candidatePath -match '(?i)\.(?:cs|fs|vb|csproj|fsproj|vbproj|props|targets)$') { $candidatePath } else { $null }
            $lexicalState = 'code'
            $sourceLines = if ($null -ne $currentPath) { [IO.File]::ReadAllLines((Join-Path $repository $currentPath)) } else { @() }
            $scannedThrough = 0
            continue
        }
        if ($entry -match '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@') {
            $nextLine = [int]$Matches[1]
            while ($null -ne $currentPath -and $scannedThrough -lt $nextLine - 1) {
                Inspect-AddedLine -Path $currentPath -Line ($scannedThrough + 1) -Text $sourceLines[$scannedThrough] -LexicalState ([ref]$lexicalState) -StateOnly
                $scannedThrough++
            }
            continue
        }
        if ($entry.StartsWith('+') -and -not $entry.StartsWith('+++') -and $null -ne $currentPath) {
            Inspect-AddedLine -Path $currentPath -Line $nextLine -Text $entry.Substring(1) -LexicalState ([ref]$lexicalState)
            $scannedThrough = $nextLine
            $nextLine++
        }
    }

    $result = [ordered]@{
        passed = $violations.Count -eq 0
        violations = @($violations)
        warnings = @($warnings)
        warningDispositionRequired = $warnings.Count -gt 0
        reviewedRange = "$baseCommit..working-tree"
        manualReviewLimitations = $limitations
    }
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 5 -Compress))
    exit 0
}
catch {
    [Console]::Error.WriteLine("Managed product boundary invocation error: $($_.Exception.Message)")
    exit 2
}
