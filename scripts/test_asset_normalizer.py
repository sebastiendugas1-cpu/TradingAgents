# ============================ Test Asset Normalizer ============================
"""
Lightweight validation script for Slice 3.

Run:
    python scripts/test_asset_normalizer.py
"""

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.assets import AssetNormalizationError, AssetType, normalize_asset_symbol


TEST_CASES = [
    ("BTC/USD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("btc-usd", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("BTCUSD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("XBT/USD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("ETHCAD", "ETH/CAD", AssetType.CRYPTO, "ETH", "CAD", None),
    ("KRAKEN:BTCUSD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", "KRAKEN"),
    ("SOL", "SOL/USD", AssetType.CRYPTO, "SOL", "USD", None),
    ("AAPL", "AAPL", AssetType.TRADITIONAL, "AAPL", None, None),
    ("SPY", "SPY", AssetType.TRADITIONAL, "SPY", None, None),
    ("NASDAQ:AAPL", "AAPL", AssetType.TRADITIONAL, "AAPL", None, "NASDAQ"),
]

INVALID_CASES = [
    "",
    "   ",
    "BTC//USD",
    "???",
]


def main() -> int:
    print("Running Slice 3 asset normalizer validation...")

    passed = 0
    failed = 0

    for raw, expected_normalized, expected_type, expected_base, expected_quote, expected_venue in TEST_CASES:
        try:
            result = normalize_asset_symbol(raw)
        except Exception as exc:
            failed += 1
            print(f"[FAIL] {raw!r}: unexpected exception: {exc}")
            continue

        checks = [
            result.normalized == expected_normalized,
            result.asset_type == expected_type,
            result.base == expected_base,
            result.quote == expected_quote,
            result.venue_prefix == expected_venue,
        ]

        if all(checks):
            passed += 1
            print(f"[OK]   {raw!r} -> {result.as_dict()}")
        else:
            failed += 1
            print(f"[FAIL] {raw!r} -> {result.as_dict()}")
            print(
                "       expected:",
                {
                    "normalized": expected_normalized,
                    "asset_type": expected_type.value,
                    "base": expected_base,
                    "quote": expected_quote,
                    "venue_prefix": expected_venue,
                },
            )

    for raw in INVALID_CASES:
        try:
            result = normalize_asset_symbol(raw)
        except AssetNormalizationError:
            passed += 1
            print(f"[OK]   invalid {raw!r} rejected")
        except Exception as exc:
            failed += 1
            print(f"[FAIL] invalid {raw!r}: wrong exception: {exc}")
        else:
            failed += 1
            print(f"[FAIL] invalid {raw!r}: unexpectedly normalized as {result.as_dict()}")

    print()
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")

    if failed:
        print("Asset normalizer validation failed.")
        return 1

    print("Asset normalizer validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

