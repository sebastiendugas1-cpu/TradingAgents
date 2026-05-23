$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 20B ADD PRIVATE TRANSPORT SHELL TEST TO SAFETY REGRESSION SUITE ==="

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

if (-not (Test-Path ".\scripts\test_kraken_private_transport_shell.py")) {
    throw "Missing Slice 20A private transport shell test script."
}

$runner = Get-Content $runnerPath -Raw

if ($runner -notlike "*scripts/test_kraken_private_transport_shell.py*") {
    $runner = $runner.Replace(
'    "scripts/test_kraken_payload_review_private_client_integration.py",
)',
'    "scripts/test_kraken_payload_review_private_client_integration.py",
    "scripts/test_kraken_private_transport_shell.py",
)'
    )

    if ($runner -notlike "*scripts/test_kraken_private_transport_shell.py*") {
        throw "Failed to insert private transport shell test into DEFAULT_SAFETY_TESTS."
    }

    Set-Content -Path $runnerPath -Value $runner -Encoding UTF8
    Write-Host "[UPDATED] $runnerPath"
} else {
    Write-Host "[SKIPPED] $runnerPath already includes private transport shell test"
}

$test = Get-Content $testPath -Raw

$test = $test.Replace(
'    assert len(DEFAULT_SAFETY_TESTS) >= 22',
'    assert len(DEFAULT_SAFETY_TESTS) >= 23'
)

if ($test -notlike '*test_default_safety_tests_include_private_transport_shell_test*') {
    $insert = @'

def test_default_safety_tests_include_private_transport_shell_test() -> None:
    assert "scripts/test_kraken_private_transport_shell.py" in DEFAULT_SAFETY_TESTS

    print("[OK] default safety tests include private transport shell test")
'@

    $test = $test.Replace(
'

def test_regression_suite_runs_subset_successfully() -> None:',
$insert + '

def test_regression_suite_runs_subset_successfully() -> None:'
    )

    $test = $test.Replace(
'    test_default_safety_tests_include_payload_review_private_client_integration_test()
    test_regression_suite_runs_subset_successfully()',
'    test_default_safety_tests_include_payload_review_private_client_integration_test()
    test_default_safety_tests_include_private_transport_shell_test()
    test_regression_suite_runs_subset_successfully()'
    )

    Write-Host "[UPDATED] $testPath"
} else {
    Write-Host "[SKIPPED] $testPath already includes private transport shell assertion"
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
## Slice 20B — Add Disabled Kraken Private Transport Shell Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 20A disabled Kraken private transport shell with the master safety regression suite.

Scope:
- Update `scripts/run_execution_safety_regression_suite.py`.
- Add `scripts/test_kraken_private_transport_shell.py` to the default safety suite.
- Update `scripts/test_execution_safety_regression_suite_runner.py`.
- Validate that the master suite includes the disabled private transport shell test.

Safety:
- No network call.
- No request signing.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 20B — Disabled Private Transport Shell Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- disabled Kraken private transport shell validation

This ensures future safety-suite runs protect the transport boundary and confirm no network/private endpoint behavior has been introduced.
"@

$decisionBlock = @"
## Slice 20B Decision — Protect Disabled Private Transport Shell in Master Regression Suite

Decision:
Add the disabled Kraken private transport shell test to the master safety regression suite.

Reason:
Slice 20A created the private transport boundary. That boundary must be protected before future transport, signing, or private request work continues.

Result:
The project now verifies the disabled private transport shell during full safety regression.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 20B — Add Disabled Kraken Private Transport Shell Test to Master Safety Regression Suite" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 20B — Disabled Private Transport Shell Test Added to Safety Regression Suite" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 20B Decision — Protect Disabled Private Transport Shell in Master Regression Suite" -Block $decisionBlock

python -m py_compile $runnerPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 20B FILES ==="
Get-Item `
    ".\scripts\run_execution_safety_regression_suite.py", `
    ".\scripts\test_execution_safety_regression_suite_runner.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 20B script completed."
