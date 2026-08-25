$ErrorActionPreference = 'Stop'

$script = Resolve-Path (Join-Path $PSScriptRoot '..' 'assets' 'assert_gate_coverage.py')
$root = Join-Path ([IO.Path]::GetTempPath()) ('gate-coverage-' + [guid]::NewGuid().ToString('N'))
$oldExempt = $env:GATE_EXEMPT
$env:GATE_EXEMPT = ''

# python3 first: the generated workflows invoke the shipped asset as `python3`, and
# `python` does not exist on a stock ubuntu runner. Bare `& python` made this test
# unrunnable on the very platform the asset ships to.
$python = @('python3', 'python') |
    ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (-not $python) {
    Write-Host 'SKIP: no python3/python on this host; gate-coverage parser not exercised'
    return
}

function Invoke-Gate([string] $yaml) {
    $workflow = Join-Path $root 'ci.yml'
    $output = Join-Path $root 'output.txt'
    $yaml | Set-Content -LiteralPath $workflow -Encoding utf8
    & $python.Source -S $script $workflow *> $output
    [pscustomobject]@{
        Code = $LASTEXITCODE
        Output = Get-Content -LiteralPath $output -Raw
    }
}

try {
    New-Item -ItemType Directory -Path $root | Out-Null

    $flow = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    needs: [build, lint]
    runs-on: ubuntu-latest
'@
    if ($flow.Code -ne 0) { throw "flow needs should pass without site packages:`n$($flow.Output)" }

    $block = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    needs:
      - build
      - lint
    runs-on: ubuntu-latest
'@
    if ($block.Code -ne 0) { throw "block needs should pass without site packages:`n$($block.Output)" }

    $missing = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    needs: build
    runs-on: ubuntu-latest
'@
    if ($missing.Code -eq 0 -or $missing.Output -notmatch "not gated by 'ci-gate': lint") {
        throw "an omitted job must fail clearly:`n$($missing.Output)"
    }

    # --- Fail-open regression: a QUOTED job key is valid Actions syntax. It used to be
    #     invisible to the job scan, so it could never appear in missing-set arithmetic
    #     and the gate printed "all N job(s) accounted for" over an ungated quality job.
    $quotedUngated = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  "security-scan":
    runs-on: ubuntu-latest
  ci-gate:
    needs: [build]
    runs-on: ubuntu-latest
'@
    if ($quotedUngated.Code -eq 0 -or $quotedUngated.Output -notmatch "not gated by 'ci-gate': security-scan") {
        throw "a quoted ungated job must be caught, not silently accounted for:`n$($quotedUngated.Output)"
    }

    $quotedGated = Invoke-Gate @'
jobs:
  'build':
    runs-on: ubuntu-latest
  "security-scan":
    runs-on: ubuntu-latest
  ci-gate:
    needs: ['build', "security-scan"]
    runs-on: ubuntu-latest
'@
    if ($quotedGated.Code -ne 0) { throw "quoted job keys and quoted flow needs must pass:`n$($quotedGated.Output)" }

    # --- Fail-closed regressions: four valid YAML forms that used to misparse into an
    #     empty or short `needs` list, reddening a correct workflow.
    $fourSpaceSeq = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    needs:
    - build
    - lint
    runs-on: ubuntu-latest
'@
    if ($fourSpaceSeq.Code -ne 0) { throw "a 4-space block sequence is valid YAML and must pass:`n$($fourSpaceSeq.Output)" }

    $commentedSeq = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    needs:
      - build
    # lint is the slow one
      - lint
    runs-on: ubuntu-latest
'@
    if ($commentedSeq.Code -ne 0) { throw "a comment inside the needs sequence must not truncate it:`n$($commentedSeq.Output)" }

    $quotedSeqItems = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    needs:
      - "build"
      - 'lint'
    runs-on: ubuntu-latest
'@
    if ($quotedSeqItems.Code -ne 0) { throw "quoted block sequence items must be read:`n$($quotedSeqItems.Output)" }

    $commentedJobsKey = Invoke-Gate @'
jobs: # every job in this workflow
  build:
    runs-on: ubuntu-latest
  ci-gate:
    needs: [build]
    runs-on: ubuntu-latest
'@
    if ($commentedJobsKey.Code -ne 0) { throw "a trailing comment on 'jobs:' must not hide every job:`n$($commentedJobsKey.Output)" }

    # --- The parser must refuse to report coverage it cannot verify.
    $unparsable = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  <<: *shared
  ci-gate:
    needs: [build]
    runs-on: ubuntu-latest
'@
    if ($unparsable.Code -eq 0 -or $unparsable.Output -notmatch 'unparsable line at job indentation') {
        throw "an unclassifiable line at job indentation must fail closed:`n$($unparsable.Output)"
    }

    'assert_gate_coverage.py OK - quoted keys, 4-space and commented sequences, commented jobs key, and fail-closed parsing'
}
finally {
    $env:GATE_EXEMPT = $oldExempt
    if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The fail-closed python child above is asserted, not fatal — clear its native status so
# a caller that checks $LASTEXITCODE after a PASS does not read the child's failure.
$global:LASTEXITCODE = 0
