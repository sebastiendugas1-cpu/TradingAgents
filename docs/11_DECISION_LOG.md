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
