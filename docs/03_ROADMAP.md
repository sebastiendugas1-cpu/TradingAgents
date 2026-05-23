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

Status: Complete.

Goal:

Define structured outputs from specialized agents.

## Slice 9 — Strategy Scoring Engine

Status: Complete.

Goal:

Convert agent opinions into measurable trading decisions.

## Slice 10 — Backtesting Engine

Status: Complete.

Goal:

Evaluate strategies against historical data.

## Slice 11 — Paper Trading Engine

Status: Complete.

Goal:

Simulate live trading without real money using a safe paper account, fake balances, simulated fills, rejected orders, blocked orders, and P/L reporting.

## Slice 12A — Kraken Read-Only Safety Plan and Config Validator

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







## Slice 12B — Kraken Read-Only Mock Private Client

Goal:

Create a mock-only read-only Kraken private client interface before using real Kraken API keys.

Safety:

- No real Kraken private API calls.
- No real account access.
- No trading.
- No withdrawals.
- No funding actions.
- All execution-like methods must be explicitly blocked.

Validation:

- Mock balances can be read.
- Mock open orders can be read.
- Mock trade history can be read.
- Combined snapshot can be generated.
- `place_order`, `cancel_order`, `withdraw`, and funding actions are blocked.
