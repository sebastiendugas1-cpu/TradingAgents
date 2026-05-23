# ============================ Slice 12C-1 Validation - Kraken Read-Only Environment Validator ============================

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken.env_validation import (  # noqa: E402
    KrakenReadOnlyEnvironmentError,
    validate_kraken_readonly_environment,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 12C-1 Kraken read-only environment validation...")

    empty_report = validate_kraken_readonly_environment(environ={})
    assert_equal(empty_report.has_api_key, False, "empty config has no key")
    assert_equal(empty_report.has_api_secret, False, "empty config has no secret")
    assert_equal(empty_report.is_ready_for_readonly_private_client, False, "empty config is not ready")

    safe_report = validate_kraken_readonly_environment(
        environ={
            "KRAKEN_API_KEY": "dummy_key_for_validation_only",
            "KRAKEN_API_SECRET": "dummy_secret_for_validation_only",
            "KRAKEN_TRADING_ENABLED": "false",
            "KRAKEN_WITHDRAWALS_ENABLED": "false",
            "KRAKEN_FUNDING_ENABLED": "false",
        }
    )

    assert_equal(safe_report.has_api_key, True, "safe config has key")
    assert_equal(safe_report.has_api_secret, True, "safe config has secret")
    assert_equal(safe_report.trading_enabled, False, "trading disabled")
    assert_equal(safe_report.withdrawals_enabled, False, "withdrawals disabled")
    assert_equal(safe_report.funding_enabled, False, "funding disabled")
    assert_equal(safe_report.is_ready_for_readonly_private_client, True, "safe config ready for read-only client")

    safe_dict_text = str(safe_report.to_dict()).lower()
    assert_true("dummy_key" not in safe_dict_text, "report does not reveal API key")
    assert_true("dummy_secret" not in safe_dict_text, "report does not reveal API secret")

    with tempfile.TemporaryDirectory() as tmpdir:
        env_path = Path(tmpdir) / ".env"
        env_path.write_text(
            "\n".join(
                [
                    "KRAKEN_API_KEY=file_key_for_validation_only",
                    "KRAKEN_API_SECRET=file_secret_for_validation_only",
                    "KRAKEN_TRADING_ENABLED=false",
                    "KRAKEN_WITHDRAWALS_ENABLED=false",
                    "KRAKEN_FUNDING_ENABLED=false",
                ]
            ),
            encoding="utf-8",
        )

        file_report = validate_kraken_readonly_environment(env_file=env_path)
        assert_equal(file_report.has_api_key, True, ".env file key detected")
        assert_equal(file_report.has_api_secret, True, ".env file secret detected")
        assert_equal(file_report.is_ready_for_readonly_private_client, True, ".env file ready")

    try:
        validate_kraken_readonly_environment(
            environ={
                "KRAKEN_API_KEY": "dummy",
                "KRAKEN_API_SECRET": "dummy",
                "KRAKEN_TRADING_ENABLED": "true",
            }
        )
        raise AssertionError("Trading-enabled config should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] trading-enabled config rejected")

    try:
        validate_kraken_readonly_environment(
            environ={
                "KRAKEN_API_KEY": "dummy",
                "KRAKEN_API_SECRET": "dummy",
                "KRAKEN_WITHDRAWALS_ENABLED": "true",
            }
        )
        raise AssertionError("Withdrawal-enabled config should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] withdrawal-enabled config rejected")

    try:
        validate_kraken_readonly_environment(
            environ={
                "KRAKEN_API_KEY": "dummy",
                "KRAKEN_API_SECRET": "dummy",
                "KRAKEN_PERMISSION_SCOPE": "read balance trade withdraw",
            }
        )
        raise AssertionError("Dangerous permission scope should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] dangerous permission scope rejected")

    try:
        validate_kraken_readonly_environment(environ={}, require_keys=True)
        raise AssertionError("Missing required keys should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] require_keys rejects missing credentials")

    print("Kraken read-only environment validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
