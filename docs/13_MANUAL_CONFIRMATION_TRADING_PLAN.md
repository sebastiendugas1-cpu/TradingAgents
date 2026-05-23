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
