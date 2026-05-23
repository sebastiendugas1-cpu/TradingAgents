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

## Slice 14A — Global Live Execution Safety Config

A global live execution safety config has been introduced.

Default behavior is intentionally restrictive:
- Live trading is disabled.
- Kill switch is enabled.
- Maximum live trade value is zero.

The config is implemented in:

`tradingagents/execution/safety_config.py`

Future live execution code must call the safety gate before any executable action is allowed.

Current restrictions:
- No live trading code exists in this slice.
- No Kraken AddOrder call exists in this slice.
- No Kraken CancelOrder call exists in this slice.
- No withdrawal code exists in this slice.
- No funding code exists in this slice.
- No trading permission is required for this slice.

The safety config provides a safe report that excludes secrets and raw credential values.

## Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton

A disabled-by-default Kraken live execution client skeleton has been introduced.

The client is implemented in:

`tradingagents/execution/kraken_live_execution_client.py`

Safety requirements:
- All future executable paths must pass through `LiveExecutionSafetyConfig.assert_live_execution_allowed(...)`.
- Default config blocks all submit/cancel paths.
- Kill switch blocks all submit/cancel paths.
- Even if a permissive test config is supplied, Slice 14B raises a not-implemented error instead of calling any private client.

Current restrictions:
- No real Kraken live execution endpoint call exists.
- No live order submission is implemented.
- No live cancellation is implemented.
- No withdrawal or funding behavior exists.
- No trading permission is required for validation.

## Slice 14C — Live Execution Permission Preflight

A live execution permission preflight layer has been introduced.

The preflight layer reports:
- Whether live trading is enabled.
- Whether the kill switch is active.
- The maximum configured live trade value.
- Whether explicit confirmation is present and valid.
- Whether dangerous funding/withdrawal environment terms were detected.

The preflight report is safe to log:
- It does not expose API keys.
- It does not expose API secrets.
- It does not expose token or password values.
- It records whether execution endpoints were called, which remains false in this slice.

Current restrictions remain unchanged:
- No Kraken AddOrder call exists in this slice.
- No Kraken CancelOrder call exists in this slice.
- No withdrawal code exists in this slice.
- No funding code exists in this slice.
- No trading permission is required for this slice.
