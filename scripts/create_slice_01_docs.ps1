# ============================ Slice 1 - Create Project Documentation Foundation ============================
# Purpose:
# Creates the initial docs/ truth-table files for the TradingAgents crypto / multi-asset project.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# D:; cd D:\Trading\TradingAgents; powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_01_docs.ps1

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

Write-DocFile "00_PROJECT_VISION.md" @'
# TradingAgents Crypto / Multi-Asset Project Vision

## Purpose

This project will evolve the TradingAgents framework into a flexible, multi-asset trading decision system.

The long-term goal is to support:

- Crypto assets such as BTC, ETH, SOL, and other selected pairs.
- Traditional assets such as stocks, ETFs, and indexes where supported.
- TradingView as a signal, charting, alert, and strategy-input layer.
- Kraken as a market-data and eventual execution platform.
- Modular AI agents that analyze different parts of the market.
- Backtesting, paper trading, manual-confirmation trading, and only later restricted live automation.

## Core Principle

This project must be built in layers.

The system must never jump directly from analysis to live trading. Every step must be documented, tested, validated, and committed before moving to the next layer.

## Final Desired Capability

The final system should be able to:

1. Collect market data.
2. Analyze assets using multiple specialized agents.
3. Compare strategies against historical data.
4. Run paper trades before real trades.
5. Present clear trade proposals.
6. Support manual approval.
7. Eventually execute restricted live trades only with strong risk controls.

## Non-Goal

The system must not promise guaranteed profits.

The correct goal is:

> Build a measurable, testable, risk-controlled trading decision and execution framework.

## Current Development Branch

Primary development branch:

```text
crypto-dev
```

## Project Status

Current stage:

```text
Slice 1 — Project documentation foundation
```
'@

Write-DocFile "01_SAFETY_RULES.md" @'
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
'@

Write-DocFile "02_ARCHITECTURE.md" @'
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
'@

Write-DocFile "03_ROADMAP.md" @'
# Roadmap

## Slice-Based Development Rule

Each slice must be treated as a complete, testable block.

Each slice must define:

- Goal.
- Scope.
- Files changed.
- Full script or full function blocks.
- Test command.
- Expected result.
- Validation checklist.
- Commit message.

## Slice 1 — Project Documentation Foundation

Status: In progress.

Goal:

Create the core documentation structure that acts as the project source of truth.

Deliverables:

- `docs/00_PROJECT_VISION.md`
- `docs/01_SAFETY_RULES.md`
- `docs/02_ARCHITECTURE.md`
- `docs/03_ROADMAP.md`
- `docs/04_SLICE_WORKFLOW.md`
- `docs/05_DATA_SOURCES.md`
- `docs/06_TRADINGVIEW_PLAN.md`
- `docs/07_KRAKEN_PLAN.md`
- `docs/08_AGENT_DESIGN.md`
- `docs/09_BACKTESTING_AND_OPTIMIZATION.md`
- `docs/10_EXECUTION_AND_RISK_CONTROLS.md`
- `docs/11_DECISION_LOG.md`
- `docs/12_NEXT_CHAT_PROMPT.md`

Validation:

- Docs folder exists.
- All core docs exist.
- No source code changed.
- Git status shows documentation changes only.

Commit message:

```text
Add project foundation documentation
```

## Slice 2 — Project Audit Script

Goal:

Create a safe local audit script that reports project status.

Expected checks:

- Current Git branch.
- Python version.
- Conda environment.
- Editable package status.
- `.env` exists.
- API key presence without revealing secrets.
- Git status summary.

