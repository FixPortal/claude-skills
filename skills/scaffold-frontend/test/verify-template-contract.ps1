$ErrorActionPreference = 'Stop'
$skillRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$templateRoot = Join-Path $skillRoot 'templates'
$packagePath = Join-Path $templateRoot 'package.json'
$package = Get-Content $packagePath -Raw | ConvertFrom-Json
$skill = Get-Content (Join-Path $skillRoot 'SKILL.md') -Raw
$architecture = Get-Content (Join-Path $templateRoot 'src' 'architecture.spec.ts') -Raw
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('frontend-template-' + [guid]::NewGuid().ToString('N'))

foreach ($script in @{ test = 'vitest run'; coverage = 'vitest run --coverage'; build = 'tsc -b && vite build' }.GetEnumerator()) {
    if ($package.scripts.($script.Key) -ne $script.Value) { throw "package template missing $($script.Key) script" }
}
if ($package.engines.node -ne '>=24.15.0 <25') { throw 'package template Node floor drifted' }
foreach ($dependency in 'typescript','typescript-eslint','vitest','@vitest/coverage-v8','jsdom','archunit','@testing-library/react','@testing-library/jest-dom') {
    if (-not $package.devDependencies.PSObject.Properties.Name.Contains($dependency)) { throw "package template missing $dependency" }
}
if ($package.devDependencies.archunit -ne '2.4.0') { throw 'archunit must remain exact' }
if ($package.devDependencies.vitest -ne $package.devDependencies.'@vitest/coverage-v8') { throw 'vitest and @vitest/coverage-v8 must use the same range' }

foreach ($note in '~/.agents/notes/npm-publishing-traps.md','~/.agents/notes/web-ui-traps.md','~/.agents/notes/archunitts-traps.md') {
    if ($skill -notmatch [regex]::Escape($note)) { throw "skill missing canonical note: $note" }
}
if ($architecture -notmatch [regex]::Escape('*.{test,spec,archunit}.*')) { throw 'architecture wrapper is not excluded from its own graph' }
if ($skill -notmatch [regex]::Escape('npm exec --silent --yes --package=typescript@<version> --call "tsc --showConfig --project <config>"')) {
    throw 'skill missing npm 11-compatible TypeScript config verification command'
}

# Test sources must belong to a project: without tsconfig.test.json referenced from the
# root solution file, `tsc -b` type-checks app and node config while Vitest transpiles
# test files with no type-checking - both stay green on a type-broken test.
$rootTsconfig = Get-Content (Join-Path $templateRoot 'tsconfig.json') -Raw | ConvertFrom-Json
if (-not ($rootTsconfig.references.path -contains './tsconfig.test.json')) {
    throw 'tsconfig.json must reference ./tsconfig.test.json so test sources are type-checked'
}
$testTsconfigPath = Join-Path $templateRoot 'tsconfig.test.json'
if (-not (Test-Path $testTsconfigPath)) { throw 'templates/tsconfig.test.json is missing' }

# The resolution half needs npm and the live registry. On a host with no npm the static
# assertions above still hold; say what did not run rather than failing the whole suite.
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: npm not on PATH; package template resolution and tsconfig checks not run'
    return
}

# A registry blip must not fail the required gate on a PR that could not have caused it,
# so npm calls retry with backoff, and a failure whose output is network-shaped means
# "registry unreachable" (SKIP), not "template broken". Anything else - ERESOLVE, a peer
# conflict, a missing version - still throws.
function Test-RegistryUnreachable([string] $Output) {
    return $Output -match '(?i)EAI_AGAIN|ENOTFOUND|ECONNREFUSED|ECONNRESET|ETIMEDOUT|ESOCKETTIMEDOUT|EAI_FAIL|E50[234]|ERR_SOCKET_TIMEOUT|EHOSTUNREACH|ENETUNREACH|fetch failed|network request to .* failed'
}

# Classifier self-test: every transient code npm 12 prints must take the retry/SKIP
# path (E502/E503/E504, ERR_SOCKET_TIMEOUT, EHOSTUNREACH, ENETUNREACH were the misses),
# and a genuine resolution failure must still throw.
foreach ($code in 'EAI_AGAIN','ENOTFOUND','ECONNREFUSED','ECONNRESET','ETIMEDOUT','ESOCKETTIMEDOUT','EAI_FAIL','E502','E503','E504','ERR_SOCKET_TIMEOUT','EHOSTUNREACH','ENETUNREACH') {
    if (-not (Test-RegistryUnreachable "npm error code $code")) { throw "Test-RegistryUnreachable misses transient npm code: $code" }
}
if (Test-RegistryUnreachable 'npm error code ERESOLVE') { throw 'Test-RegistryUnreachable swallows ERESOLVE; resolution failures must throw' }

function Invoke-NpmWithRetry([string] $What, [string[]] $Arguments, [string] $AllowedErrorPattern) {
    # Returns the captured output on success, $null when the registry stayed unreachable
    # through every retry (the caller must SKIP), and throws on any other failure. A
    # failure matching $AllowedErrorPattern is returned as output for the caller to judge.
    $output = ''
    foreach ($attempt in 1..3) {
        $output = & npm @Arguments 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { return $output }
        if ($AllowedErrorPattern -and $output -match $AllowedErrorPattern) { return $output }
        if (-not (Test-RegistryUnreachable $output)) {
            throw "$What failed (exit $LASTEXITCODE):`n$output"
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds ([math]::Pow(2, $attempt)) }
    }
    return $null
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Copy-Item -LiteralPath $packagePath -Destination (Join-Path $tempRoot 'package.json')
    $install = Invoke-NpmWithRetry 'package template resolution' @('install', '--prefix', $tempRoot, '--package-lock-only', '--ignore-scripts', '--no-audit', '--no-fund')
    if ($null -eq $install) {
        Write-Host 'SKIP: npm registry unreachable after retries; package resolution and tsconfig checks not run'
        return
    }

    foreach ($config in 'tsconfig.app.json','tsconfig.node.json','tsconfig.test.json') {
        $path = Join-Path $templateRoot $config
        # --silent is load-bearing: npm 12 prefixes exec output with "npm notice run npx"
        # and "npm notice run 'tsc' ..." lines, which land in this capture and make the
        # ConvertFrom-Json below fail with "Unexpected character encountered" - a parse
        # error that reads as a broken tsconfig. Observed in node:22 with npm 12 installed.
        $shown = Invoke-NpmWithRetry "tsc --showConfig for $config" @('exec', '--silent', '--yes', '--package=typescript@6.0.3', '--', 'tsc', '--showConfig', '--project', $path) 'TS18003'
        if ($null -eq $shown) {
            Write-Host "SKIP: npm registry unreachable after retries; tsconfig checks for $config not run"
            return
        }
        if ($shown -match 'TS18003') {
            # TS18003 "No inputs were found": this mirror's templates/src holds only
            # test-family files (the app project legitimately resolves empty HERE; a
            # scaffolded project has app sources). Fall back to the raw compilerOptions.
            Write-Host "SKIP: $config has no inputs in the bare templates tree; strict asserted from raw JSON"
            $resolved = [pscustomobject]@{ compilerOptions = ((Get-Content $path -Raw) -replace '//.*', '' | ConvertFrom-Json).compilerOptions }
        }
        else { $resolved = $shown | ConvertFrom-Json }
        if ($resolved.compilerOptions.strict -ne $true) { throw "$config does not resolve strict=true" }
    }

    'scaffold-frontend template contract OK'
}
finally {
    if ($tempRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
