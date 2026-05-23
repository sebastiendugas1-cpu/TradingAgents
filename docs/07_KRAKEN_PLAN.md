# Kraken Integration Plan

## Purpose

Kraken is the primary crypto exchange target for market data and eventual execution.

## Current Kraken Status

Current status:

```text
Public market data exists.
Private account access is not enabled.
Live trading is not enabled.
No Kraken private API calls are allowed yet.
```

## Integration Phases

### Phase 1 — Public Market Data

Status: complete.

No API key required.

Implemented features:

- Fetch supported asset pairs.
- Fetch ticker prices.
- Fetch OHLCV candles.
- Validate symbols.
- Normalize Kraken pairs into internal format.

### Phase 2A — Read-Only Safety Plan and Config Validator

Status: current slice.

No Kraken private API calls.

This phase creates:

- Read-only configuration validator.
- Permission safety checklist.
- Secret-safe status reporting.
- Hard blocking for trading, funding, and withdrawals.

### Phase 2B — Read-Only Private Access

API key required, but read-only permissions only.

Allowed:

- Read balances.
- Read open orders.
- Read trade history.

Forbidden:

- Place orders.
- Cancel orders.
- Withdraw funds.
- Funding actions.
- Margin/futures actions.

### Phase 3 — Manual-Confirmation Trading

API key may include trading permission only after previous phases are validated.

Rules:

- System proposes order.
- User confirms manually.
- Order is logged.
- Risk limits are checked before placement.

### Phase 4 — Restricted Automation

Only after paper trading and manual-confirmation trading are stable.

Required controls:

- Max trade size.
- Max daily loss.
- Max exposure.
- Kill switch.
- Cooldown rules.
- Audit logs.

## Required Kraken API Key Rules

- Never use withdrawal permission.
- Never use funding permission in this project phase.
- Never commit API keys.
- Store secrets in `.env`.
- Start read-only.
- Add trading permission only when explicitly approved in a later slice.

## `.env` Planning

Future read-only variables:

```text
KRAKEN_API_KEY=
KRAKEN_API_SECRET=
KRAKEN_TRADING_ENABLED=false
KRAKEN_WITHDRAWALS_ENABLED=false
KRAKEN_FUNDING_ENABLED=false
KRAKEN_ALLOWED_PERMISSIONS=balances,open_orders,trade_history
```

## Slice 12A Validation Rule

The config validator must reject:

- trading enabled
- withdrawals enabled
- funding enabled
- dangerous permission names
- any attempt to expose API key or secret values in output

## Slice 12B Mock-Only Rule

Before real private Kraken API calls are implemented, the project uses a mock-only read-only private client.

This mock client proves the interface for:

- Balances.
- Open orders.
- Trade history.
- Account snapshot.

It also proves that dangerous operations are blocked:

- Placing orders.
- Canceling orders.
- Withdrawals.
- Funding operations.

No real Kraken keys are required for Slice 12B.

## Slice 12C-1 — Read-Only Environment Validator

Before using a real Kraken private API key, the project must validate local configuration.

The validator must confirm:

- `KRAKEN_API_KEY` is present.
- `KRAKEN_API_SECRET` is present.
- `KRAKEN_TRADING_ENABLED` is not true.
- `KRAKEN_WITHDRAWALS_ENABLED` is not true.
- `KRAKEN_FUNDING_ENABLED` is not true.
- Dangerous permission words such as trade, withdraw, margin, leverage, futures, or funding are not present in local permission fields.

This slice does not call Kraken.

It only confirms that the local environment is ready for a future read-only private client test.
