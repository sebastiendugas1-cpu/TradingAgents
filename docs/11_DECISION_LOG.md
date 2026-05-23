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

## 2026-05-22 — Slice 3 Asset Normalization

Decision:

The project will use a shared asset normalization layer before adding Kraken, TradingView, backtesting, or execution logic.

Initial normalized formats:

- Crypto pairs use `BASE/QUOTE`, such as `BTC/USD`.
- Traditional tickers use uppercase ticker symbols, such as `AAPL`.
- TradingView-style prefixes such as `NASDAQ:AAPL` and `KRAKEN:BTCUSD` are preserved as `venue_prefix` metadata.
- Kraken alias `XBT` is normalized to `BTC`.

Safety:

This slice adds no trading capability and no external API calls.

## 2026-05-22 — Slice 4 — Kraken Public Market Data Adapter

Decision:

Add a public-data-only Kraken adapter.

Scope:

- Public REST endpoints only.
- No Kraken API key.
- No private account data.
- No balances.
- No order placement.
- No order cancellation.
- No live execution.

Initial functions:

- `get_server_time()`
- `get_asset_pairs()`
- `resolve_pair(symbol)`
- `get_ticker(symbol)`
- `get_ohlcv(symbol, interval_minutes=60)`

Validation:

- Resolve BTC/USD and ETH/USD.
- Fetch BTC/USD ticker.
- Fetch BTC/USD OHLCV candles.
- Reject traditional symbols such as AAPL in the Kraken crypto adapter.

## 2026-05-22 — Slice 5 — Local Market Data Cache

Decision:

Add a local JSON-file market data cache for public market data snapshots.

Key points:

- Cache is local only and ignored by Git under `.data-cache/`.
- Cache supports ticker and OHLCV-style payloads.
- Cache has stale-data detection.
- Cache can be cleared manually.
- No private API data, balances, orders, or execution are included.

## 2026-05-22 — Slice 6 TradingView Plan

Decision:

TradingView will be treated as a signal and alert input layer, not an execution platform.

Rules:

- First implementation must be documentation only.
- First code receiver must be logging-only.
- Alerts must use validated JSON payloads.
- Alerts must include a secret token.
- Alerts must never include API keys or credentials.
- TradingView alerts must not place Kraken orders in early slices.
- Paper trading and manual-confirmation mode must exist before any TradingView signal can contribute to live trading.

## 2026-05-22 — Slice 7 TradingView Webhook Receiver

Decision:

Add a logging-only TradingView webhook receiver.

Rules:

- Webhook payloads must include a shared secret.
- Payloads must be validated before logging.
- Signals are normalized using the Slice 3 asset normalizer.
- Signal logs are local only and ignored by Git.
- No Kraken private API is used.
- No orders are placed.
- No live trading is allowed in this slice.

## 2026-05-22 — Slice 8 Agent Decision Architecture

Decision:

Added a safe structured decision layer where agents produce analysis and recommendations only.

Key points:

- Agent outputs are structured as opinions, risk assessments, and recommendations.
- Allowed recommendation statuses are WATCH, PAPER_TRADE, MANUAL_REVIEW, and BLOCKED.
- There is intentionally no LIVE_TRADE status in this layer.
- This layer does not place orders or call Kraken private APIs.

## 2026-05-22 — Slice 9 Completed: Strategy Scoring Engine

Decision:

Added a safe strategy scoring engine that converts structured agent opinions into a normalized scorecard.

Key points:

- Supports confidence scoring.
- Supports risk scoring.
- Supports agent score breakdown.
- Limits output actions to watch, paper trade, manual review, or blocked.
- Does not support live-trade execution.
- Does not call Kraken private APIs.
- Does not place orders.

## 2026-05-22 — Slice 10 Backtesting Engine

Decision:

A safe historical backtesting layer was added.

Key points:

- The backtesting engine simulates historical trades only.
- It does not place orders.
- It does not call Kraken private APIs.
- It supports long and short simulations.
- It uses candle data and structured simulated signals.
- Outputs include simulated trades, P/L, win rate, drawdown, and profit factor.

## 2026-05-22 — Slice 11 Paper Trading Engine

Decision:

Added a safe paper-trading engine.

Key points:

- Simulation only.
- No live trading.
- No Kraken private API.
- No real balances.
- Supports paper cash, positions, fills, rejected orders, blocked orders, and reports.
- Supports converting PAPER_TRADE scorecards into simulated paper trades.

## 2026-05-22 — Slice 12A Kraken Read-Only Safety Config

