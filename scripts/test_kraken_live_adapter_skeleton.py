"""
Validation script for Slice 17F.

This validates the Kraken live adapter skeleton behind activation policy.

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
    ExecutionResultStatus,
    OrderCancellationRequest,
    SubmitOrderRequest,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.kraken_live_adapter_skeleton import (
    KrakenLiveAdapterSkeleton,
    KrakenLiveAdapterSkeletonConfig,
    KrakenLiveAdapterSkeletonError,
    assert_kraken_adapter_skeleton_report_is_safe,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandStatus,
)


def make_command() -> ManualExecutionCommand:
    return ManualExecutionCommand(
        command_id="cmd_slice_17f_test",
        package_id="sim_slice_17f_test",
        audit_id="audit_slice_17f_test",
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        limit_price=Decimal("100000"),
        status=ManualExecutionCommandStatus.BLOCKED,
        metadata={"source": "slice_17f_test"},
    )


def test_skeleton_capabilities_are_disabled() -> None:
    adapter = KrakenLiveAdapterSkeleton()
    report = adapter.capabilities().safe_report()

    assert report["adapter_name"] == "KrakenLiveAdapterSkeleton"
    assert report["mode"] == "future_live"
    assert report["can_submit_orders"] is False
    assert report["can_cancel_orders"] is False
    assert report["live_execution_enabled"] is False
    assert report["simulation_only"] is True
    assert report["private_endpoint_calls_enabled"] is False
    assert report["secrets_included"] is False

    assert_kraken_adapter_skeleton_report_is_safe(adapter.safe_report())

    print("[OK] skeleton capabilities are disabled")


def test_submit_blocks_with_default_policy() -> None:
    adapter = KrakenLiveAdapterSkeleton()
    command = make_command()
    readiness = build_default_blocked_readiness_report()

    request = SubmitOrderRequest(
        request_id="submit_slice_17f_test",
        command=command,
        readiness_report=readiness,
        metadata={"source": "slice_17f_test"},
    )

    result = adapter.submit_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("disabled in Slice 17F" in reason for reason in result.reasons)

    print("[OK] submit blocks with default policy")


def test_cancel_blocks_with_default_policy() -> None:
    adapter = KrakenLiveAdapterSkeleton()
    readiness = build_default_blocked_readiness_report()

    request = OrderCancellationRequest(
        request_id="cancel_slice_17f_test",
        command_id="cmd_slice_17f_test",
        simulated_transaction_id="sim_tx_slice_17f_test",
        readiness_report=readiness,
        reason="operator review test",
        metadata={"source": "slice_17f_test"},
    )

    result = adapter.cancel_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("disabled in Slice 17F" in reason for reason in result.reasons)

    print("[OK] cancel blocks with default policy")


def test_theoretical_ready_policy_still_blocks() -> None:
    adapter = KrakenLiveAdapterSkeleton(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    command = make_command()
    readiness = build_default_blocked_readiness_report()

    request = SubmitOrderRequest(
        request_id="submit_slice_17f_ready_policy_test",
        command=command,
        readiness_report=readiness,
    )

    result = adapter.submit_order(request)
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("disabled in Slice 17F" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks skeleton")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenLiveAdapterSkeletonError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenLiveAdapterSkeletonError")


def test_private_endpoint_enabled_config_rejected() -> None:
    expect_error(
        "private endpoint-capable config rejected",
        lambda: KrakenLiveAdapterSkeleton(
            config=KrakenLiveAdapterSkeletonConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_live_adapter_skeleton.py"
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

    print("[OK] skeleton source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17F validation: Kraken Live Adapter Skeleton Behind Activation Policy")
    print("=" * 80)

    test_skeleton_capabilities_are_disabled()
    test_submit_blocks_with_default_policy()
    test_cancel_blocks_with_default_policy()
    test_theoretical_ready_policy_still_blocks()
    test_private_endpoint_enabled_config_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17F Kraken live adapter skeleton validation passed.")
    print("[PASS] Skeleton remains disabled behind activation policy.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
