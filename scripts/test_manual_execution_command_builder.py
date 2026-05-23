"""
Validation script for Slice 15E.

This script validates that the manual execution command builder connects:
- simulation package
- audit log
- command model

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require funding, withdrawal, or trading permissions
"""

from __future__ import annotations

import inspect
import tempfile
from pathlib import Path

from tradingagents.execution.manual_execution_command_builder import (
    ManualExecutionCommandBuilderError,
    assert_builder_result_cannot_execute,
    build_manual_execution_command_from_order_intent,
)


def expect_builder_error(label: str, func) -> None:
    try:
        func()
    except ManualExecutionCommandBuilderError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualExecutionCommandBuilderError")


def test_builder_creates_blocked_command_and_audit_record() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        result = build_manual_execution_command_from_order_intent(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_15e_test"},
        )

        assert result.package_id
        assert result.audit_id
        assert result.command_id
        assert result.blocked is True
        assert result.final_status == "simulation_command_blocked_from_live_execution"
        assert result.command_status in {"blocked", "ready_for_review"}
        assert result.secrets_included is False
        assert result.execution_endpoint_called is False
        assert audit_path.exists()

        report = result.safe_report()
        assert report["package_id"] == result.package_id
        assert report["audit_id"] == result.audit_id
        assert report["command_id"] == result.command_id
        assert report["blocked"] is True
        assert report["secrets_included"] is False
        assert report["execution_endpoint_called"] is False

    print("[OK] builder creates blocked command linked to audit record")


def test_permissive_env_still_builds_non_executable_command() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        result = build_manual_execution_command_from_order_intent(
            pair="ETH/CAD",
            side="sell",
            order_type="market",
            volume="0.01",
            audit_file_path=audit_path,
            env={
                "LIVE_TRADING_ENABLED": "true",
                "KILL_SWITCH": "false",
                "MAX_LIVE_TRADE_VALUE": "25",
                "LIVE_TRADING_CONFIRMATION": "I_UNDERSTAND_LIVE_TRADING_RISK",
            },
        )

        assert result.blocked is True
        assert result.final_status == "simulation_command_blocked_from_live_execution"

        expect_builder_error(
            "builder result remains non-executable",
            lambda: assert_builder_result_cannot_execute(result),
        )

    print("[OK] permissive env still creates non-executable command")


def test_invalid_inputs_are_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        expect_builder_error(
            "missing pair rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="",
                side="buy",
                order_type="limit",
                volume="0.1",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "invalid side rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="hold",
                order_type="limit",
                volume="0.1",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "invalid order type rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="buy",
                order_type="stop",
                volume="0.1",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "zero volume rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="buy",
                order_type="limit",
                volume="0",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "missing limit price rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="buy",
                order_type="limit",
                volume="0.1",
                limit_price=None,
                audit_file_path=audit_path,
            ),
        )


def test_sensitive_values_are_not_exposed_in_safe_report() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        result = build_manual_execution_command_from_order_intent(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={
                "api_key": "SHOULD_NOT_APPEAR",
                "nested": {"token": "SHOULD_NOT_APPEAR"},
            },
        )

        report_text = str(result.safe_report()).lower()
        assert "should_not_appear" not in report_text
        assert "api_key" not in report_text
        assert "token" not in report_text
        assert "password" not in report_text

    print("[OK] sensitive values are not exposed in builder safe report")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    import tradingagents.execution.manual_execution_command_builder as module

    source = inspect.getsource(module).lower()
    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdraw",
        "withdrawal",
        "funding",
        "deposit",
        "tradebalance",
        "ledgers",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] builder source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15E validation: Manual Execution Command Builder")
    print("=" * 80)

    test_builder_creates_blocked_command_and_audit_record()
    test_permissive_env_still_builds_non_executable_command()
    test_invalid_inputs_are_rejected()
    test_sensitive_values_are_not_exposed_in_safe_report()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15E manual execution command builder validation passed.")
    print("[PASS] Builder connects simulation package, audit record, and command model safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
