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
