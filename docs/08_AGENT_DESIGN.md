# Agent Design

## Purpose

The project should use specialized agents to analyze different dimensions of the market.

Agents should produce structured analysis, not direct unverified trade orders.

## Planned Agents

### Market Structure Agent

Focus:

- Trend.
- Support and resistance.
- Volatility.
- Volume.
- Market regime.

### Technical Analysis Agent

Focus:

- Indicators.
- Moving averages.
- Momentum.
- RSI / MACD / other selected signals.
- Timeframe alignment.

### News and Sentiment Agent

Focus:

- Market news.
- Social sentiment where available.
- Major events.
- Risk headlines.

### Risk Manager Agent

Focus:

- Position size.
- Drawdown.
- Stop-loss logic.
- Exposure.
- Risk/reward.

### Strategy Critic Agent

Focus:

- Challenge the proposed trade.
- Identify weak assumptions.
- Detect overconfidence.
- Recommend blocking risky setups.

### Final Decision Agent

Focus:

- Combine structured agent outputs.
- Produce final recommendation.
- Classify action as Watch, Paper Trade, Manual Review, or Blocked.

## Structured Output Goal

Agents should produce structured outputs such as:

```json
{
  "agent": "risk_manager",
  "asset": "BTC/USD",
  "risk_score": 68,
  "concerns": ["high volatility", "weak confirmation"],
  "recommendation": "manual_review"
}
```

## Rule

No individual agent should be allowed to place live trades directly.
