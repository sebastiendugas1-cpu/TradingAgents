# ============================ Slice 6 - TradingView Integration Plan ============================
# Purpose:
# Updates TradingView documentation and decision log for a safe, logging-first integration plan.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_06_tradingview_plan.ps1

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

Write-DocFile "06_TRADINGVIEW_PLAN.md" @'
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
'@

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
$DecisionLog = Get-Content $DecisionLogPath -Raw
$Entry = @'

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
'@

if ($DecisionLog -notmatch "Slice 6 TradingView Plan") {
    Add-Content -Path $DecisionLogPath -Value $Entry -Encoding UTF8
}

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
$Roadmap = Get-Content $RoadmapPath -Raw
$Roadmap = $Roadmap.Replace("## Slice 6 — TradingView Integration Plan`r`n`r`nGoal:`r`n`r`nDocument how TradingView alerts will enter the system.", "## Slice 6 — TradingView Integration Plan`r`n`r`nStatus: In progress.`r`n`r`nGoal:`r`n`r`nDocument how TradingView alerts will enter the system safely before any webhook code exists.")
$Roadmap = $Roadmap.Replace("## Slice 7 — TradingView Webhook Receiver", "## Slice 7 — TradingView Webhook Receiver")
Set-Content -Path $RoadmapPath -Value $Roadmap -Encoding UTF8

Write-Host "=== SLICE 6 TRADINGVIEW DOCS UPDATED ==="
Get-Item (Join-Path $DocsPath "06_TRADINGVIEW_PLAN.md"), (Join-Path $DocsPath "11_DECISION_LOG.md"), (Join-Path $DocsPath "03_ROADMAP.md") | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 6 script completed."
