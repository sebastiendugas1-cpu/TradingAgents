$ErrorActionPreference = "Stop"
Write-Host "=== SLICE 21B ADD PRIVATE REQUEST SIGNER SHELL TEST TO SAFETY REGRESSION SUITE ==="

$runnerPath = ".\scripts\run_execution_safety_regression_suite.py"
$testPath = ".\scripts\test_execution_safety_regression_suite_runner.py"

if (-not (Test-Path ".\tradingagents")) { throw "Run this script from the TradingAgents project root." }
if (-not (Test-Path $runnerPath)) { throw "Missing runner file: $runnerPath" }
if (-not (Test-Path $testPath)) { throw "Missing test file: $testPath" }
if (-not (Test-Path ".\scripts\test_kraken_private_request_signer_shell.py")) { throw "Missing Slice 21A signer test." }

$runner = Get-Content $runnerPath -Raw
if ($runner -notlike "*scripts/test_kraken_private_request_signer_shell.py*") {
  $needle = '    "scripts/test_kraken_private_client_transport_integration.py",'
  if ($runner -notlike "*$needle*") { throw "Missing insertion point in runner." }
  $runner = $runner.Replace($needle, $needle + "`r`n" + '    "scripts/test_kraken_private_request_signer_shell.py",')
  Set-Content -Path $runnerPath -Value $runner -Encoding UTF8
  Write-Host "[UPDATED] $runnerPath"
} else {
  Write-Host "[SKIPPED] $runnerPath already includes signer test"
}

$test = Get-Content $testPath -Raw
$test = $test.Replace('    assert len(DEFAULT_SAFETY_TESTS) >= 24', '    assert len(DEFAULT_SAFETY_TESTS) >= 25')

if ($test -notlike "*test_default_safety_tests_include_private_request_signer_shell_test*") {
  $marker = 'def test_regression_suite_runs_subset_successfully() -> None:'
  if ($test -notlike "*$marker*") { throw "Missing regression subset marker." }

  $functionLines = @(
    'def test_default_safety_tests_include_private_request_signer_shell_test() -> None:',
    '    assert "scripts/test_kraken_private_request_signer_shell.py" in DEFAULT_SAFETY_TESTS',
    '',
    '    print("[OK] default safety tests include private request signer shell test")',
    '',
    ''
  )
  $functionBlock = $functionLines -join "`r`n"
  $test = $test.Replace($marker, $functionBlock + $marker)

  $callNeedle = '    test_default_safety_tests_include_private_client_transport_integration_test()'
  if ($test -notlike "*$callNeedle*") { throw "Missing private client transport validation call." }
  $test = $test.Replace($callNeedle, $callNeedle + "`r`n" + '    test_default_safety_tests_include_private_request_signer_shell_test()')

  Write-Host "[UPDATED] $testPath"
} else {
  Write-Host "[SKIPPED] $testPath already includes signer assertion"
}

Set-Content -Path $testPath -Value $test -Encoding UTF8

$roadmapPath = ".\docs\03_ROADMAP.md"
$controlsPath = ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md"
$decisionPath = ".\docs\11_DECISION_LOG.md"

$roadmapMarker = "Slice 21B - Add Disabled Kraken Private Request Signer Shell Test to Master Safety Regression Suite"
$controlsMarker = "Slice 21B - Disabled Private Request Signer Shell Test Added to Safety Regression Suite"
$decisionMarker = "Slice 21B Decision - Protect Disabled Private Request Signer Shell in Master Regression Suite"

$roadmap = Get-Content $roadmapPath -Raw
if ($roadmap -notlike "*$roadmapMarker*") {
  Add-Content -Path $roadmapPath -Encoding UTF8 -Value @"

## $roadmapMarker

Status: Implemented pending validation.

Goal:
Protect the Slice 21A disabled Kraken private request signer shell with the master safety regression suite.

Safety:
- No API secret usage.
- No environment secret reading.
- No nonce generation.
- No signature generation.
- No HMAC or digest signing implementation.
- No network call.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@
  Write-Host "[UPDATED] $roadmapPath"
} else {
  Write-Host "[SKIPPED] $roadmapPath already contains Slice 21B"
}

$controls = Get-Content $controlsPath -Raw
if ($controls -notlike "*$controlsMarker*") {
  Add-Content -Path $controlsPath -Encoding UTF8 -Value @"

## $controlsMarker

The master execution safety regression suite now includes disabled Kraken private request signer shell validation.

This protects the signer boundary and confirms no secret, nonce, signature, network, or private endpoint behavior has been introduced.
"@
  Write-Host "[UPDATED] $controlsPath"
} else {
  Write-Host "[SKIPPED] $controlsPath already contains Slice 21B"
}

$decision = Get-Content $decisionPath -Raw
if ($decision -notlike "*$decisionMarker*") {
  Add-Content -Path $decisionPath -Encoding UTF8 -Value @"

## $decisionMarker

Decision:
Add the disabled Kraken private request signer shell test to the master safety regression suite.

Reason:
Slice 21A created the signer boundary. That boundary must be protected before future request signing or private transport work continues.

Result:
The project now verifies the disabled private request signer shell during full safety regression.
"@
  Write-Host "[UPDATED] $decisionPath"
} else {
  Write-Host "[SKIPPED] $decisionPath already contains Slice 21B"
}

python -m py_compile $runnerPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 21B FILES ==="
Get-Item $runnerPath, $testPath, $roadmapPath, $controlsPath, $decisionPath | Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 21B script completed."
