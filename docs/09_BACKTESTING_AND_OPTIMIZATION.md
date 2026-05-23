# Backtesting and Optimization

## Purpose

Backtesting and optimization are required before any live trading.

## Backtesting Goals

The system should be able to test:

- Entry logic.
- Exit logic.
- Stop-loss logic.
- Take-profit logic.
- Risk limits.
- Fees.
- Slippage.
- Drawdown.

## Required Metrics

Backtest reports should include:

- Total return.
- Win rate.
- Loss rate.
- Profit factor.
- Max drawdown.
- Average win.
- Average loss.
- Risk/reward.
- Number of trades.
- Fees paid.
- Slippage estimate.

## Optimization Rule

Optimization must not be treated as guaranteed profit.

The goal is to find robust configurations, not overfit historical data.

## Paper Trading Requirement

No strategy should move from backtesting to live trading directly.

Required path:

```text
Backtest
    |
Paper Trade
    |
Manual Confirmation
    |
Restricted Live Trading
```
