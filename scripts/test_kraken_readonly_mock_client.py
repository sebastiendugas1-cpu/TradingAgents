# ============================ Slice 12B Validation - Kraken Read-Only Mock Client ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken import (  # noqa: E402
    KrakenReadOnlyClientError,
    KrakenReadOnlyMode,
    create_default_mock_kraken_readonly_client,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def assert_raises_readonly_error(callback, label: str) -> None:
    try:
        callback()
    except KrakenReadOnlyClientError:
        print(f"[OK] {label}")
        return

    raise AssertionError(f"{label}: expected KrakenReadOnlyClientError")


def main() -> int:
    print("Running Slice 12B Kraken read-only mock client validation...")

    client = create_default_mock_kraken_readonly_client()

    assert_equal(client.mode, KrakenReadOnlyMode.MOCK, "client mode is mock")

    balances = client.get_balances()
    open_orders = client.get_open_orders()
    trade_history = client.get_trade_history()

    assert_equal(len(balances), 2, "mock balance count")
    assert_equal(len(open_orders), 1, "mock open order count")
    assert_equal(len(trade_history), 1, "mock trade history count")

    assert_equal(balances[0].asset, "USD", "first balance asset")
    assert_true(balances[0].available > 0, "USD available balance positive")

    assert_equal(open_orders[0].pair, "BTC/USD", "mock open order pair")
    assert_equal(open_orders[0].side, "buy", "mock open order side")

    snapshot = client.get_account_snapshot()
    snapshot_dict = snapshot.to_dict()

    assert_equal(snapshot.source, "mock", "snapshot source")
    assert_equal(len(snapshot.balances), 2, "snapshot balance count")
    assert_equal(len(snapshot.open_orders), 1, "snapshot open order count")
    assert_equal(len(snapshot.trade_history), 1, "snapshot trade history count")
    assert_true("secret" not in str(snapshot_dict).lower(), "snapshot does not reveal secrets")
    assert_true("api_key" not in str(snapshot_dict).lower(), "snapshot does not reveal API key")

    assert_raises_readonly_error(lambda: client.place_order(), "place_order blocked")
    assert_raises_readonly_error(lambda: client.cancel_order(), "cancel_order blocked")
    assert_raises_readonly_error(lambda: client.withdraw(), "withdraw blocked")
    assert_raises_readonly_error(lambda: client.funding_operation(), "funding operation blocked")

    print("Kraken read-only mock client validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
