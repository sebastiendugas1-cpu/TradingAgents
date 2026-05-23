# Architecture

## High-Level Architecture

The project will be structured as a layered trading-agent framework.

```text
User / Operator
    |
CLI / Dashboard / Future UI
    |
Project Orchestration Layer
    |
Agent Decision Layer
    |
Strategy Scoring Layer
    |
Backtesting / Paper Trading / Live Execution Layer
    |
Data Sources and Exchanges
```

## Major System Layers

### Layer 0 — Foundation

- GitHub repo.
- Branch workflow.
- Conda environment.
- Documentation.
- Audit tools.
- Safe `.env` handling.

### Layer 1 — Read-Only Analysis

- Run agents against assets.
- Generate reports.
- No trade execution.

### Layer 2 — Market Data

- Public Kraken market data.
- Historical OHLCV candles.
- Asset normalization.
- Data validation.
- Cache layer.

### Layer 3 — Specialized Agents

Possible agents:

- Market structure agent.
- Technical analysis agent.
- News and sentiment agent.
- Risk manager agent.
- Portfolio exposure agent.
- Strategy critic agent.
- Final decision agent.

### Layer 4 — Strategy Scoring

Agent output should be converted into structured decisions such as:

```text
Asset: BTC/USD
Direction: Long / Short / Neutral
Confidence: 0-100
Risk Score: 0-100
Suggested Action: Watch / Paper Trade / Manual Review / Blocked
```

### Layer 5 — Backtesting

- Test strategies on historical data.
- Include fees.
- Include slippage.
- Measure drawdown.
- Measure risk-adjusted performance.

### Layer 6 — Paper Trading

- Simulated orders.
- Simulated balances.
- Paper P/L.
- Trade history.
- Strategy comparison.

### Layer 7 — Kraken Read-Only

- Read balances.
- Read open orders.
- Read trade history.
- No order placement.

### Layer 8 — Manual-Confirmation Trading

- System proposes trade.
- User reviews.
- User approves manually.
- Order is placed only after confirmation.

### Layer 9 — Restricted Automation

- Small controlled position sizes.
- Hard risk limits.
- Kill switch.
- Full audit log.

## Design Principle

Each module must be replaceable.

The project should support multiple data sources, exchanges, and asset classes without rewriting the whole system.
