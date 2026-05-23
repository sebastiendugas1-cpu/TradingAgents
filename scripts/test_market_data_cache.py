# ============================ Slice 5 Market Data Cache Validation ============================

from __future__ import annotations

import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.marketdata.cache import MarketDataCache  # noqa: E402


def main() -> int:
    print("Running Slice 5 market data cache validation...")

    cache = MarketDataCache(PROJECT_ROOT / ".data-cache" / "marketdata-test")
    cache.clear()

    payload = {
        "pair": "XXBTZUSD",
        "last": "75379.4",
        "bid": "75379.3",
        "ask": "75379.5",
    }

    path = cache.write(source="kraken", kind="ticker", symbol="BTC/USD", payload=payload)
    print(f"[OK] Wrote cache file: {path.relative_to(PROJECT_ROOT)}")

    record = cache.read(source="kraken", kind="ticker", symbol="BTC/USD")
    if record is None:
        print("[FAIL] Cache read returned None")
        return 1

    if record.payload != payload:
        print(f"[FAIL] Cache payload mismatch: {record.payload}")
        return 1

    print(f"[OK] Read cache record: source={record.source}, kind={record.kind}, symbol={record.symbol}")

    if cache.is_stale(record, max_age_seconds=3600):
        print("[FAIL] Fresh cache record was marked stale")
        return 1

    print("[OK] Fresh cache record is not stale")

    time.sleep(1)
    if not cache.is_stale(record, max_age_seconds=0):
        print("[FAIL] Cache record should be stale with max_age_seconds=0")
        return 1

    print("[OK] Stale cache detection works")

    ohlcv_path = cache.write(
        source="kraken",
        kind="ohlcv",
        symbol="BTC/USD",
        extra="60m",
        payload={"candles": [[1, "1", "2", "0.5", "1.5", "10", "100"]]},
    )
    print(f"[OK] Wrote OHLCV cache file: {ohlcv_path.relative_to(PROJECT_ROOT)}")

    cache.clear()
    missing = cache.read(source="kraken", kind="ticker", symbol="BTC/USD")
    if missing is not None:
        print("[FAIL] Cache clear did not remove ticker record")
        return 1

    print("[OK] Cache clear works")
    print("Market data cache validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
