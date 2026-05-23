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
