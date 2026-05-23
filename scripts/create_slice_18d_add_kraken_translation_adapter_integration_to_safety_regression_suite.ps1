$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 18D ADD KRAKEN TRANSLATION ADAPTER INTEGRATION TEST TO SAFETY REGRESSION SUITE ==="

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

if (-not (Test-Path ".\scripts\test_kraken_order_translation_adapter_integration.py")) {
    throw "Missing Slice 18C Kraken order translation adapter integration test script."
}

$runner = Get-Content $runnerPath -Raw

if ($runner -notlike "*scripts/test_kraken_order_translation_adapter_integration.py*") {
    $runner = $runner.Replace(
'    "scripts/test_kraken_private_order_request_translator.py",
)',
'    "scripts/test_kraken_private_order_request_translator.py",
    "scripts/test_kraken_order_translation_adapter_integration.py",
)'
    )
    Set-Content -Path $runnerPath -Value $runner -Encoding UTF8
    Write-Host "[UPDATED] $runnerPath"
} else {
    Write-Host "[SKIPPED] $runnerPath already includes Kraken translation adapter integration test"
}

$test = Get-Content $testPath -Raw

$test = $test.Replace(
'    assert len(DEFAULT_SAFETY_TESTS) >= 18',
'    assert len(DEFAULT_SAFETY_TESTS) >= 19'
)

if ($test -notlike '*test_default_safety_tests_include_kraken_translation_adapter_integration_test*') {
    $insert = @'

def test_default_safety_tests_include_kraken_translation_adapter_integration_test() -> None:
    assert "scripts/test_kraken_order_translation_adapter_integration.py" in DEFAULT_SAFETY_TESTS

    print("[OK] default safety tests include Kraken translation adapter integration test")
'@

    $test = $test.Replace(
'

def test_regression_suite_runs_subset_successfully() -> None:',
$insert + '

def test_regression_suite_runs_subset_successfully() -> None:'
    )

    $test = $test.Replace(
'    test_default_safety_tests_include_kraken_order_translator_test()
    test_regression_suite_runs_subset_successfully()',
'    test_default_safety_tests_include_kraken_order_translator_test()
    test_default_safety_tests_include_kraken_translation_adapter_integration_test()
    test_regression_suite_runs_subset_successfully()'
    )

    Write-Host "[UPDATED] $testPath"
} else {
    Write-Host "[SKIPPED] $testPath already includes Kraken translation adapter integration assertion"
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
## Slice 18D — Add Kraken Translator Adapter Integration Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 18C Kraken order translator adapter integration with the master safety regression suite.

Scope:
- Update `scripts/run_execution_safety_regression_suite.py`.
- Add `scripts/test_kraken_order_translation_adapter_integration.py` to the default safety suite.
- Update `scripts/test_execution_safety_regression_suite_runner.py`.
- Validate that the master safety suite includes the Kraken translator adapter integration test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 18D — Kraken Translator Adapter Integration Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- Kraken order translator adapter integration validation

This ensures future safety-suite runs protect the validate=true payload translation and disabled adapter routing path.
"@

$decisionBlock = @"
## Slice 18D Decision — Protect Kraken Translator Adapter Integration in Master Regression Suite

Decision:
Add the Kraken order translator adapter integration test to the master safety regression suite.

Reason:
Slice 18C connected the Kraken-style payload translator to the disabled Kraken adapter skeleton. The master suite must protect that integration before future work builds on top of it.

Result:
The project now verifies the Kraken translator adapter integration during full safety regression.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 18D — Add Kraken Translator Adapter Integration Test to Master Safety Regression Suite" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 18D — Kraken Translator Adapter Integration Test Added to Safety Regression Suite" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 18D Decision — Protect Kraken Translator Adapter Integration in Master Regression Suite" -Block $decisionBlock

python -m py_compile $runnerPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 18D FILES ==="
Get-Item `
    ".\scripts\run_execution_safety_regression_suite.py", `
    ".\scripts\test_execution_safety_regression_suite_runner.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 18D script completed."
