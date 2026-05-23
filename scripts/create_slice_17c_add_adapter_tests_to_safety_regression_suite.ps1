$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 17C ADD ADAPTER TESTS TO SAFETY REGRESSION SUITE ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

$runnerPath = ".\scripts\run_execution_safety_regression_suite.py"
$testPath = ".\scripts\test_execution_safety_regression_suite_runner.py"

if (-not (Test-Path $runnerPath)) {
    throw "Missing runner file: $runnerPath"
}

if (-not (Test-Path $testPath)) {
    throw "Missing test file: $testPath"
}

$runner = Get-Content $runnerPath -Raw

if ($runner -notlike "*scripts/test_execution_adapter_interface.py*") {
    $runner = $runner.Replace(
'    "scripts/test_manual_execution_pipeline_regression.py",
)',
'    "scripts/test_manual_execution_pipeline_regression.py",
    "scripts/test_execution_adapter_interface.py",
    "scripts/test_execution_adapter_command_integration.py",
)'
    )
    Set-Content -Path $runnerPath -Value $runner -Encoding UTF8
    Write-Host "[UPDATED] $runnerPath"
} else {
    Write-Host "[SKIPPED] $runnerPath already includes adapter tests"
}

$test = Get-Content $testPath -Raw

$test = $test.Replace(
'    assert len(DEFAULT_SAFETY_TESTS) >= 10',
'    assert len(DEFAULT_SAFETY_TESTS) >= 15'
)

if ($test -notlike '*test_default_safety_tests_include_adapter_tests*') {
    $insert = @'

def test_default_safety_tests_include_adapter_tests() -> None:
    assert "scripts/test_execution_adapter_interface.py" in DEFAULT_SAFETY_TESTS
    assert "scripts/test_execution_adapter_command_integration.py" in DEFAULT_SAFETY_TESTS

    print("[OK] default safety tests include adapter interface and integration tests")
'@

    $test = $test.Replace(
'

def test_regression_suite_runs_subset_successfully() -> None:',
$insert + '

def test_regression_suite_runs_subset_successfully() -> None:'
    )

    $test = $test.Replace(
'    test_default_safety_tests_exist()
    test_regression_suite_runs_subset_successfully()',
'    test_default_safety_tests_exist()
    test_default_safety_tests_include_adapter_tests()
    test_regression_suite_runs_subset_successfully()'
    )

    Write-Host "[UPDATED] $testPath"
} else {
    Write-Host "[SKIPPED] $testPath already includes adapter test assertion"
}

Set-Content -Path $testPath -Value $test -Encoding UTF8

function Add-DocBlockOnce {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing doc file: $Path"
    }

    $existing = Get-Content $Path -Raw

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`n$Block" -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @"
## Slice 17C — Add Adapter Tests to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the new execution adapter interface and adapter-command integration with the master safety regression suite.

Scope:
- Update `scripts/run_execution_safety_regression_suite.py`.
- Add `scripts/test_execution_adapter_interface.py`.
- Add `scripts/test_execution_adapter_command_integration.py`.
- Update `scripts/test_execution_safety_regression_suite_runner.py`.
- Validate that the master safety suite includes adapter tests.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 17C — Adapter Tests Added to Safety Regression Suite

The master execution safety regression suite now includes:
- execution adapter interface validation
- execution adapter command integration validation

This ensures future safety-suite runs protect the adapter boundary and mock adapter integration.
"@

$decisionBlock = @"
## Slice 17C Decision — Protect Adapter Boundary in Master Regression Suite

Decision:
Add the execution adapter tests to the master safety regression suite.

Reason:
Slices 17A and 17B added execution-adjacent adapter architecture. The master suite must protect these files before future live-adjacent work continues.

Result:
The project now verifies adapter interface and adapter-command integration during full safety regression.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 17C — Add Adapter Tests to Master Safety Regression Suite" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 17C — Adapter Tests Added to Safety Regression Suite" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 17C Decision — Protect Adapter Boundary in Master Regression Suite" -Block $decisionBlock

python -m py_compile $runnerPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 17C FILES ==="
Get-Item `
    ".\scripts\run_execution_safety_regression_suite.py", `
    ".\scripts\test_execution_safety_regression_suite_runner.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 17C script completed."