Decision:

Before using real Kraken private API keys, the project will first add a read-only configuration validator.

Key points:

- Slice 12A does not call Kraken private APIs.
- Slice 12A does not require real Kraken keys.
- Trading, funding, and withdrawal flags are rejected.
- Dangerous permission names are rejected.
- Secret values must never be printed.
- Real Kraken private account access will be a later slice.

## 2026-05-22 — Slice 12B Kraken Read-Only Mock Client

Decision:

The first Kraken private-client implementation will be mock-only.

Reason:

This allows the project to define and test the account-data interface before any real Kraken API keys are used.

Safety rules:

- No private Kraken API calls.
- No real balance reads.
- No order placement.
- No order cancellation.
- No withdrawals.
- No funding operations.

## 2026-05-22 — Slice 12C-1 Kraken Read-Only Environment Validator

Decision:

Before calling real Kraken private endpoints, the project will validate local read-only configuration.

This validator must not call Kraken and must not expose API key or secret values.

The validator blocks unsafe flags such as trading, withdrawals, and funding.

## 2026-05-22 — Slice 12C-2: Real Kraken Read-Only Client

Decision:

Added a real Kraken private read-only client.

Safety boundaries:

- Balance reading only.
- Open-order reading only.
- Trade-history reading only.
- No order placement.
- No cancellation.
- No withdrawal.
- No funding operation.
- No secrets printed in validation.

## 2026-05-22 — Manual-Confirmation Trading Plan

Decision:

The project will require a manual-confirmation layer before any future live trading execution.

Key points:

- The system may propose trades, but cannot execute without explicit user approval.
- Approval must require deliberate confirmation.
- Every proposal must include risk, confidence, quantity, estimated value, and reason summary.
- Every proposal and decision must be logged.
- Manual-confirmation must be validated before restricted automation.
- This slice is documentation-only and does not add live trading.

## 2026-05-22 — Slice 13B Trade Proposal Model

Decision:

Add a manual-confirmation trade proposal model that can represent proposed trades, risk summaries, and approval records without executing anything.

Rules:

- A trade proposal is not an order.
- A trade proposal cannot call Kraken.
- A trade proposal cannot execute live trades.
- Blocked or watch-only decisions cannot become proposals.
- Manual approval records are audit records only.

## 2026-05-22 — Slice 13C Manual Approval Workflow

Decision:

Created a local manual approval workflow for trade proposals.

Key points:

- Approval requires exact confirmation text: `APPROVE <proposal_id>`.
- Rejection requires exact confirmation text: `REJECT <proposal_id>`.
- Approval/rejection records are written locally.
- The workflow does not place Kraken orders.
- The workflow does not cancel Kraken orders.
- The workflow does not call private exchange APIs.
- The workflow is still pre-execution only.

## 2026-05-22 — Slice 13D Risk Gate Engine

Decision:

Added a safe risk gate engine that evaluates manually approved trade proposals before any future dry-run/order-preview workflow.

The risk gate checks:

- Kill switch state.
- Manual approval requirement.
- Allowed symbols.
- Maximum trade value.
- Maximum risk score.
- Minimum confidence score.
- Allowed decision statuses.

This slice does not place orders, cancel orders, call trading endpoints, access funding, or withdraw assets.

## 2026-05-22 — Slice 13E Kraken Order Preview / Dry-Run Model

Decision:

Added a dry-run-only Kraken order preview model.

This allows the system to convert an approved proposal and passing risk-gate result into a local Kraken-style payload for inspection only.

Safety boundaries:

- The preview does not call Kraken.
- The preview does not place orders.
- The preview does not cancel orders.
- The preview does not use API keys.
- The preview is explicitly marked dry-run-only.

## Slice 14A Decision — Live Execution Must Be Blocked by Default

Decision:
Before adding any future live execution layer, the project must first include a global safety config.

Reason:
The project already supports read-only Kraken access, paper trading, backtesting, TradingView webhook triggers, manual approval, risk gates, and dry-run previews. The next safety requirement is a hard global execution gate before any live trading function can exist.

Chosen defaults:
- `LIVE_TRADING_ENABLED=false`
- `KILL_SWITCH=true`
- `MAX_LIVE_TRADE_VALUE=0`

Result:
Future live execution must be explicitly enabled, must pass a kill-switch check, must have a positive max trade value, and must include explicit confirmation.

This slice intentionally does not introduce Kraken AddOrder, Kraken CancelOrder, funding, withdrawal, or automatic live order functionality.

