# ============================ Slice 13A - Manual Confirmation Trading Plan ============================
# Purpose:
# Creates/updates documentation for the manual-confirmation trading workflow.
#
# Safety:
# - No live trading code
# - No Kraken private trading calls
# - No order placement
# - No order cancellation
# - No funding or withdrawal actions
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_13a_manual_confirmation_plan.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$DocsPath = Join-Path $ProjectRoot "docs"

Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path $DocsPath | Out-Null

function Write-DocFile {
    param(
        [string]$FileName,
        [string]$Content
    )

    $FullPath = Join-Path $DocsPath $FileName
    Set-Content -Path $FullPath -Value $Content -Encoding UTF8
}

Write-DocFile "13_MANUAL_CONFIRMATION_TRADING_PLAN.md" @'
# Manual-Confirmation Trading Plan

## Purpose

This document defines the future workflow for manual-confirmation trading.

Manual-confirmation trading means:

```text
The system may propose a trade.
The user must review the proposal.
The user must explicitly approve.
Only then can a future execution layer place the order.
```

This slice is planning-only. It does not add live trading, order placement, order cancellation, or exchange execution.

## Current Safety Status

The project currently supports:

- Public Kraken market data.
- Real Kraken read-only private data.
- TradingView webhook logging.
- Strategy scoring.
- Backtesting.
- Paper trading.

The project still does not support:

- Live order placement.
- Live order cancellation.
- Withdrawals.
- Funding actions.
- Automated trading.

## Required Manual-Confirmation Workflow

The future manual-confirmation flow must follow this sequence:

```text
1. Market data is collected.
2. Agents produce structured opinions.
3. Strategy scoring engine produces a scorecard.
4. Risk controls review the scorecard.
5. The system creates a trade proposal.
6. The proposal is displayed to the user.
7. The user explicitly approves or rejects.
8. If approved, a future execution layer may place the order.
9. Every proposal and decision is logged.
```

## Trade Proposal Requirements

Every trade proposal must include:

- Timestamp.
- Asset symbol.
- Direction: buy / sell / hold.
- Suggested order type.
- Suggested quantity.
- Estimated price.
- Estimated notional value.
- Estimated fees if available.
- Reason summary.
- Agent score breakdown.
- Confidence score.
- Risk score.
- Risk/reward notes.
- Stop-loss plan.
- Take-profit plan.
- Max loss estimate.
- Source of signal: agents, TradingView, manual, or combined.
- Execution mode: manual-confirmation only.
- Approval status.

## Required User Approval

A future approval prompt must require an explicit confirmation phrase such as:

```text
APPROVE
```

The system must not accept vague inputs such as:

```text
yes
ok
go
sure
```

This prevents accidental execution.

## Required Block Conditions

Manual-confirmation trade proposals must be blocked if:

- The scorecard action is `blocked`.
- Risk score exceeds the configured limit.
- Confidence score is below the configured threshold.
- The symbol is not allowed.
- The proposed quantity exceeds max trade size.
- The notional value exceeds max allowed exposure.
- Daily loss limit is reached.
- The account is in kill-switch mode.
- Kraken API key permissions are unsafe.
- Required data is missing.
- The proposal was generated from an invalid TradingView token.
- The user has not explicitly approved.

## Audit Log Requirements

Every proposal must be logged, even if blocked or rejected.

The audit log should include:

- Proposal ID.
- Timestamp.
- Asset.
- Direction.
- Quantity.
- Estimated price.
- Estimated notional value.
- Status: proposed, blocked, rejected, approved, simulated, executed.
- Reason summary.
- Risk score.
- Confidence score.
- User decision.
- Execution result if applicable.
- Error details if applicable.

The audit log must never include API keys, API secrets, or raw authentication headers.

## Execution Boundary

Manual-confirmation is not the same as automation.

Manual-confirmation means:

```text
The system cannot act without the user's explicit approval.
```

Automation means:

```text
The system can act without user approval.
```

