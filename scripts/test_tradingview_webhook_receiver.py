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
