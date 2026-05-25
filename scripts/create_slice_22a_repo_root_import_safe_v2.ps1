Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-CheckedPython {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $Arguments
  )

  & python @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Python command failed with exit code ${LASTEXITCODE}: python $($Arguments -join ' ')"
  }
}

Write-Host "Slice 22A - Make Execution Safety Scripts Repo-Root Import Safe"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
  "scripts/run_execution_safety_regression_suite.py",
  "scripts/test_execution_safety_regression_suite_runner.py",
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

RUNNER = Path("scripts/run_execution_safety_regression_suite.py")
RUNNER_TEST = Path("scripts/test_execution_safety_regression_suite_runner.py")
DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")

IMPORT_SAFE_BLOCK_LINES = [
    "# Ensure this script can import the local package when it is run directly from",
    "# the repository root or through a subprocess without PYTHONPATH preconfigured.",
    "from pathlib import Path",
    "import sys",
    "",
    "REPO_ROOT = Path(__file__).resolve().parents[1]",
    "if str(REPO_ROOT) not in sys.path:",
    "    sys.path.insert(0, str(REPO_ROOT))",
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def add_import_safe_block(path: Path) -> None:
    text = read(path)

    if "REPO_ROOT = Path(__file__).resolve().parents[1]" in text and "sys.path.insert(0, str(REPO_ROOT))" in text:
        return

    lines = text.splitlines()
    insert_at = 0

    if lines and lines[0].startswith("#!"):
        insert_at = 1

    while insert_at < len(lines):
        stripped = lines[insert_at].strip()
        if stripped == "" or stripped.startswith("#"):
            insert_at += 1
            continue
        break

    if insert_at < len(lines) and lines[insert_at].startswith('"""'):
        insert_at += 1
        while insert_at < len(lines) and '"""' not in lines[insert_at]:
            insert_at += 1
        if insert_at < len(lines):
            insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    updated_lines = lines[:insert_at] + IMPORT_SAFE_BLOCK_LINES + [""] + lines[insert_at:]
    write(path, "\n".join(updated_lines) + "\n")


def append_once(path: Path, marker: str, block: str) -> None:
    text = read(path)
    if marker in text:
        return

    if text and not text.endswith("\n"):
        text += "\n"

    text += "\n" + block.strip() + "\n"
    write(path, text)


add_import_safe_block(RUNNER)
add_import_safe_block(RUNNER_TEST)

append_once(
    DOC_ROADMAP,
    "Slice 22A - Make Execution Safety Scripts Repo-Root Import Safe",
    """
### Slice 22A - Make Execution Safety Scripts Repo-Root Import Safe

Validated target:
- Make the master execution safety regression runner repo-root import safe.
- Make the regression runner validation test repo-root import safe.
- Reduce dependence on manually setting `PYTHONPATH` before validation.
- Preserve the current 26-test master safety suite.

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
    "Slice 22A control - repo-root import safety for execution validation",
    """
### Slice 22A control - repo-root import safety for execution validation

The execution safety regression runner and its runner validation test now add the repository root to `sys.path` when run directly. This keeps validation stable when subprocesses are launched without `PYTHONPATH` preconfigured.

This slice is workflow hardening only. It does not activate private execution, does not create signatures, does not read secrets, does not generate nonces, and does not introduce private endpoint or network calls.
"""
)

append_once(
    DOC_DECISIONS,
    "Slice 22A decision - make safety validation independent from manual PYTHONPATH setup",
    """
### Slice 22A decision - make safety validation independent from manual PYTHONPATH setup

Decision:
- Make the execution safety regression runner and its validation test insert the repository root into `sys.path`.

Reason:
- Slice 21D initially failed validation when `PYTHONPATH` was not set, even though the code changes were valid.
- Safety validation should be reliable from the documented repo-root workflow without depending on temporary shell state.

Expected result:
- Master safety suite remains at 26 tests.
- All 26 tests remain passing.
- Safety guards continue to confirm that no private execution endpoint call or account-changing permission requirement was introduced.
"""
)

print("[PASS] Slice 22A patch applied.")
print("[PASS] Regression runner is repo-root import safe.")
print("[PASS] Regression runner validation test is repo-root import safe.")
print("[PASS] Roadmap, controls, and decision log updated.")
'@

$TempPatch = Join-Path $env:TEMP "apply_slice_22a_patch.py"
Set-Content -LiteralPath $TempPatch -Value $PythonPatch -Encoding UTF8

try {
  Invoke-CheckedPython -Arguments @($TempPatch)
}
finally {
  if (Test-Path -LiteralPath $TempPatch) {
    Remove-Item -LiteralPath $TempPatch -Force
  }
}

Write-Host ""
Write-Host "Running Slice 22A validation without manually setting PYTHONPATH..."
if (Test-Path Env:PYTHONPATH) {
  Remove-Item Env:PYTHONPATH
}

Invoke-CheckedPython -Arguments @(".\scripts\test_execution_safety_regression_suite_runner.py")
Invoke-CheckedPython -Arguments @(".\scripts\run_execution_safety_regression_suite.py")

Write-Host ""
Write-Host "Checking working tree..."
git status --short
if ($LASTEXITCODE -ne 0) {
  throw "git status failed with exit code ${LASTEXITCODE}"
}

Write-Host ""
Write-Host "[PASS] Slice 22A creation and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Make execution safety scripts repo-root import safe"
Read-Host "Press Enter to close..."
