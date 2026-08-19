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

# The resolution half needs npm and the live registry. On a host with no npm the static
# assertions above still hold; say what did not run rather than failing the whole suite.
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP: npm not on PATH; package template resolution and tsconfig checks not run'
    return
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Copy-Item -LiteralPath $packagePath -Destination (Join-Path $tempRoot 'package.json')
    $install = & npm install --prefix $tempRoot --package-lock-only --ignore-scripts --no-audit --no-fund 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "package template does not resolve:`n$install" }

    foreach ($config in 'tsconfig.app.json','tsconfig.node.json') {
        $path = Join-Path $templateRoot $config
        # --silent is load-bearing: npm 12 prefixes exec output with "npm notice run npx"
        # and "npm notice run 'tsc' ..." lines, which land in this capture and make the
        # ConvertFrom-Json below fail with "Unexpected character encountered" - a parse
        # error that reads as a broken tsconfig. Observed in node:22 with npm 12 installed.
        $shown = & npm exec --silent --yes --package=typescript@6.0.3 -- tsc --showConfig --project $path 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "tsc --showConfig failed for $config`n$shown" }
        $resolved = $shown | ConvertFrom-Json
        if ($resolved.compilerOptions.strict -ne $true) { throw "$config does not resolve strict=true" }
    }

    'scaffold-frontend template contract OK'
}
finally {
    if ($tempRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