This project must complete and validate manual-confirmation before restricted automation is considered.

## Next Implementation Slice

The next coding slice after this plan should be:

```text
Slice 13B — Trade Proposal Model
```

Slice 13B should create data models only, such as:

- TradeProposal
- TradeProposalStatus
- TradeApprovalDecision
- TradeRiskSummary

It must still not place live orders.
'@

# Update roadmap if the manual confirmation plan doc is not already listed.
$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $roadmap = Get-Content $RoadmapPath -Raw

    if ($roadmap -notmatch "Slice 13A") {
        $roadmap += @'

## Slice 13A — Manual-Confirmation Trading Plan

Status: Complete.

Goal:

Define the manual-confirmation workflow before any live execution code exists.

Deliverables:

- `docs/13_MANUAL_CONFIRMATION_TRADING_PLAN.md`

Rules:

- Planning only.
- No order placement.
- No Kraken trading permission.
- No cancellation.
- No withdrawals.
- No funding actions.

Commit message:

```text
Add manual-confirmation trading plan
```
'@
    }

    $roadmap = $roadmap -replace "## Slice 13 — Manual-Confirmation Trading\s+Goal:\s+System proposes trades, user approves manually\.", "## Slice 13 — Manual-Confirmation Trading`n`nGoal:`n`nSystem proposes trades, user approves manually.`n`nSplit into:`n`n- Slice 13A — Manual-confirmation trading plan.`n- Slice 13B — Trade proposal model.`n- Slice 13C — Manual approval workflow.`n- Slice 13D — Execution bridge, only after explicit approval and safety validation."

    Set-Content -Path $RoadmapPath -Value $roadmap -Encoding UTF8
}

# Update execution/risk controls doc.
$RiskPath = Join-Path $DocsPath "10_EXECUTION_AND_RISK_CONTROLS.md"
if (Test-Path $RiskPath) {
    $risk = Get-Content $RiskPath -Raw

    if ($risk -notmatch "## Manual-Confirmation Requirements") {
        $risk += @'

## Manual-Confirmation Requirements

Before any future live order execution can exist, the system must implement manual-confirmation controls.

Required behavior:

- Create a trade proposal.
- Show the full risk summary.
- Require explicit user approval.
- Reject vague approval words.
- Log every proposed, blocked, rejected, approved, simulated, or executed trade.
- Never execute without explicit approval.
- Never store secrets in logs.

A valid approval should require a deliberate confirmation phrase such as:

```text
APPROVE
```

Manual-confirmation must be validated before restricted automation is considered.
'@
    }

    Set-Content -Path $RiskPath -Value $risk -Encoding UTF8
}

# Update decision log.
$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    $decisionLog = Get-Content $DecisionLogPath -Raw

    if ($decisionLog -notmatch "Manual-Confirmation Trading Plan") {
        $decisionLog += @'

## 2026-05-22 — Manual-Confirmation Trading Plan

Decision:

The project will require a manual-confirmation layer before any future live trading execution.

Key points:

- The system may propose trades, but cannot execute without explicit user approval.
- Approval must require deliberate confirmation.
- Every proposal must include risk, confidence, quantity, estimated value, and reason summary.
- Every proposal and decision must be logged.
- Manual-confirmation must be validated before restricted automation.
- This slice is documentation-only and does not add live trading.
'@
    }

    Set-Content -Path $DecisionLogPath -Value $decisionLog -Encoding UTF8
}

Write-Host "=== SLICE 13A MANUAL-CONFIRMATION PLAN CREATED ==="
Write-Host ""

Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "Slice 13A script completed."
Write-Host ""

Get-ChildItem $DocsPath | Where-Object { $_.Name -in @(
    "03_ROADMAP.md",
    "10_EXECUTION_AND_RISK_CONTROLS.md",
    "11_DECISION_LOG.md",
    "13_MANUAL_CONFIRMATION_TRADING_PLAN.md"
) } | Select-Object Name, Length, LastWriteTime
