# ============================ Slice 4 - Kraken Public Data Validation ============================
"""
Validation script for the public-data-only Kraken adapter.

This script:
- Uses no Kraken API key.
- Does not access private account data.
- Does not place orders.
"""

from __future__ import annotations

import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))


from tradingagents.marketdata import KrakenPublicClient, KrakenPublicError  # noqa: E402


def main() -> int:
    print("Running Slice 4 Kraken public market data validation...")

    client = KrakenPublicClient(timeout_seconds=20)

    failures = 0

    try:
        server_time = client.get_server_time()
        print(f"[OK] Server time response keys: {list(server_time.keys())}")
    except KrakenPublicError as exc:
        failures += 1
        print(f"[FAIL] get_server_time: {exc}")

    for symbol in ["BTC/USD", "ETH/USD"]:
        try:
            pair_key = client.resolve_pair(symbol)
            print(f"[OK] {symbol} resolved to Kraken pair: {pair_key}")
        except KrakenPublicError as exc:
            failures += 1
            print(f"[FAIL] resolve_pair({symbol!r}): {exc}")

    try:
        ticker = client.get_ticker("BTC/USD")
        print(
            "[OK] BTC/USD ticker: "
            f"pair={ticker.kraken_pair_key}, "
            f"last={ticker.last_price}, "
            f"bid={ticker.bid}, "
            f"ask={ticker.ask}"
        )
    except KrakenPublicError as exc:
        failures += 1
        print(f"[FAIL] get_ticker('BTC/USD'): {exc}")

    try:
        candles = client.get_ohlcv("BTC/USD", interval_minutes=60)
        if not candles:
            failures += 1
            print("[FAIL] get_ohlcv('BTC/USD'): no candles returned")
        else:
            latest = candles[-1]
            print(
                "[OK] BTC/USD OHLCV: "
                f"candles={len(candles)}, "
                f"latest_time={latest.time}, "
                f"latest_close={latest.close}"
            )
    except KrakenPublicError as exc:
        failures += 1
        print(f"[FAIL] get_ohlcv('BTC/USD'): {exc}")

    try:
        client.resolve_pair("AAPL")
        failures += 1
        print("[FAIL] resolve_pair('AAPL'): expected traditional asset rejection")
    except KrakenPublicError:
        print("[OK] Traditional symbol AAPL rejected by Kraken crypto adapter")

    print()
    print(f"Failures: {failures}")

    if failures:
        print("Kraken public data validation failed.")
        return 1

    print("Kraken public data validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
