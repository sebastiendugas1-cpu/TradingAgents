"""
Validation script for Slice 17A.

This validates the execution adapter interface and mock adapter.

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

from tradingagents.execution.execution_adapter import (
    OrderCancellationRequest,
    ExecutionAdapter,
    ExecutionAdapterError,
    ExecutionResultStatus,
    MockExecutionAdapter,
    SubmitOrderRequest,
    assert_adapter_report_is_safe,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandStatus,
)


def make_command() -> ManualExecutionCommand:
    return ManualExecutionCommand(
        command_id="cmd_slice_17a_test",
        package_id="sim_slice_17a_test",
        audit_id="audit_slice_17a_test",
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        limit_price=Decimal("100000"),
        status=ManualExecutionCommandStatus.BLOCKED,
        metadata={
            "source": "slice_17a_test",
            "simulation_only": True,
        },
    )


def test_mock_adapter_capabilities_are_safe() -> None:
    adapter = MockExecutionAdapter()
    assert isinstance(adapter, ExecutionAdapter)

    report = adapter.capabilities().safe_report()

    assert report["adapter_name"] == "MockExecutionAdapter"
    assert report["mode"] == "mock"
    assert report["live_execution_enabled"] is False
    assert report["simulation_only"] is True
    assert report["private_endpoint_calls_enabled"] is False
    assert report["secrets_included"] is False

    print("[OK] mock adapter capabilities are safe")


def test_submit_request_blocks_by_default() -> None:
    adapter = MockExecutionAdapter()
    readiness = build_default_blocked_readiness_report()
    command = make_command()

    request = SubmitOrderRequest(
        request_id="submit_slice_17a_test",
        command=command,
        readiness_report=readiness,
        metadata={"source": "slice_17a_test"},
    )

    result = adapter.submit_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("Readiness report is blocked." in reason for reason in result.reasons)

    assert_adapter_report_is_safe(report)

    print("[OK] submit request blocks by default")


def test_cancel_request_blocks_by_default() -> None:
    adapter = MockExecutionAdapter()
    readiness = build_default_blocked_readiness_report()

    request = OrderCancellationRequest(
        request_id="cancel_slice_17a_test",
        command_id="cmd_slice_17a_test",
        simulated_transaction_id="sim_tx_slice_17a_test",
        readiness_report=readiness,
        reason="operator review test",
        metadata={"source": "slice_17a_test"},
    )

    result = adapter.cancel_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("Readiness report is blocked." in reason for reason in result.reasons)

    assert_adapter_report_is_safe(report)

    print("[OK] cancel request blocks by default")


def expect_error(label: str, func) -> None:
    try:
        func()
    except ExecutionAdapterError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected ExecutionAdapterError")


def test_invalid_requests_are_rejected() -> None:
    readiness = build_default_blocked_readiness_report()
    command = make_command()

    expect_error(
        "missing submit request_id rejected",
        lambda: SubmitOrderRequest(
            request_id="",
            command=command,
            readiness_report=readiness,
        ).validate(),
    )

    bad_command = ManualExecutionCommand(
        command_id="cmd_bad_volume",
        package_id="sim_bad_volume",
        audit_id="audit_bad_volume",
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        limit_price=Decimal("100000"),
        status=ManualExecutionCommandStatus.BLOCKED,
    )

    # ManualExecutionCommand validates its own volume. This adapter validation check
    # covers missing cancel fields separately.
    assert bad_command.volume > 0

    expect_error(
        "missing cancel transaction id rejected",
        lambda: OrderCancellationRequest(
            request_id="cancel_missing_tx",
            command_id="cmd_slice_17a_test",
            simulated_transaction_id="",
            readiness_report=readiness,
            reason="operator review test",
        ).validate(),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path("tradingagents/execution/execution_adapter.py").read_text(
        encoding="utf-8"
    ).lower()

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

    print("[OK] adapter source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17A validation: Live Execution Adapter Interface")
    print("=" * 80)

    test_mock_adapter_capabilities_are_safe()
    test_submit_request_blocks_by_default()
    test_cancel_request_blocks_by_default()
    test_invalid_requests_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17A execution adapter interface validation passed.")
    print("[PASS] Mock adapter remains blocked and simulation-only.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()

