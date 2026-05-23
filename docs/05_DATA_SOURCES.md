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
