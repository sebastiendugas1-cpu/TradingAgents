# Safety Rules

## Primary Rule

No live trading until the lower layers are complete, tested, and validated.

## Required Safety Progression

The project must progress in this order:

1. Documentation foundation.
2. Project audit and environment validation.
3. Read-only analysis.
4. Public market data.
5. Data caching.
6. Backtesting.
7. Paper trading.
8. Kraken read-only account access.
9. Manual-confirmation trading.
10. Restricted live trading.
11. Optimization and automation improvements.

## Kraken Safety Rules

When Kraken API keys are eventually used:

- No withdrawal permission.
- Start with read-only permissions only.
- No trade permission until paper trading and manual confirmation are validated.
- Never store API keys directly in code.
- API keys must stay in `.env` or another local secret store.
- `.env` must never be committed to GitHub.

## TradingView Safety Rules

TradingView alerts may be used later as signals.

TradingView alerts must not directly place live trades until:

- Webhook authentication exists.
- Payload validation exists.
- Paper trading has been tested.
- Manual-confirmation mode has been validated.
- Risk controls exist.

## Live Trading Safety Gates

Before restricted live trading, the system must include:

- Max trade size.
- Max daily loss.
- Max open positions.
- Max open orders.
- Cooldown after losses.
- Kill switch.
- Full trade audit log.
- Manual override.

## Forbidden Until Later

The following are forbidden in early slices:

- Live Kraken order placement.
- Automated trading without confirmation.
- High leverage.
- Margin/futures trading.
- Withdrawal API permissions.
- Hardcoded secrets.