## Slice 14B Decision — Create Live Execution Shape Without Enabling Live Execution

Decision:
Create the Kraken live execution client skeleton before adding any real live execution behavior.

Reason:
The project now has manual approval, risk gates, dry-run previews, and a global execution safety config. The next safe architectural step is to define where future live execution will live while proving that all paths remain blocked by default.

Chosen approach:
- Create typed request models for future submit and cancel paths.
- Require the Slice 14A safety gate before any future executable behavior.
- Keep the methods intentionally not implemented after the safety gate.
- Validate that the private client is never called.
- Validate that the source contains no Kraken live execution endpoint names.

Result:
The project gains the live execution client structure without enabling live trading.

## Slice 14C Decision — Add Preflight Before Any Future Live Execution

Decision:
Before any future manually triggered live execution path can be developed, the project must include a dedicated preflight validator.

Reason:
The project now has a kill switch, disabled-by-default live execution config, and a blocked Kraken live execution client skeleton. A separate preflight layer gives the project a safe status report before any future execution path can even be considered.

Chosen behavior:
- Preflight fails by default.
- Kill switch blocks preflight.
- Disabled live trading blocks preflight.
- Zero max live trade value blocks preflight.
- Missing explicit confirmation blocks preflight.
- Dangerous funding/withdrawal environment terms are reported safely.
- Secret values are never included in the report.

This slice intentionally does not introduce Kraken AddOrder, Kraken CancelOrder, funding, withdrawal, or automatic live order functionality.

## Slice 14D Decision — Add Final Manual Live Execution Readiness Report

Decision:
Before any future manual live order slice, the project must provide one combined readiness report across all safety layers.

Reason:
Separate safety layers now exist:
- Live execution safety config.
- Disabled Kraken live execution client skeleton.
- Live execution permission preflight.
- Risk gate engine.
- Manual approval workflow.

A combined report helps confirm whether the full system is still blocked by default or theoretically ready under intentionally configured conditions.

Result:
The default readiness state remains blocked. The report is safe to log, excludes secrets, and does not call execution endpoints.


## Slice 15A Decision — Simulate the Full Manual Execution Flow Before Live Execution

Decision:
Before introducing any real live order path, the project will first build an end-to-end manual live order simulation package.

Reason:
The project now has safety config, a disabled live execution client skeleton, permission preflight, readiness reporting, risk gates, manual approval, and dry-run order preview. The next practical step is to connect these pieces into one simulated manual execution package.

Result:
The system can represent the final manual execution flow without calling any private execution endpoint. This gives a safer test target before future live execution work.

## Slice 15B Decision — Audit Before Real Execution

Decision:
Before adding any real manual execution path, the project must have a durable local audit log for simulated and future live execution decisions.

Reason:
A trading system must be able to explain what was proposed, what was approved, what risk checks passed, what preview was generated, what final decision was made, and why.

Result:
Slice 15B adds a safe audit record model and JSONL writer. It remains execution-free and does not introduce private execution endpoint calls, funding, withdrawals, or trading permission requirements.

## Slice 15C Decision — Simulated Execution Must Be Auditable Before Live Execution

Decision:
Before any future live execution path is added, the project must prove that simulated manual execution packages can be converted into durable audit records.

Reason:
A future live order path must have an audit trail before it can be considered safe. The audit system needs to capture the decision package, readiness state, risk state, manual approval state, dry-run preview state, and final blocked/ready status.

Result:
Slice 15C integrates the manual live order simulation package with the execution audit log while still blocking all live execution behavior.

This slice intentionally does not add private execution endpoint calls, funding behavior, withdrawal behavior, or automatic live order functionality.

## Slice 15D Decision — Manual Execution Requires a Formal Command Model

Decision:
Before adding any future live execution path, the project must have a formal manual execution command model.

Reason:
The project now has simulation packages and execution audit logs. A future live path should not directly consume raw order dictionaries. It should consume a validated command object that is linked to a simulation package and audit record.

Result:
Slice 15D introduces a non-executable command model with strict validation and safe reporting.

Safety outcome:
- The command model cannot place orders.
- The command model cannot cancel orders.
- The command model does not call private execution endpoints.
- The command model does not require trading, funding, or withdrawal permissions.

## Slice 15E Decision — Command Builder Must Remain Non-Executable

Decision:
The manual execution command builder may connect simulation, audit, and command records, but it must not execute anything.

Reason:
Before live execution can exist, the system needs a complete auditable command candidate flow.

Result:
Slice 15E produces safe command candidates only. Commands remain blocked from live execution.
