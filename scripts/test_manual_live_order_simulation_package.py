"""
Validation script for Slice 15A.

This validates an end-to-end manual live order simulation package.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationError,
    ManualLiveOrderSimulationInput,
    assert_report_has_no_secret_terms,
    build_manual_live_order_simulation_package,
    build_permissive_test_config,
)


def expect_simulation_error(label: str, func) -> None:
    try:
        func()
    except ManualLiveOrderSimulationError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualLiveOrderSimulationError")


def sample_limit_input() -> ManualLiveOrderSimulationInput:
    return ManualLiveOrderSimulationInput(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume="0.000085168",
        limit_price="100000",
        quote_currency="CAD",
        proposal_id="proposal-test-001",
        approval_id="approval-test-001",
        strategy_name="slice-15a-simulation",
        risk_summary="test risk summary",
        operator_note="simulation only",
    )


def test_default_package_is_blocked_and_safe() -> None:
    package = build_manual_live_order_simulation_package(sample_limit_input())
    report = package.safe_report()

    assert package.blocked is True
    assert package.simulation_only is True
    assert package.status == "blocked_simulation_only"
    assert package.safe_to_log is True
    assert package.secrets_included is False
    assert package.execution_endpoint_called is False
    assert report["execution_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["order_intent"]["pair"] == "BTC/CAD"
    assert report["order_intent"]["volume"] == "0.000085168"

    component_names = {component.name for component in package.components}
    assert "order_intent" in component_names
    assert "manual_live_execution_readiness" in component_names
    assert "kraken_dry_run_order_preview" in component_names
    assert "slice_15a_simulation_boundary" in component_names

    assert_report_has_no_secret_terms(report)
    expect_simulation_error(
        "simulation package cannot be executed",
        package.assert_not_executable,
    )

    print("[OK] default simulation package is blocked and safe")


def test_permissive_config_still_simulation_only() -> None:
    package = build_manual_live_order_simulation_package(
        sample_limit_input(),
        config=build_permissive_test_config(),
        risk_gate_ready=True,
        manual_approval_ready=True,
    )

    assert package.blocked is True
    assert package.simulation_only is True
    assert package.status == "blocked_simulation_only"
    assert any(
        component.name == "slice_15a_simulation_boundary"
        and component.status == "blocked_by_design"
        for component in package.components
    )

    print("[OK] permissive config still produces simulation-only package")


def test_bad_order_input_is_rejected_in_component() -> None:
    bad_input = ManualLiveOrderSimulationInput(
        pair="",
        side="hold",
        order_type="limit",
        volume="0",
        limit_price="",
    )

    package = build_manual_live_order_simulation_package(bad_input)

    order_component = [
        component for component in package.components if component.name == "order_intent"
    ][0]

    assert order_component.blocked is True
    assert "pair is required." in order_component.reasons
    assert "side must be buy or sell." in order_component.reasons
    assert "volume must be greater than zero." in order_component.reasons
    assert "limit_price is required for limit orders." in order_component.reasons

    print("[OK] invalid order input is captured as blocked component")


def test_dangerous_environment_keeps_package_blocked() -> None:
    package = build_manual_live_order_simulation_package(
        sample_limit_input(),
        env={"KRAKEN_WITHDRAW_PERMISSION": "true"},
    )

    readiness_component = [
        component
        for component in package.components
        if component.name == "manual_live_execution_readiness"
    ][0]

    assert readiness_component.blocked is True
    assert any("Dangerous" in reason for reason in readiness_component.reasons)
    assert package.blocked is True

    print("[OK] dangerous environment keeps simulation package blocked")


def test_report_does_not_leak_secrets() -> None:
    package = build_manual_live_order_simulation_package(
        sample_limit_input(),
        env={
            "KRAKEN_API_KEY": "SHOULD_NOT_APPEAR",
            "KRAKEN_API_SECRET": "SHOULD_NOT_APPEAR",
        },
    )

    report = package.safe_report()
    report_text = str(report)

    assert "SHOULD_NOT_APPEAR" not in report_text
    assert_report_has_no_secret_terms(report)

    print("[OK] simulation report is safe to log")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    from pathlib import Path

    source = Path(
        "tradingagents/execution/manual_live_order_simulation_package.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdrawfunds",
        "depositmethods",
        "wallettransfer",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] simulation source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15A validation: Manual Live Order Simulation Package")
    print("=" * 80)

    test_default_package_is_blocked_and_safe()
    test_permissive_config_still_simulation_only()
    test_bad_order_input_is_rejected_in_component()
    test_dangerous_environment_keeps_package_blocked()
    test_report_does_not_leak_secrets()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15A manual live order simulation package validation passed.")
    print("[PASS] End-to-end manual execution flow is represented safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
