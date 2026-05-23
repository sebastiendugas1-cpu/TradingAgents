# ============================ Slice 12A Validation - Kraken Read-Only Config ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken import (  # noqa: E402
    KrakenConfigError,
    load_kraken_readonly_config,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def assert_raises(expected_error, fn, label: str) -> None:
    try:
        fn()
    except expected_error:
        print(f"[OK] {label}")
        return

    raise AssertionError(f"{label}: expected {expected_error.__name__}")


def main() -> int:
    print("Running Slice 12A Kraken read-only config validation...")

    empty_config = load_kraken_readonly_config({})
    assert_equal(empty_config.enabled, False, "empty config disabled")
    assert_equal(empty_config.has_api_key, False, "empty config has no key")
    assert_equal(empty_config.is_read_only_safe, False, "empty config is not active safe config")

    safe_env = {
        "KRAKEN_API_KEY": "fake-key-for-validation-only",
        "KRAKEN_API_SECRET": "fake-secret-for-validation-only",
        "KRAKEN_TRADING_ENABLED": "false",
        "KRAKEN_WITHDRAWALS_ENABLED": "false",
        "KRAKEN_FUNDING_ENABLED": "false",
        "KRAKEN_ALLOWED_PERMISSIONS": "balances, open_orders, trade_history",
    }

    safe_config = load_kraken_readonly_config(safe_env)
    assert_equal(safe_config.enabled, True, "safe config enabled")
    assert_equal(safe_config.has_api_key, True, "safe config has key")
    assert_equal(safe_config.has_api_secret, True, "safe config has secret")
    assert_equal(safe_config.trading_enabled, False, "trading disabled")
    assert_equal(safe_config.withdrawals_enabled, False, "withdrawals disabled")
    assert_equal(safe_config.funding_enabled, False, "funding disabled")
    assert_true(safe_config.is_read_only_safe, "safe config is read-only safe")

    safe_dict = safe_config.to_dict()
    assert_true("fake-key" not in str(safe_dict), "safe dict does not reveal key")
    assert_true("fake-secret" not in str(safe_dict), "safe dict does not reveal secret")

    assert_raises(
        KrakenConfigError,
        lambda: load_kraken_readonly_config(
            {
                **safe_env,
                "KRAKEN_TRADING_ENABLED": "true",
            }
        ),
        "trading flag rejected",
    )

    assert_raises(
        KrakenConfigError,
        lambda: load_kraken_readonly_config(
            {
                **safe_env,
                "KRAKEN_WITHDRAWALS_ENABLED": "true",
            }
        ),
        "withdrawal flag rejected",
    )

    assert_raises(
        KrakenConfigError,
        lambda: load_kraken_readonly_config(
            {
                **safe_env,
                "KRAKEN_ALLOWED_PERMISSIONS": "balances, trade, withdrawals",
            }
        ),
        "dangerous permission names rejected",
    )

    print("Kraken read-only config validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
