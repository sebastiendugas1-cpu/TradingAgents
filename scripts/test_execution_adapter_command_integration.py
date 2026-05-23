"""
Validation script for Slice 17B.

This validates the adapter + manual command builder integration.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from tradingagents.execution.execution_adapter import MockExecutionAdapter
from tradingagents.execution.execution_adapter_command_integration import (
    ExecutionAdapterCommandIntegrationError,
    assert_integration_result_is_safe,
    build_command_and_route_to_mock_adapter,
)


def test_command_builder_routes_to_mock_adapter() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "adapter_command_integration.jsonl"

        result = build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_17b_test"},
        )

        report = result.safe_report()

        assert report["adapter_name"] == "MockExecutionAdapter"
        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["secrets_included"] is False
        assert report["private_endpoint_called"] is False
        assert report["builder_id"]
        assert report["package_id"]
        assert report["audit_id"]
        assert report["command_id"]
        assert report["request_id"]
        assert report["adapter_result_id"]
        assert audit_path.exists()

        assert report["adapter_report"]["blocked"] is True
        assert report["adapter_report"]["private_endpoint_called"] is False
        assert report["adapter_report"]["secrets_included"] is False

        assert_integration_result_is_safe(result)

    print("[OK] command builder routes to mock adapter safely")


def test_permissive_mock_adapter_still_non_live() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "adapter_command_integration_permissive.jsonl"

        adapter = MockExecutionAdapter(allow_simulated_success=True)

        result = build_command_and_route_to_mock_adapter(
            pair="SOL/CAD",
            side="buy",
            order_type="limit",
            volume=Decimal("0.1"),
            limit_price=Decimal("200"),
            audit_file_path=audit_path,
            adapter=adapter,
            metadata={"source": "slice_17b_test"},
        )

        report = result.safe_report()

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert adapter.private_endpoint_called is False
        assert audit_path.exists()

        assert_integration_result_is_safe(result)

    print("[OK] permissive mock adapter remains non-live")


def expect_error(label: str, func) -> None:
    try:
        func()
    except Exception as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected failure")


def test_invalid_order_intent_fails_safely() -> None:
    expect_error(
        "invalid side rejected",
        lambda: build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="hold",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
        ),
    )

    expect_error(
        "zero volume rejected",
        lambda: build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0",
            limit_price="100000",
        ),
    )

    expect_error(
        "missing limit price rejected",
        lambda: build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price=None,
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/execution_adapter_command_integration.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdraw",
        "withdrawal",
        "deposit",
        "funding",
        "tradebalance",
        "ledgers",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] integration source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17B validation: Execution Adapter + Command Builder Integration")
    print("=" * 80)

    test_command_builder_routes_to_mock_adapter()
    test_permissive_mock_adapter_still_non_live()
    test_invalid_order_intent_fails_safely()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17B execution adapter command integration validation passed.")
    print("[PASS] Command builder routes to mock adapter safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
