# Kraken Integration Plan

## Purpose

Kraken is the primary crypto exchange target for market data and eventual execution.

## Integration Phases

### Phase 1 — Public Market Data

No API key required.

Planned features:

- Fetch supported asset pairs.
- Fetch ticker prices.
- Fetch OHLCV candles.
- Validate symbols.
- Normalize Kraken pairs into internal format.

### Phase 2 — Read-Only Private Access

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

## API Key Rules

- Never use withdrawal permission.
- Never commit API keys.
- Store secrets in `.env`.
- Start read-only.
- Add trading permission only when explicitly approved.
