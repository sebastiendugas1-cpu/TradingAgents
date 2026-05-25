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

Write-Host "Slice 22F - Update High-Level Project Source-of-Truth Architecture Checkpoint"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
  "scripts/run_execution_safety_regression_suite.py",
  "docs/03_ROADMAP.md",
  "docs/10_EXECUTION_AND_RISK_CONTROLS.md",
  "docs/11_DECISION_LOG.md",
  "docs/12_EXECUTION_SAFETY_STATE_CHECKPOINT.md"
)

foreach ($File in $RequiredFiles) {
  if (-not (Test-Path -LiteralPath $File)) {
    throw "Required file not found: $File"
  }
}

$PythonPatch = @'
from pathlib import Path

DOC_ARCH = Path("docs/13_HIGH_LEVEL_PROJECT_ARCHITECTURE_CHECKPOINT.md")
DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")
DOC_SAFETY_CHECKPOINT = Path("docs/12_EXECUTION_SAFETY_STATE_CHECKPOINT.md")

ARCHITECTURE_BLOCK = "\n### Slice 22F - High-Level Project Source-of-Truth Architecture Checkpoint\n\nCheckpoint after Slice 22E:\n\n- Latest validated TradingAgents commit: `68880df Add execution safety state checkpoint`\n- Branch: `crypto-dev`\n- Master execution safety regression suite: 29 tests passing / 0 failing\n- Local repo currently being worked: `D:\\Trading\\TradingAgents`\n- TradingAgents role: research/decision brain template and controlled execution-safety development branch\n- crypto-trading-agent role: Kraken safety/execution/reconciliation shell and broader project source-of-truth repo\n- Current execution state: disabled Kraken private execution review chain only\n- Current signing state: disabled/data-only review plumbing only\n- Payload review CLI: can expose disabled signing-material review state\n- Private signer shell: disabled and non-executable\n- Private transport shell: disabled and non-networking\n- Private client shell: disabled and non-executable\n\nHard safety boundaries still in force:\n\n- Do not introduce real order placement.\n- Do not introduce real order cancellation.\n- Do not introduce private endpoint calls.\n- Do not introduce network calls in private execution code.\n- Do not introduce API secret usage.\n- Do not introduce environment secret reading.\n- Do not introduce nonce generation.\n- Do not introduce HMAC/hashlib/base64 signing implementation.\n- Do not introduce live trading.\n- Do not introduce private account-changing permission requirements.\n\nArchitecture decision preserved:\n\n- TradingAgents is not becoming the unchecked live-trading engine.\n- TradingAgents is being used to develop and test the decision/review/safety chain in isolated, safety-gated slices.\n- The broader `crypto-trading-agent` project remains the intended Kraken safety/execution/reconciliation shell.\n- Before transferring or applying this work to `crypto-trading-agent`, confirm the current source-of-truth file in that repo and reconcile this checkpoint with it.\n\nRecommended next step:\n\n- Either continue with disabled/data-only review plumbing in TradingAgents, or switch to the `crypto-trading-agent` repo and update its high-level source-of-truth architecture document with this validated TradingAgents checkpoint.\n"
ROADMAP_BLOCK = "\n### Slice 22F - Update High-Level Project Source-of-Truth Architecture Checkpoint\n\nValidated target:\n- Add a high-level architecture checkpoint after Slice 22E.\n- Clarify the role split between TradingAgents and crypto-trading-agent.\n- Record the latest validated TradingAgents commit and safety-suite state.\n- Preserve current disabled/non-executable private execution posture.\n- Keep master safety suite coverage at 29 tests.\n\nSafety posture:\n- No real order placement.\n- No real order cancellation.\n- No private endpoint calls.\n- No network calls in private execution code.\n- No API secret usage.\n- No environment secret reading.\n- No nonce generation.\n- No HMAC/hashlib/base64 signing implementation.\n- No live trading.\n- No private account-changing permission requirement.\n"
CONTROLS_BLOCK = "\n### Slice 22F control - high-level architecture checkpoint\n\nThe high-level architecture checkpoint now explicitly records the role split between TradingAgents and crypto-trading-agent, plus the current disabled Kraken private execution review-chain state.\n\nThis slice is documentation-only. It does not activate private execution, does not read API secrets, does not read environment secrets, does not generate nonces, does not generate signatures, and does not introduce private endpoint or network calls.\n"
DECISIONS_BLOCK = "\n### Slice 22F decision - preserve TradingAgents / crypto-trading-agent role split\n\nDecision:\n- Record the current architecture split before continuing deeper into signing-related work.\n\nReason:\n- TradingAgents is currently being used to build a safety-gated review chain.\n- The broader crypto-trading-agent repo remains the intended Kraken safety/execution/reconciliation shell.\n- A clear checkpoint reduces project drift and prevents confusing disabled review plumbing with live execution capability.\n\nExpected result:\n- Master safety suite remains at 29 tests.\n- All 29 tests remain passing.\n- Safety guards continue to confirm that no secret reading, nonce generation, signing implementation, private endpoint call, or account-changing permission requirement was introduced.\n"


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


architecture_text = "# High-Level Project Architecture Checkpoint\n\n" + ARCHITECTURE_BLOCK.strip() + "\n"
write(DOC_ARCH, architecture_text)

append_once(DOC_SAFETY_CHECKPOINT, "Slice 22F - High-Level Project Source-of-Truth Architecture Checkpoint", ARCHITECTURE_BLOCK)
append_once(DOC_ROADMAP, "Slice 22F - Update High-Level Project Source-of-Truth Architecture Checkpoint", ROADMAP_BLOCK)
append_once(DOC_CONTROLS, "Slice 22F control - high-level architecture checkpoint", CONTROLS_BLOCK)
append_once(DOC_DECISIONS, "Slice 22F decision - preserve TradingAgents / crypto-trading-agent role split", DECISIONS_BLOCK)

print("[PASS] Slice 22F high-level architecture checkpoint applied.")
print("[PASS] Role split between TradingAgents and crypto-trading-agent documented.")
print("[PASS] Roadmap, controls, decision log, and safety checkpoint updated.")

'@

$TempPatch = Join-Path $env:TEMP "apply_slice_22f_architecture_checkpoint_patch.py"
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
Write-Host "Running Slice 22F validation..."
Invoke-CheckedPython -Arguments @(".\scripts\run_execution_safety_regression_suite.py")

Write-Host ""
Write-Host "Checking working tree..."
git status --short
if ($LASTEXITCODE -ne 0) {
  throw "git status failed with exit code ${LASTEXITCODE}"
}

Write-Host ""
Write-Host "[PASS] Slice 22F architecture checkpoint and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Update high-level architecture checkpoint"
Read-Host "Press Enter to close..."
