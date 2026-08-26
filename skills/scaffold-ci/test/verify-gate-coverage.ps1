$ErrorActionPreference = 'Stop'

$script = Resolve-Path (Join-Path $PSScriptRoot '..' 'assets' 'assert_gate_coverage.py')
$root = Join-Path ([IO.Path]::GetTempPath()) ('gate-coverage-' + [guid]::NewGuid().ToString('N'))
$oldExempt = $env:GATE_EXEMPT
$oldConditionalExempt = $env:GATE_CONDITIONAL_EXEMPT
$env:GATE_EXEMPT = ''
$env:GATE_CONDITIONAL_EXEMPT = ''

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
    if: always()
    needs: [build, lint]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($flow.Code -ne 0) { throw "flow needs should pass without site packages:`n$($flow.Output)" }

    $block = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs:
      - build
      - lint
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($block.Code -ne 0) { throw "block needs should pass without site packages:`n$($block.Output)" }

    $missing = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs: build
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
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
    if: always()
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
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
    if: always()
    needs: ['build', "security-scan"]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
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
    if: always()
    needs:
    - build
    - lint
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($fourSpaceSeq.Code -ne 0) { throw "a 4-space block sequence is valid YAML and must pass:`n$($fourSpaceSeq.Output)" }

    $commentedSeq = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs:
      - build
    # lint is the slow one
      - lint
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($commentedSeq.Code -ne 0) { throw "a comment inside the needs sequence must not truncate it:`n$($commentedSeq.Output)" }

    $quotedSeqItems = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs:
      - "build"
      - 'lint'
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($quotedSeqItems.Code -ne 0) { throw "quoted block sequence items must be read:`n$($quotedSeqItems.Output)" }

    $commentedJobsKey = Invoke-Gate @'
jobs: # every job in this workflow
  build:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($commentedJobsKey.Code -ne 0) { throw "a trailing comment on 'jobs:' must not hide every job:`n$($commentedJobsKey.Output)" }

    # --- The parser must refuse to report coverage it cannot verify.
    $unparsable = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  <<: *shared
  ci-gate:
    if: always()
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($unparsable.Code -eq 0 -or $unparsable.Output -notmatch 'unparsable line at job indentation') {
        throw "an unclassifiable line at job indentation must fail closed:`n$($unparsable.Output)"
    }

    # --- A conditional job feeding the gate reports green while checking nothing,
    #     because the gate counts `skipped` as a pass.
    $conditionalFeeder = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  secrets:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs: [build, secrets]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($conditionalFeeder.Code -eq 0 -or $conditionalFeeder.Output -notmatch "job-level 'if:' on job\(s\) feeding 'ci-gate': secrets") {
        throw "a conditional job feeding the gate must fail:`n$($conditionalFeeder.Output)"
    }

    $env:GATE_CONDITIONAL_EXEMPT = 'secrets'
    $conditionalExempted = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  secrets:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs: [build, secrets]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    $env:GATE_CONDITIONAL_EXEMPT = ''
    if ($conditionalExempted.Code -ne 0) {
        throw "a named GATE_CONDITIONAL_EXEMPT job must pass:`n$($conditionalExempted.Output)"
    }

    # --- The gate's OWN semantics. Both of these keep the job, its name and its needs:
    #     list intact, so neither is visible as a coverage change in a diff -- and both
    #     leave the required context reporting green while deciding nothing.
    $noAlways = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  ci-gate:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($noAlways.Code -eq 0 -or $noAlways.Output -notmatch "must carry ``if: always\(\)`` -- found no job-level 'if:'") {
        throw "a gate without always() must fail: it is skipped exactly when it was needed:`n$($noAlways.Output)"
    }

    $narrowedCondition = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  ci-gate:
    if: always() && github.event_name == 'push'
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($narrowedCondition.Code -eq 0 -or $narrowedCondition.Output -notmatch 'must carry') {
        throw "a compound gate condition must fail -- a gate that runs only sometimes is the defect:`n$($narrowedCondition.Output)"
    }

    $noAggregation = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - run: echo "all good"
'@
    if ($noAggregation.Code -eq 0 -or $noAggregation.Output -notmatch 'has no step conditioned on a') {
        throw "a gate that aggregates nothing must fail:`n$($noAggregation.Output)"
    }

    # A comment naming the expression must not satisfy the aggregation check.
    $commentedAggregation = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  ci-gate:
    if: always()
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      # this used to check needs.*.result
      - run: echo "all good"
'@
    if ($commentedAggregation.Code -eq 0 -or $commentedAggregation.Output -notmatch 'has no step conditioned on a') {
        throw "a commented-out aggregation must not count as aggregation:`n$($commentedAggregation.Output)"
    }

    # Three valid spellings of the same condition, and per-job result references.
    $spellings = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  ci-gate:
    if: ${{ always() }}
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: needs.build.result != 'success'
        run: exit 1
'@
    if ($spellings.Code -ne 0) {
        throw "`${{ always() }}` and a per-job result reference are both valid and must pass:`n$($spellings.Output)"
    }

    $quotedAlways = Invoke-Gate @'
jobs:
  build:
    runs-on: ubuntu-latest
  ci-gate:
    'if': "always()"
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - if: contains(needs.*.result, 'failure')
        run: exit 1
'@
    if ($quotedAlways.Code -ne 0) {
        throw "a quoted 'if' key and quoted always() value must pass:`n$($quotedAlways.Output)"
    }

    'assert_gate_coverage.py OK - quoted keys, sequence forms, fail-closed parsing, conditional feeders, and the gate''s own always()/aggregation semantics'
}
finally {
    $env:GATE_EXEMPT = $oldExempt
    $env:GATE_CONDITIONAL_EXEMPT = $oldConditionalExempt
    if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The fail-closed python child above is asserted, not fatal — clear its native status so
# a caller that checks $LASTEXITCODE after a PASS does not read the child's failure.
$global:LASTEXITCODE = 0
