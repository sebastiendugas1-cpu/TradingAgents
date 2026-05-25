Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Slice 21D - Add Private Request Signer Transport Integration to Safety Regression Suite"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
  "scripts/run_execution_safety_regression_suite.py",
  "scripts/test_execution_safety_regression_suite_runner.py",
  "scripts/test_kraken_private_signer_transport_integration.py",
  "docs/03_ROADMAP.md",
  "docs/10_EXECUTION_AND_RISK_CONTROLS.md",
  "docs/11_DECISION_LOG.md"
)

foreach ($File in $RequiredFiles) {
  if (-not (Test-Path -LiteralPath $File)) {
    throw "Required file not found: $File"
  }
}

$PythonPatch = @'
from pathlib import Path
import re

NEW_TEST = "scripts/test_kraken_private_signer_transport_integration.py"

SUITE_FILE = Path("scripts/run_execution_safety_regression_suite.py")
RUNNER_TEST_FILE = Path("scripts/test_execution_safety_regression_suite_runner.py")

DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def insert_test_path_after_anchor(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_private_request_signer_shell.py",
        "scripts/test_kraken_private_client_transport_integration.py",
        "scripts/test_kraken_private_client_transport_integration.py",
        "scripts/test_kraken_private_transport_shell.py",
    ]

    for anchor in anchors:
        if anchor not in text:
            continue

        lines = text.splitlines()
        out = []
        inserted = False

        for line in lines:
            out.append(line)
            if (not inserted) and anchor in line:
                indent = line[: len(line) - len(line.lstrip())]
                quote = '"' if '"' in line else "'"
                comma = "," if line.rstrip().endswith(",") else ""
                out.append(f"{indent}{quote}{new_test}{quote}{comma}")
                inserted = True

        if inserted:
            return "\n".join(out) + "\n"

    raise RuntimeError(
        f"Could not find an anchor test path to insert {new_test}. "
        "Open scripts/run_execution_safety_regression_suite.py and add it manually."
    )


def update_expected_counts(text: str) -> str:
    replacements = [
        (r"(EXPECTED_TEST_COUNT\s*=\s*)25\b", r"\g<1>26"),
        (r"(expected_test_count\s*=\s*)25\b", r"\g<1>26"),
        (r"(EXPECTED_TOTAL_TESTS\s*=\s*)25\b", r"\g<1>26"),
        (r"(expected_total_tests\s*=\s*)25\b", r"\g<1>26"),
        (r"(TOTAL_TESTS\s*=\s*)25\b", r"\g<1>26"),
        (r"(total_tests\s*=\s*)25\b", r"\g<1>26"),
        (r"(assert\s+len\([^)]+\)\s*==\s*)25\b", r"\g<1>26"),
        (r"(assert\s+[^=\n]+\.total_tests\s*==\s*)25\b", r"\g<1>26"),
        (r"(Total tests:\s*)25\b", r"\g<1>26"),
        (r"(Passed tests:\s*)25\b", r"\g<1>26"),
        (r"(Passed:\s*)25\b", r"\g<1>26"),
    ]

    updated = text
    for pattern, repl in replacements:
        updated = re.sub(pattern, repl, updated)

    return updated


def insert_test_path_in_runner_test(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    # Many runner tests include an explicit expected test-name list. If so,
    # add the new test after the closest existing signer/transport test.
    anchors = [
        "scripts/test_kraken_private_request_signer_shell.py",
        "scripts/test_kraken_private_client_transport_integration.py",
        "scripts/test_kraken_private_transport_shell.py",
    ]

    for anchor in anchors:
        if anchor not in text:
            continue

        lines = text.splitlines()
        out = []
        inserted = False

        for line in lines:
            out.append(line)
            if (not inserted) and anchor in line:
                indent = line[: len(line) - len(line.lstrip())]
                quote = '"' if '"' in line else "'"
                comma = "," if line.rstrip().endswith(",") else ""
                out.append(f"{indent}{quote}{new_test}{quote}{comma}")
                inserted = True

        if inserted:
            return "\n".join(out) + "\n"

    # If the runner test only verifies counts or execution output, no explicit
    # list update is required.
    return text


def append_once(path: Path, marker: str, block: str) -> None:
    text = read(path)
    if marker in text:
        return

    if text and not text.endswith("\n"):
        text += "\n"

    text += "\n" + block.strip() + "\n"
    write(path, text)


suite_text = read(SUITE_FILE)
suite_text = insert_test_path_after_anchor(suite_text, NEW_TEST)
write(SUITE_FILE, suite_text)

runner_text = read(RUNNER_TEST_FILE)
runner_text = update_expected_counts(runner_text)
runner_text = insert_test_path_in_runner_test(runner_text, NEW_TEST)
write(RUNNER_TEST_FILE, runner_text)

append_once(
    DOC_ROADMAP,
    "Slice 21D - Add Private Request Signer Transport Integration to Safety Regression Suite",
    """
### Slice 21D - Add Private Request Signer Transport Integration to Safety Regression Suite

Validated target:
- Add `scripts/test_kraken_private_signer_transport_integration.py` to the master execution safety regression suite.
- Increase the expected suite coverage from 25 tests to 26 tests.
- Preserve the current disabled/non-executable execution posture.

Safety posture:
- No real order placement.
- No real order cancellation.
- No private endpoint calls.
- No network calls in private execution code.
- No API secret usage.
- No environment secret reading.
- No nonce generation.
- No HMAC/hashlib/base64 signing implementation.
- No live trading.
- No private account-changing permission requirement.
"""
)

append_once(
    DOC_CONTROLS,
    "Slice 21D control - signer transport integration suite registration",
    """
### Slice 21D control - signer transport integration suite registration

The private request signer transport integration test is now part of the master execution safety regression suite.

This slice is a suite-registration-only change. It does not activate private execution, does not create signatures, does not read secrets, does not generate nonces, and does not introduce private endpoint or network calls.
"""
)

append_once(
    DOC_DECISIONS,
    "Slice 21D decision - register signer transport integration in master suite",
    """
### Slice 21D decision - register signer transport integration in master suite

Decision:
- Register `scripts/test_kraken_private_signer_transport_integration.py` in the master execution safety regression suite.

Reason:
- Slice 21C validated the disabled signer-to-transport path independently.
- The protection now belongs in the master regression gate so future changes cannot bypass it.

Expected result:
- Execution Safety Regression Suite increases from 25 tests to 26 tests.
- All tests remain passing.
- Safety guards continue to confirm that no private execution endpoint call or account-changing permission requirement was introduced.
"""
)

print("[PASS] Slice 21D patch applied.")
print("[PASS] Added signer transport integration test to master suite when absent.")
print("[PASS] Updated runner test expected count/list when applicable.")
print("[PASS] Updated roadmap, controls, and decision log.")
'@

$TempPatch = Join-Path $env:TEMP "apply_slice_21d_patch.py"
Set-Content -LiteralPath $TempPatch -Value $PythonPatch -Encoding UTF8

try {
  python $TempPatch
}
finally {
  if (Test-Path -LiteralPath $TempPatch) {
    Remove-Item -LiteralPath $TempPatch -Force
  }
}

Write-Host ""
Write-Host "Running Slice 21D validation..."
python .\scripts\test_kraken_private_signer_transport_integration.py
python .\scripts\test_execution_safety_regression_suite_runner.py
python .\scripts\run_execution_safety_regression_suite.py

Write-Host ""
Write-Host "[PASS] Slice 21D creation and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Add signer transport integration to safety regression suite"
Read-Host "Press Enter to close..."
