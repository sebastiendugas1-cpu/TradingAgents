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

Write-Host "Slice 22E - Add Execution Safety State Checkpoint"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
  "scripts/run_execution_safety_regression_suite.py",
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

DOC_CHECKPOINT = Path("docs/12_EXECUTION_SAFETY_STATE_CHECKPOINT.md")
DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")

CHECKPOINT_BLOCK = "\n### Slice 22E - Execution Safety State Checkpoint\n\nCheckpoint after Slice 22D:\n\n- Latest validated commit: `cee8ba6 Expose disabled signing material in payload review CLI`\n- Master execution safety regression suite: 29 tests passing / 0 failing\n- Current execution mode: disabled private execution; manual review plumbing only\n- Signing state: data-only review plumbing exists; no signing implementation exists\n- Payload review CLI: exposes disabled signing-material review state\n- Private signer shell: still disabled and non-executable\n- Private transport shell: still disabled and non-networking\n- Private client shell: still disabled and non-executable\n\nSafety invariants preserved:\n\n- No real order placement\n- No real order cancellation\n- No private endpoint calls\n- No network calls in private execution code\n- No API secret usage\n- No environment secret reading\n- No nonce generation\n- No HMAC/hashlib/base64 signing implementation\n- No live trading\n- No private account-changing permission requirement\n\nRecommended next technical step:\n\n- Continue with a small disabled review-plumbing slice only, or pause to update the higher-level source-of-truth architecture document before introducing any additional signing-related structure.\n"
ROADMAP_BLOCK = "\n### Slice 22E - Add Execution Safety State Checkpoint\n\nValidated target:\n- Add an explicit documentation checkpoint after Slice 22D.\n- Record the latest validated commit and safety-suite state.\n- Preserve current disabled/non-executable private execution posture.\n- Keep master safety suite coverage at 29 tests.\n\nSafety posture:\n- No real order placement.\n- No real order cancellation.\n- No private endpoint calls.\n- No network calls in private execution code.\n- No API secret usage.\n- No environment secret reading.\n- No nonce generation.\n- No HMAC/hashlib/base64 signing implementation.\n- No live trading.\n- No private account-changing permission requirement.\n"
CONTROLS_BLOCK = "\n### Slice 22E control - execution safety checkpoint\n\nThe execution safety state is now explicitly recorded after Slice 22D. The project remains in disabled/private-execution-blocked mode with data-only signing review plumbing.\n\nThis slice is documentation-only. It does not activate private execution, does not read API secrets, does not read environment secrets, does not generate nonces, does not generate signatures, and does not introduce private endpoint or network calls.\n"
DECISIONS_BLOCK = "\n### Slice 22E decision - checkpoint execution safety state before further signing work\n\nDecision:\n- Add a documentation checkpoint before continuing deeper into signing architecture.\n\nReason:\n- The project now has multiple disabled signing review layers.\n- A compact checkpoint reduces drift and makes the current validated state clear before any future technical slice.\n\nExpected result:\n- Master safety suite remains at 29 tests.\n- All 29 tests remain passing.\n- Safety guards continue to confirm that no secret reading, nonce generation, signing implementation, private endpoint call, or account-changing permission requirement was introduced.\n"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\ufeff", "")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\ufeff", ""), encoding="utf-8", newline="\n")


def append_once(path: Path, marker: str, block: str) -> None:
    text = read(path) if path.exists() else ""
    if marker in text:
        return

    if text and not text.endswith("\n"):
        text += "\n"

    text += "\n" + block.strip() + "\n"
    write(path, text)


checkpoint_text = "# Execution Safety State Checkpoint\n\n" + CHECKPOINT_BLOCK.strip() + "\n"
write(DOC_CHECKPOINT, checkpoint_text)

append_once(DOC_ROADMAP, "Slice 22E - Add Execution Safety State Checkpoint", ROADMAP_BLOCK)
append_once(DOC_CONTROLS, "Slice 22E control - execution safety checkpoint", CONTROLS_BLOCK)
append_once(DOC_DECISIONS, "Slice 22E decision - checkpoint execution safety state before further signing work", DECISIONS_BLOCK)

print("[PASS] Slice 22E documentation checkpoint applied.")
print("[PASS] Execution safety state checkpoint document updated.")
print("[PASS] Roadmap, controls, and decision log updated.")

'@

$TempPatch = Join-Path $env:TEMP "apply_slice_22e_checkpoint_patch.py"
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
Write-Host "Running Slice 22E validation..."
Invoke-CheckedPython -Arguments @(".\scripts\run_execution_safety_regression_suite.py")

Write-Host ""
Write-Host "Checking working tree..."
git status --short
if ($LASTEXITCODE -ne 0) {
  throw "git status failed with exit code ${LASTEXITCODE}"
}

Write-Host ""
Write-Host "[PASS] Slice 22E documentation checkpoint and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Add execution safety state checkpoint"
Read-Host "Press Enter to close..."
