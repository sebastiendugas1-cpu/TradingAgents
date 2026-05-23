"""
Validation script for Slice 14A.

This script confirms that live execution safety config is restrictive by default.

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

from decimal import Decimal

from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


def expect_safety_error(label: str, func) -> None:
    try:
        func()
    except SafetyConfigError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected SafetyConfigError")


def test_default_config_is_safe() -> None:
    config = LiveExecutionSafetyConfig.default()

    assert config.live_trading_enabled is False
    assert config.kill_switch is True
    assert config.max_live_trade_value == Decimal("0")
    assert config.explicit_confirmation == ""

    config.validate_config_only()

    expect_safety_error(
        "default config blocks future live execution",
        lambda: config.assert_live_execution_allowed("safe dry run preview only"),
    )


def test_env_defaults_are_safe_when_missing() -> None:
    config = LiveExecutionSafetyConfig.from_env({})

    assert config.live_trading_enabled is False
    assert config.kill_switch is True
    assert config.max_live_trade_value == Decimal("0")
    assert config.explicit_confirmation == ""

    config.validate_config_only()


def test_unsafe_enabled_with_zero_value_is_rejected() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "0",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )

    expect_safety_error(
        "live enabled with zero max value is rejected",
        config.validate_config_only,
    )


def test_missing_confirmation_blocks_live_execution() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
        }
    )

    config.validate_config_only()

    expect_safety_error(
        "missing explicit confirmation blocks live execution",
        lambda: config.assert_live_execution_allowed("safe dry run preview only"),
    )


def test_kill_switch_blocks_even_with_other_live_settings() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "true",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )

    config.validate_config_only()

    expect_safety_error(
        "kill switch blocks live execution",
        lambda: config.assert_live_execution_allowed("safe dry run preview only"),
    )


def test_dangerous_permission_terms_are_rejected() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_CONFIRMATION: "please enable withdrawal permission",
        }
    )

    expect_safety_error(
        "dangerous permission terms are rejected",
        config.validate_config_only,
    )


def test_dangerous_executable_action_terms_are_rejected() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )

    config.validate_config_only()

    dangerous_actions = [
        "AddOrder",
        "CancelOrder",
        "place order",
        "submit order",
        "execute order",
        "market buy",
        "market sell",
        "withdraw",
        "funding",
        "deposit",
        "transfer",
    ]

    for action in dangerous_actions:
        expect_safety_error(
            f"dangerous executable action term rejected: {action}",
            lambda action=action: config.assert_live_execution_allowed(action),
        )


def test_invalid_env_values_are_rejected() -> None:
    expect_safety_error(
        "invalid boolean rejected",
        lambda: LiveExecutionSafetyConfig.from_env(
            {
                ENV_LIVE_TRADING_ENABLED: "maybe",
            }
        ),
    )

    expect_safety_error(
        "negative max live trade value rejected",
        lambda: LiveExecutionSafetyConfig.from_env(
            {
                ENV_MAX_LIVE_TRADE_VALUE: "-1",
            }
        ),
    )

    expect_safety_error(
        "non-numeric max live trade value rejected",
        lambda: LiveExecutionSafetyConfig.from_env(
            {
                ENV_MAX_LIVE_TRADE_VALUE: "abc",
            }
        ),
    )


def test_safe_report_excludes_secrets() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "false",
            ENV_KILL_SWITCH: "true",
            ENV_MAX_LIVE_TRADE_VALUE: "0",
        }
    )

    report = config.safe_report()
    report_text = str(report).lower()

    assert report["live_trading_enabled"] is False
    assert report["kill_switch"] is True
    assert report["max_live_trade_value"] == "0"
    assert report["explicit_confirmation_present"] is False
    assert report["live_execution_allowed_by_default"] is False
    assert report["secrets_included"] is False

    forbidden_report_terms = [
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "token",
    ]

    for term in forbidden_report_terms:
        assert term not in report_text

    print("[OK] config report is safe to log")


def main() -> None:
    print("Slice 14A validation: Live Trading Kill Switch and Execution Safety Config")
    print("=" * 80)

    test_default_config_is_safe()
    test_env_defaults_are_safe_when_missing()
    test_unsafe_enabled_with_zero_value_is_rejected()
    test_missing_confirmation_blocks_live_execution()
    test_kill_switch_blocks_even_with_other_live_settings()
    test_dangerous_permission_terms_are_rejected()
    test_dangerous_executable_action_terms_are_rejected()
    test_invalid_env_values_are_rejected()
    test_safe_report_excludes_secrets()

    print("=" * 80)
    print("[PASS] Slice 14A safety config validation passed.")
    print("[PASS] No live order placement or cancellation code was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
