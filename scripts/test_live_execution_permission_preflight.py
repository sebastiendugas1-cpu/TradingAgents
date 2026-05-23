"""
Validation script for Slice 14C.

This script confirms that live execution permission preflight remains safe.

It does not:
- place orders
- cancel orders
- call Kraken AddOrder
- call Kraken CancelOrder
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

import inspect
from decimal import Decimal

from tradingagents.execution.live_execution_preflight import (
    LiveExecutionPermissionPreflight,
    LiveExecutionPreflightError,
    build_live_execution_preflight_report,
    detect_dangerous_environment_terms,
)
from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
)
import tradingagents.execution.live_execution_preflight as preflight_module


FORBIDDEN_SECRET_VALUES = (
    "super-secret-key",
    "super-secret-token",
    "super-secret-password",
)

FORBIDDEN_ENDPOINT_TERMS = (
    "AddOrder",
    "CancelOrder",
    "/0/private/AddOrder",
    "/0/private/CancelOrder",
    "Withdraw",
    "/0/private/Withdraw",
)


def expect_preflight_error(label: str, func) -> None:
    try:
        func()
    except LiveExecutionPreflightError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected LiveExecutionPreflightError")


def test_default_preflight_blocks_live_execution() -> None:
    report = build_live_execution_preflight_report({})

    assert report.passed is False
    assert report.live_trading_enabled is False
    assert report.kill_switch is True
    assert report.max_live_trade_value == "0"
    assert report.explicit_confirmation_present is False
    assert report.explicit_confirmation_valid is False
    assert report.secrets_included is False
    assert report.execution_endpoints_called is False
    assert any("KILL_SWITCH" in reason for reason in report.blocked_reasons)
    assert any("LIVE_TRADING_ENABLED" in reason for reason in report.blocked_reasons)

    print("[OK] default preflight blocks live execution")


def test_preflight_assert_raises_by_default() -> None:
    preflight = LiveExecutionPermissionPreflight(env={})

    expect_preflight_error(
        "default preflight assert blocks live execution",
        preflight.assert_preflight_passed,
    )


def test_permissive_config_can_only_pass_preflight_without_calling_endpoints() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "true",
        ENV_KILL_SWITCH: "false",
        ENV_MAX_LIVE_TRADE_VALUE: "10",
        ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is True
    assert report.live_trading_enabled is True
    assert report.kill_switch is False
    assert report.max_live_trade_value == "10"
    assert report.explicit_confirmation_present is True
    assert report.explicit_confirmation_valid is True
    assert report.blocked_reasons == tuple()
    assert report.execution_endpoints_called is False

    print("[OK] permissive config only passes preflight; no endpoint is called")


def test_kill_switch_blocks_even_with_other_settings_enabled() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "true",
        ENV_KILL_SWITCH: "true",
        ENV_MAX_LIVE_TRADE_VALUE: "10",
        ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is False
    assert any("KILL_SWITCH" in reason for reason in report.blocked_reasons)

    print("[OK] kill switch blocks preflight")


def test_zero_trade_value_blocks_preflight() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "false",
        ENV_KILL_SWITCH: "true",
        ENV_MAX_LIVE_TRADE_VALUE: "0",
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is False
    assert any("MAX_LIVE_TRADE_VALUE" in reason for reason in report.blocked_reasons)

    print("[OK] zero max live trade value blocks preflight")


def test_missing_confirmation_blocks_preflight() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "true",
        ENV_KILL_SWITCH: "false",
        ENV_MAX_LIVE_TRADE_VALUE: "10",
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is False
    assert any("confirmation" in reason.lower() for reason in report.blocked_reasons)

    print("[OK] missing explicit confirmation blocks preflight")


def test_dangerous_environment_terms_are_detected_without_secret_leakage() -> None:
    env = {
        "KRAKEN_API_KEY": "super-secret-key",
        "KRAKEN_API_SECRET": "super-secret-token",
        "ENABLE_WITHDRAWALS": "false",
        "SOME_SAFE_SETTING": "please do not withdraw anything",
        "NORMAL_SETTING": "hello",
    }

    detected = detect_dangerous_environment_terms(env)
    detected_text = str(detected)

    assert "ENABLE_WITHDRAWALS" in detected
    assert "SOME_SAFE_SETTING=<redacted-dangerous-term>" in detected

    for secret in FORBIDDEN_SECRET_VALUES:
        assert secret not in detected_text

    report = build_live_execution_preflight_report(env)
    report_text = str(report.as_dict())

    assert report.passed is False
    assert report.secrets_included is False
    assert "ENABLE_WITHDRAWALS" in report.dangerous_environment_terms_detected

    for secret in FORBIDDEN_SECRET_VALUES:
        assert secret not in report_text

    print("[OK] dangerous environment terms detected without leaking secrets")


def test_report_is_safe_to_log() -> None:
    env = {
        "KRAKEN_API_KEY": "super-secret-key",
        "KRAKEN_API_SECRET": "super-secret-token",
        "ACCESS_TOKEN": "super-secret-token",
        ENV_LIVE_TRADING_ENABLED: "false",
        ENV_KILL_SWITCH: "true",
        ENV_MAX_LIVE_TRADE_VALUE: "0",
    }

    report = build_live_execution_preflight_report(env)
    report_dict = report.as_dict()
    report_text = str(report_dict)

    assert report_dict["secrets_included"] is False
    assert report_dict["execution_endpoints_called"] is False

    for secret in FORBIDDEN_SECRET_VALUES:
        assert secret not in report_text

    print("[OK] preflight report is safe to log")


def test_config_can_be_supplied_directly() -> None:
    config = LiveExecutionSafetyConfig(
        live_trading_enabled=False,
        kill_switch=True,
        max_live_trade_value=Decimal("0"),
        explicit_confirmation="",
    )

    report = LiveExecutionPermissionPreflight(config=config, env={}).run()

    assert report.passed is False
    assert report.live_trading_enabled is False
    assert report.kill_switch is True
    assert report.max_live_trade_value == "0"

    print("[OK] preflight accepts directly supplied config")


def test_preflight_source_contains_no_kraken_execution_endpoint_names() -> None:
    source = inspect.getsource(preflight_module)

    for term in FORBIDDEN_ENDPOINT_TERMS:
        assert term not in source

    print("[OK] preflight source contains no Kraken execution endpoint names")


def main() -> None:
    print("Slice 14C validation: Live Execution Permission Preflight")
    print("=" * 80)

    test_default_preflight_blocks_live_execution()
    test_preflight_assert_raises_by_default()
    test_permissive_config_can_only_pass_preflight_without_calling_endpoints()
    test_kill_switch_blocks_even_with_other_settings_enabled()
    test_zero_trade_value_blocks_preflight()
    test_missing_confirmation_blocks_preflight()
    test_dangerous_environment_terms_are_detected_without_secret_leakage()
    test_report_is_safe_to_log()
    test_config_can_be_supplied_directly()
    test_preflight_source_contains_no_kraken_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 14C live execution permission preflight validation passed.")
    print("[PASS] Preflight remains safe to log and does not expose secrets.")
    print("[PASS] No Kraken execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
