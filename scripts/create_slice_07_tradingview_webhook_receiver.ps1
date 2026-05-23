# ============================ Slice 7 - TradingView Webhook Receiver ============================
$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$SignalsDir = Join-Path $ProjectRoot "tradingagents\signals"
$ScriptsDir = Join-Path $ProjectRoot "scripts"
$DocsDir = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $SignalsDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null

function Write-TextFile {
    param([string]$Path, [string]$Content)
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-TextFile (Join-Path $SignalsDir "__init__.py") @'
"""Signal ingestion helpers for TradingAgents."""

from tradingagents.signals.tradingview_webhook import (
    TradingViewSignal,
    TradingViewWebhookError,
    handle_tradingview_payload,
    validate_tradingview_payload,
)

__all__ = [
    "TradingViewSignal",
    "TradingViewWebhookError",
    "handle_tradingview_payload",
    "validate_tradingview_payload",
]
'@

Write-TextFile (Join-Path $SignalsDir "tradingview_webhook.py") @'
"""Safe TradingView webhook payload handling.

Slice 7 rules:
- Logging only.
- No Kraken private API.
- No order placement.
- No live trading.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from tradingagents.assets import AssetIdentifier, normalize_asset_symbol


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SIGNAL_LOG_DIR = PROJECT_ROOT / ".signals"
DEFAULT_SIGNAL_LOG_FILE = DEFAULT_SIGNAL_LOG_DIR / "tradingview_signals.jsonl"

ALLOWED_SIGNALS = {"long", "short", "exit", "watch", "neutral"}
ALLOWED_SOURCES = {"tradingview"}


class TradingViewWebhookError(ValueError):
    """Raised when a TradingView webhook payload is invalid."""


@dataclass(frozen=True)
class TradingViewSignal:
    """Validated TradingView signal record."""

    received_at: str
    source: str
    symbol: str
    normalized_symbol: str
    asset_type: str
    signal: str
    timeframe: str | None
    strategy: str | None
    confidence: int | None
    raw_payload: dict[str, Any]


def validate_tradingview_payload(payload: dict[str, Any], expected_secret: str) -> TradingViewSignal:
    """Validate a TradingView alert payload and return a normalized signal.

    The secret is used only to authenticate the webhook payload.
    It is never stored in the signal log.
    """

    if not isinstance(payload, dict):
        raise TradingViewWebhookError("Payload must be a JSON object.")

    if not expected_secret:
        raise TradingViewWebhookError("Expected webhook secret is not configured.")

    supplied_secret = str(payload.get("secret", ""))
    if supplied_secret != expected_secret:
        raise TradingViewWebhookError("Invalid TradingView webhook secret.")

    source = str(payload.get("source", "")).strip().lower()
    if source not in ALLOWED_SOURCES:
        raise TradingViewWebhookError(f"Invalid source: {source!r}")

    raw_symbol = str(payload.get("symbol", "")).strip()
    if not raw_symbol:
        raise TradingViewWebhookError("Missing symbol.")

    raw_signal = str(payload.get("signal", "")).strip().lower()
    if raw_signal not in ALLOWED_SIGNALS:
        raise TradingViewWebhookError(f"Invalid signal: {raw_signal!r}")

    confidence = _parse_optional_int(payload.get("confidence"))
    if confidence is not None and not 0 <= confidence <= 100:
        raise TradingViewWebhookError("Confidence must be between 0 and 100.")

    asset: AssetIdentifier = normalize_asset_symbol(raw_symbol)

    safe_payload = dict(payload)
    safe_payload.pop("secret", None)

    return TradingViewSignal(
        received_at=datetime.now(timezone.utc).isoformat(),
        source=source,
        symbol=raw_symbol,
        normalized_symbol=asset.normalized,
        asset_type=asset.asset_type.value,
        signal=raw_signal,
        timeframe=_optional_string(payload.get("timeframe")),
        strategy=_optional_string(payload.get("strategy")),
        confidence=confidence,
        raw_payload=safe_payload,
    )


def handle_tradingview_payload(
    payload: dict[str, Any],
    expected_secret: str,
    log_file: Path | None = None,
) -> TradingViewSignal:
    """Validate and append a TradingView signal to a local JSONL log."""

    signal = validate_tradingview_payload(payload, expected_secret)
    target = log_file or DEFAULT_SIGNAL_LOG_FILE
    target.parent.mkdir(parents=True, exist_ok=True)

    with target.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(asdict(signal), sort_keys=True) + "\n")

    return signal


def _optional_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _parse_optional_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise TradingViewWebhookError("Confidence must be an integer.") from exc
'@

Write-TextFile (Join-Path $ScriptsDir "run_tradingview_webhook_receiver.py") @'
# ============================ TradingView Webhook Receiver Runner ============================
"""Run a local logging-only TradingView webhook receiver.

Default URL:
    http://127.0.0.1:8765/tradingview

Environment variables:
    TRADINGVIEW_WEBHOOK_SECRET
    TRADINGVIEW_WEBHOOK_HOST
    TRADINGVIEW_WEBHOOK_PORT
"""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from tradingagents.signals import TradingViewWebhookError, handle_tradingview_payload


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SIGNAL_LOG = PROJECT_ROOT / ".signals" / "tradingview_signals.jsonl"
DEFAULT_SECRET = "local-dev-secret"


class TradingViewWebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802 - stdlib method name
        if self.path != "/tradingview":
            self._send_json(404, {"ok": False, "error": "not_found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length).decode("utf-8")
            payload = json.loads(raw_body)

            secret = os.environ.get("TRADINGVIEW_WEBHOOK_SECRET", DEFAULT_SECRET)
            signal = handle_tradingview_payload(payload, expected_secret=secret, log_file=SIGNAL_LOG)

            self._send_json(
                200,
                {
                    "ok": True,
                    "mode": "logging_only",
                    "normalized_symbol": signal.normalized_symbol,
                    "signal": signal.signal,
                },
            )
        except json.JSONDecodeError:
            self._send_json(400, {"ok": False, "error": "invalid_json"})
        except TradingViewWebhookError as exc:
            self._send_json(400, {"ok": False, "error": str(exc)})
        except Exception as exc:  # defensive server boundary
            self._send_json(500, {"ok": False, "error": f"server_error: {exc}"})

    def log_message(self, format: str, *args: object) -> None:
        return

    def _send_json(self, status_code: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    host = os.environ.get("TRADINGVIEW_WEBHOOK_HOST", "127.0.0.1")
    port = int(os.environ.get("TRADINGVIEW_WEBHOOK_PORT", "8765"))

    server = ThreadingHTTPServer((host, port), TradingViewWebhookHandler)
    print(f"TradingView logging-only webhook receiver running at http://{host}:{port}/tradingview")
    print(f"Signal log: {SIGNAL_LOG}")
    print("Press Ctrl+C to stop.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping TradingView webhook receiver.")
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

Write-TextFile (Join-Path $ScriptsDir "test_tradingview_webhook_receiver.py") @'
# ============================ Slice 7 Validation - TradingView Webhook Receiver ============================
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.signals import TradingViewWebhookError, handle_tradingview_payload  # noqa: E402


def main() -> int:
    print("Running Slice 7 TradingView webhook receiver validation...")

    expected_secret = "test-secret"

    with tempfile.TemporaryDirectory() as temp_dir:
        log_file = Path(temp_dir) / "signals.jsonl"

        valid_payload = {
            "source": "tradingview",
            "symbol": "KRAKEN:BTCUSD",
            "signal": "long",
            "timeframe": "1h",
            "strategy": "slice7_validation",
            "confidence": 72,
            "secret": expected_secret,
        }

        signal = handle_tradingview_payload(valid_payload, expected_secret=expected_secret, log_file=log_file)
        assert signal.normalized_symbol == "BTC/USD"
        assert signal.asset_type == "crypto"
        assert signal.signal == "long"
        assert log_file.exists()
        print(f"[OK] Valid signal logged: {signal.normalized_symbol} {signal.signal}")

        rows = log_file.read_text(encoding="utf-8").splitlines()
        assert len(rows) == 1
        saved = json.loads(rows[0])
        assert "secret" not in saved["raw_payload"]
        print("[OK] Secret was not written to signal log")

        invalid_secret_payload = dict(valid_payload)
        invalid_secret_payload["secret"] = "wrong-secret"
        try:
            handle_tradingview_payload(invalid_secret_payload, expected_secret=expected_secret, log_file=log_file)
        except TradingViewWebhookError:
            print("[OK] Invalid secret rejected")
        else:
            raise AssertionError("Invalid secret was accepted")

        invalid_signal_payload = dict(valid_payload)
        invalid_signal_payload["signal"] = "buy-everything"
        try:
            handle_tradingview_payload(invalid_signal_payload, expected_secret=expected_secret, log_file=log_file)
        except TradingViewWebhookError:
            print("[OK] Invalid signal rejected")
        else:
            raise AssertionError("Invalid signal was accepted")

        traditional_payload = dict(valid_payload)
        traditional_payload["symbol"] = "NASDAQ:AAPL"
        traditional_payload["signal"] = "watch"
        signal = handle_tradingview_payload(traditional_payload, expected_secret=expected_secret, log_file=log_file)
        assert signal.normalized_symbol == "AAPL"
        assert signal.asset_type == "traditional"
        print("[OK] Traditional symbol accepted and normalized")

    print("TradingView webhook receiver validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# Ignore local signal logs.
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
if (-not (Test-Path $GitIgnorePath)) {
    New-Item -ItemType File -Path $GitIgnorePath | Out-Null
}
$GitIgnoreText = Get-Content $GitIgnorePath -Raw
if ($GitIgnoreText -notmatch "(?m)^\.signals/$") {
    Add-Content -Path $GitIgnorePath -Value "`n# Local TradingView signal logs`n.signals/"
}

# Documentation updates: append slice note once.
$DecisionLogPath = Join-Path $DocsDir "11_DECISION_LOG.md"
$DecisionMarker = "## 2026-05-22 — Slice 7 TradingView Webhook Receiver"
if (Test-Path $DecisionLogPath) {
    $DecisionText = Get-Content $DecisionLogPath -Raw
    if ($DecisionText -notlike "*$DecisionMarker*") {
        Add-Content -Path $DecisionLogPath -Value @'

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
'@
    }
}

$PlanPath = Join-Path $DocsDir "06_TRADINGVIEW_PLAN.md"
$PlanMarker = "## Slice 7 Implementation Notes"
if (Test-Path $PlanPath) {
    $PlanText = Get-Content $PlanPath -Raw
    if ($PlanText -notlike "*$PlanMarker*") {
        Add-Content -Path $PlanPath -Value @'

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
'@
    }
}

Write-Host "=== SLICE 7 FILES CREATED ==="
Get-ChildItem $SignalsDir | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 7 VALIDATION ==="
python .\scripts\test_tradingview_webhook_receiver.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 7 script completed."
