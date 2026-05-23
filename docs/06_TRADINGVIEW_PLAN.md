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
