# TradingView Integration Plan

## Purpose

TradingView will be used as a charting, alert, and signal-input layer.

TradingView is not the exchange and must not directly place live trades in early development.

The first TradingView implementation must be **logging-only**.

## Current Project Rule

TradingView alerts can eventually become inputs into the decision system, but they must follow this path:

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
Paper Trading
    |
Manual Review
    |
Restricted Automation, much later
```

## Initial Role

TradingView may provide:

- Manual chart analysis.
- Alert signals.
- Strategy alerts.
- Watchlist monitoring.
- Webhook payloads later.

TradingView signals must be treated as **inputs**, not final trade commands.

## Development Phases

### Phase 1 — Documentation Only

Status: current slice.

Goal:

- Define payload format.
- Define security expectations.
- Define signal types.
- Define the no-live-trading rule.

No code receiver yet.

### Phase 2 — Local Webhook Receiver

Goal:

- Add a local webhook endpoint.
- Accept test alerts only.
- Validate payload shape.
- Validate secret token.
- Write alerts to a local log.
- Do not place trades.

### Phase 3 — Paper-Trading Signal Input

Goal:

- Convert valid TradingView alerts into paper-trading signals.
- Simulate entries/exits.
- Log performance.

### Phase 4 — Manual-Confirmation Signal Input

Goal:

- TradingView alert triggers a trade proposal.
- System analyzes risk.
- User manually approves or rejects.

### Phase 5 — Restricted Automation

Goal:

- Only after backtesting, paper trading, and manual-confirmation mode are validated.
- Alerts may contribute to restricted live execution only when all safety gates pass.

## Required Alert Payload Format

TradingView alert messages should be valid JSON.

Planned minimum payload:

```json
{
  "source": "tradingview",
  "version": "1.0",
  "event_id": "{{ticker}}-{{time}}-example",
  "symbol": "BTC/USD",
  "exchange": "KRAKEN",
  "timeframe": "1h",
  "signal": "long",
  "strategy": "example_strategy",
  "confidence": 72,
  "price": "{{close}}",
  "timestamp": "{{time}}",
  "secret": "LOCAL_SECRET_TOKEN"
}
```

## Required Fields

The webhook receiver should eventually require:

- `source`
- `version`
- `event_id`
- `symbol`
- `timeframe`
- `signal`
- `strategy`
- `timestamp`
- `secret`

## Optional Fields

Optional fields may include:

- `exchange`
- `confidence`
- `price`
- `risk_level`
- `notes`
- `take_profit`
- `stop_loss`

## Allowed Signal Types

Initial allowed signals:

```text
watch
long
short
exit
reduce
increase
neutral
```

Early implementation should not execute these. It should only validate and log them.

## Security Rules

A TradingView webhook receiver must include:

- Secret token validation.
- Payload schema validation.
- Rejection of unknown signal types.
- Rejection of missing symbol or timeframe.
- Rejection of malformed JSON.
- Full logging of accepted and rejected alerts.
- No secrets in GitHub.
- No API keys in TradingView alert bodies.

## Safety Rules

TradingView alerts must not place live orders until:

- Backtesting exists.
- Paper trading exists.
- Manual-confirmation mode exists.
- Kraken order safety gates exist.
- Kill switch exists.
- Daily loss limits exist.
- Max trade size exists.
- Audit logging exists.

## Local Development Notes

During development, the receiver may run locally.

A public webhook endpoint may later require:

- VPS or cloud host.
- HTTPS endpoint.
- Reverse proxy or tunnel for testing.
- Secure environment variables.
- Request logging.

## TradingView Operational Notes

TradingView webhook alerts are expected to send HTTP POST requests to a configured external URL.

The alert message should be JSON when possible so the receiver can parse it consistently.

The receiving server must respond quickly and should not perform long-running analysis directly inside the webhook request. Instead, it should log the alert and hand off processing to a separate worker or queue.

## Implementation Rule

When the code slice for TradingView begins, the first receiver must be:

```text
logging-only
```

It must not call Kraken order endpoints.

It must not place simulated orders until the paper-trading slice exists.

It must not place live orders until the restricted live trading phase is explicitly approved.

## Slice 7 Implementation Notes

The first webhook receiver is logging-only.

Local endpoint:

```text
POST http://127.0.0.1:8765/tradingview
```

Local signal log:

```text
.signals/tradingview_signals.jsonl
```

Required payload fields:

- `source`
- `symbol`
- `signal`
- `secret`

Optional payload fields:

- `timeframe`
- `strategy`
- `confidence`

Allowed signals:

- `long`
- `short`
- `exit`
- `watch`
- `neutral`

This slice does not place trades.
