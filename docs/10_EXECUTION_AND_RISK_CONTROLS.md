# Execution and Risk Controls

## Purpose

This file defines the controls required before order execution.

## Execution Modes

### Mode 1 — Analysis Only

No orders.

### Mode 2 — Paper Trading

Simulated orders only.

### Mode 3 — Manual Confirmation

System proposes orders, user approves manually.

### Mode 4 — Restricted Automation

System may place limited orders under strict controls.

## Required Risk Controls Before Live Trading

- Max trade size.
- Max daily loss.
- Max total exposure.
- Max open positions.
- Max open orders.
- Stop-loss requirement.
- Cooldown after losing trades.
- Kill switch.
- Manual override.
- Full audit log.

## Block Conditions

The system must block trades when:

- API key permissions are unsafe.
- Daily loss limit is reached.
- Trade size exceeds limit.
- Symbol is not approved.
- Strategy confidence is below threshold.
- Risk score is too high.
- Required market data is missing.
- User has not approved in manual-confirmation mode.

## Audit Log Requirement

Every proposed, blocked, simulated, or executed trade must be logged.

Log should include:

- Timestamp.
- Asset.
- Direction.
- Size.
- Price.
- Reason.
- Agent scores.
- Risk decision.
- Execution mode.
- Result.
