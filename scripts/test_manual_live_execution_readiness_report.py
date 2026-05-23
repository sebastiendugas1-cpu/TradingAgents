"""
Validation script for Slice 14D.

This script validates the manual live execution readiness report.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path

from tradingagents.execution.manual_live_execution_readiness import (
    ManualLiveExecutionReadinessError,
    assert_manual_live_execution_ready,
    build_manual_live_execution_readiness_report,
)
from tradingagents.execution.safety_config import (
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
)


def expect_readiness_error(label: str, func) -> None:
    try:
        func()
    except ManualLiveExecutionReadinessError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualLiveExecutionReadinessError")


def test_default_readiness_report_is_blocked() -> None:
    report = build_manual_live_execution_readiness_report()

    assert report.live_execution_blocked is True
    assert report.theoretically_ready is False
    assert report.secrets_included is False
    assert report.execution_endpoint_called is False

    component_names = {component.name for component in report.components}
    assert "safety_config" in component_names
    assert "live_execution_preflight" in component_names
    assert "kraken_live_execution_client" in component_names
    assert "risk_gate" in component_names
    assert "manual_approval" in component_names

    print("[OK] default readiness report is blocked")


def test_default_assert_readiness_blocks() -> None:
    expect_readiness_error(
        "default assert readiness blocks live execution",
        lambda: assert_manual_live_execution_ready(),
    )


def test_permissive_config_still_blocked_by_disabled_client() -> None:
    config = LiveExecutionSafetyConfig(
        live_trading_enabled=True,
        kill_switch=False,
        max_live_trade_value=Decimal("10"),
        explicit_confirmation=LIVE_TRADING_CONFIRMATION_PHRASE,
    )

    report = build_manual_live_execution_readiness_report(
        config=config,
        risk_gate_ready=True,
        manual_approval_ready=True,
    )

    assert report.live_execution_blocked is True
    assert report.theoretically_ready is False

    client_component = next(
        component
        for component in report.components
        if component.name == "kraken_live_execution_client"
    )

    assert client_component.blocked is True
    assert client_component.status == "blocked_by_design"

    print("[OK] permissive config remains blocked by disabled client skeleton")


def test_risk_and_manual_approval_readiness_are_reported() -> None:
    report = build_manual_live_execution_readiness_report(
        risk_gate_ready=False,
        manual_approval_ready=False,
    )

    risk_component = next(
        component for component in report.components if component.name == "risk_gate"
    )
    approval_component = next(
        component for component in report.components if component.name == "manual_approval"
    )

    assert risk_component.blocked is True
    assert approval_component.blocked is True

    report_ready_inputs = build_manual_live_execution_readiness_report(
        risk_gate_ready=True,
        manual_approval_ready=True,
    )

    ready_risk_component = next(
        component
        for component in report_ready_inputs.components
        if component.name == "risk_gate"
    )
    ready_approval_component = next(
        component
        for component in report_ready_inputs.components
        if component.name == "manual_approval"
    )

    assert ready_risk_component.blocked is False
    assert ready_approval_component.blocked is False

    print("[OK] risk gate and manual approval readiness are reported")


def test_safe_report_excludes_secrets() -> None:
    report = build_manual_live_execution_readiness_report(
        env={
            "KRAKEN_API_KEY": "should_not_print",
            "KRAKEN_API_SECRET": "should_not_print",
            "LIVE_TRADING_ENABLED": "false",
            "KILL_SWITCH": "true",
            "MAX_LIVE_TRADE_VALUE": "0",
        }
    )

    safe = report.safe_report()
    safe_text = str(safe).lower()

    assert safe["secrets_included"] is False
    assert safe["execution_endpoint_called"] is False

    forbidden_terms = [
        "should_not_print",
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
    ]

    for term in forbidden_terms:
        assert term not in safe_text

    print("[OK] readiness report is safe to log")


def test_dangerous_environment_blocks_readiness() -> None:
    report = build_manual_live_execution_readiness_report(
        env={
            "ENABLE_WITHDRAWAL_FEATURE": "true",
            "LIVE_TRADING_ENABLED": "false",
            "KILL_SWITCH": "true",
            "MAX_LIVE_TRADE_VALUE": "0",
        }
    )

    assert report.live_execution_blocked is True

    preflight_component = next(
        component
        for component in report.components
        if component.name == "live_execution_preflight"
    )

    assert preflight_component.blocked is True
    assert any("Dangerous environment/configuration term" in reason for reason in preflight_component.reasons)

    print("[OK] dangerous environment terms keep readiness blocked")


def test_readiness_source_contains_no_kraken_execution_endpoint_names() -> None:
    source_path = Path("tradingagents/execution/manual_live_execution_readiness.py")
    source = source_path.read_text(encoding="utf-8").lower()

    forbidden_terms = [
        "addorder",
        "cancelorder",
        "withdraw",
        "deposit",
        "tradebalance",
        "ledgers",
    ]

    for term in forbidden_terms:
        assert term not in source

    print("[OK] readiness source contains no Kraken execution endpoint names")


def main() -> None:
    print("Slice 14D validation: Manual Live Execution Readiness Report")
    print("=" * 80)

    test_default_readiness_report_is_blocked()
    test_default_assert_readiness_blocks()
    test_permissive_config_still_blocked_by_disabled_client()
    test_risk_and_manual_approval_readiness_are_reported()
    test_safe_report_excludes_secrets()
    test_dangerous_environment_blocks_readiness()
    test_readiness_source_contains_no_kraken_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 14D manual live execution readiness report validation passed.")
    print("[PASS] Default readiness remains blocked.")
    print("[PASS] No Kraken execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