Expected command:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python scripts/project_audit.py
```

## Slice 3 — Asset Model and Symbol Normalization

Goal:

Create a common asset format for crypto and traditional assets.

Examples:

- `BTC/USD`
- `ETH/USD`
- `SOL/CAD`
- `AAPL`
- `SPY`

## Slice 4 — Kraken Public Market Data Adapter

Goal:

Fetch public Kraken data without private API keys.

No trading.

## Slice 5 — Local Data Cache

Goal:

Cache market data locally to reduce repeated API calls and support testing.

## Slice 6 — TradingView Integration Plan

Goal:

Document how TradingView alerts will enter the system.

## Slice 7 — TradingView Webhook Receiver

Goal:

Receive TradingView alerts safely.

No trading.

## Slice 8 — Modular Agent Decision Architecture

Goal:

Define structured outputs from specialized agents.

## Slice 9 — Strategy Scoring Engine

Goal:

Convert agent opinions into measurable trading decisions.

## Slice 10 — Backtesting Engine

Goal:

Evaluate strategies against historical data.

## Slice 11 — Paper Trading Engine

Goal:

Simulate live trading without real money.

## Slice 12 — Kraken Read-Only Account Integration

Goal:

Read real account data with no trading permission.

## Slice 13 — Manual-Confirmation Trading

Goal:

System proposes trades, user approves manually.

## Slice 14 — Restricted Live Trading

Goal:

Enable limited real order execution with strict risk controls.

## Slice 15 — Optimization and Tuning

Goal:

Use historical and paper-trading results to improve strategies.
'@

Write-DocFile "04_SLICE_WORKFLOW.md" @'
# Slice Workflow

## Purpose

This file defines how every development slice must be handled.

The goal is to avoid vague requests such as:

```text
Make a big block of code.
```

Instead, every slice must be treated as a complete, testable, documented block.

## Required Slice Format

Each slice must include:

```text
Slice Number:
Slice Name:
Goal:
Scope:
Files Changed:
Do Not Change:
Deliverables:
Test Command:
Expected Result:
Validation Checklist:
Commit Message:
```

## Standard Development Flow

1. Define the slice in the roadmap.
2. Confirm the branch.
3. Implement the full block.
4. Run the test command.
5. Capture terminal output using the AutoHotkey capture workflow.
6. Debug if needed.
7. Validate checklist.
8. Commit in GitHub Desktop.
9. Push to GitHub fork.
10. Update the decision log.

## Preferred Code Delivery Style

The user prefers:

- Full updated files when possible.
- Full updated function blocks when replacing functions.
- No tiny line-only patches unless the change is very small.
- Clear file placement instructions.
- Clear test commands.
- Clear expected output.

## Branch Strategy

Primary branches:

```text
main       = stable fork copy
crypto-dev = active development branch
```

Future feature branches may use:

```text
feature/slice-02-project-audit
feature/slice-03-asset-normalization
feature/slice-04-kraken-public-data
```

## Testing Rule

A slice is not complete until it has:

- Code or docs delivered.
- Test command run.
- Output reviewed.
- Validation checklist passed.
- Git commit created.
- Push completed if appropriate.

## Safety Rule

No live trading code is allowed unless the slice explicitly belongs to the restricted live trading phase and all previous safety layers are complete.
'@

Write-DocFile "05_DATA_SOURCES.md" @'
# Data Sources

## Purpose

This file tracks planned data sources for the trading system.

## Primary Data Sources

### Kraken

Initial role:

- Public crypto market data.
- OHLCV candles.
- Ticker prices.
- Asset pairs.
- Later: read-only account data.
- Much later: restricted order execution.

### TradingView

Initial role:

- Chart-based analysis.
- Manual visual confirmation.
- Alert signals.
- Later: webhook alerts into the system.

TradingView is not the exchange. It is a signal and charting layer.

### OpenAI / LLM Providers

Role:

- Agent reasoning.
- Market analysis.
- News summarization.
- Strategy critique.
- Structured decision reports.

### Future Optional Sources

Possible future sources:

- Finnhub.
- Yahoo Finance.
- Alpha Vantage.
- CoinGecko.
- CoinMarketCap.
- News APIs.
- On-chain data providers.

## Data Safety Rules

- Never store API keys in source code.
- Never commit `.env`.
- Cache data only when safe.
- Clearly label historical, delayed, and real-time data.
- Do not mix paper trading and live trading logs without clear separation.

## Asset Classes

Target support:

- Crypto.
- Stocks.
- ETFs.
- Indexes where supported.

Initial implementation priority:

1. Crypto public market data.
2. Crypto historical candles.
3. Stock compatibility preserved where possible.
'@

Write-DocFile "06_TRADINGVIEW_PLAN.md" @'
# TradingView Integration Plan

## Purpose

TradingView will be used as a charting, alert, and signal-input layer.

It should not directly place live trades in the early phases.

## Initial Role

TradingView may provide:

- Manual chart analysis.
- Alert signals.
- Strategy alerts.
- Webhook payloads later.

## Future Webhook Flow

```text
TradingView Alert
    |
