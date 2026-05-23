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