Webhook Receiver
    |
Payload Validation
    |
Security Token Check
    |
Signal Log
    |
Paper Trading or Manual Review
```

## Required Webhook Safety

Before accepting TradingView alerts:

- Secret token validation must exist.
- Payload schema validation must exist.
- Invalid alerts must be rejected.
- All alerts must be logged.
- Alerts must not place live trades during early development.

## Example Future Payload

```json
{
  "source": "tradingview",
  "symbol": "BTC/USD",
  "signal": "long",
  "timeframe": "1h",
  "strategy": "example_strategy",
  "confidence": 72,
  "secret": "local-secret-token"
}
```

## Development Rule

TradingView integration must first be implemented as logging-only.

Then paper trading.

Then manual-confirmation trading.

Only much later can a TradingView alert contribute to restricted automation.
'@

Write-DocFile "07_KRAKEN_PLAN.md" @'
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
'@

Write-DocFile "08_AGENT_DESIGN.md" @'
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
'@

Write-DocFile "09_BACKTESTING_AND_OPTIMIZATION.md" @'
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
'@

Write-DocFile "10_EXECUTION_AND_RISK_CONTROLS.md" @'
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
'@

Write-DocFile "11_DECISION_LOG.md" @'
# Decision Log

This file records major project decisions.

## 2026-05-22 — Project Direction

Decision:

The project will evolve into a multi-asset trading agent framework with crypto as the first practical focus.

Key points:

- Use the `crypto-dev` branch for active development.
- Preserve safety-first development.
- Use TradingView as signal/chart/alert layer.
- Use Kraken for crypto market data and eventual execution.
- Do not enable live trading early.
- Build in slices.
- Use Markdown docs as the project source of truth across chats.

## 2026-05-22 — Development Slice Rule

Decision:

Every major change must be treated as a complete slice.

Each slice must include:

- Goal.
- Scope.
- Files changed.
- Full script or full function blocks.
- Test command.
- Expected result.
- Validation checklist.
- Commit message.

## 2026-05-22 — Safety Rule

Decision:

No live Kraken trading until read-only analysis, market data, backtesting, paper trading, and manual-confirmation trading are validated.
'@

Write-DocFile "12_NEXT_CHAT_PROMPT.md" @'
# Next Chat Prompt

Use this prompt when starting a new chat for this project.

```text
We are working on the TradingAgents repo for a custom multi-asset / crypto trading agent project.

Local project path:
D:\Trading\TradingAgents

GitHub fork:
https://github.com/sebastiendugas1-cpu/TradingAgents

Active development branch:
crypto-dev

Current project status:
We are building the project in slices. The Markdown files in /docs are the source of truth.

Important docs:
- docs/00_PROJECT_VISION.md
- docs/01_SAFETY_RULES.md
- docs/02_ARCHITECTURE.md
- docs/03_ROADMAP.md
- docs/04_SLICE_WORKFLOW.md
- docs/11_DECISION_LOG.md

Development rules:
- Use full updated files or full function blocks.
- Avoid tiny partial snippets unless the change is very small.
- Every slice needs a goal, scope, test command, expected result, validation checklist, and commit message.
- No live trading yet.
- No Kraken trading keys yet.
- No withdrawal permission ever.
- TradingView is planned as a signal/alert layer.
- Kraken is planned as crypto market data and eventual execution platform.
- Start with analysis-only, then data, then backtesting, then paper trading, then read-only Kraken, then manual-confirmation trading, then restricted live trading.

User workflow:
The user runs local commands and captures terminal output with AutoHotkey into:
.chatGPT-output/output.txt

When debugging, ask the user to run commands and paste/upload the latest output.
```
'@

Write-Host "=== SLICE 1 DOCS CREATED ==="
Get-ChildItem $DocsPath | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 1 script completed."
