"""
Validation script for Slice 19A.

This validates the disabled Kraken private client shell.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.kraken_private_client_shell import (
    KrakenPrivateClientShell,
    KrakenPrivateClientShellConfig,
    KrakenPrivateClientShellError,
    KrakenPrivateClientShellStatus,
    assert_kraken_private_client_shell_report_is_safe,
)
from tradingagents.execution.kraken_private_order_request_translator import (
    KrakenPrivateOrderPayload,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)


def make_payload() -> KrakenPrivateOrderPayload:
    return KrakenPrivateOrderPayload(
        pair="XBT/CAD",
        type="buy",
        ordertype="limit",
        volume="0.000085168",
        price="100000",
        validate=True,
        userref="cmd_slice_19a_test",
    )


def test_shell_capabilities_are_disabled() -> None:
    client = KrakenPrivateClientShell()
    report = client.safe_report()
    capabilities = report["capabilities"]

    assert report["enabled"] is False
    assert report["dry_run_only"] is True
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert capabilities["can_submit_private_order"] is False
    assert capabilities["can_cancel_private_order"] is False
    assert capabilities["can_query_private_order_status"] is False
    assert capabilities["private_endpoint_calls_enabled"] is False

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] private client shell capabilities are disabled")


def test_submit_preview_blocks() -> None:
    client = KrakenPrivateClientShell()
    result = client.submit_private_order_preview(make_payload())
    report = result.safe_report()

    assert result.status == KrakenPrivateClientShellStatus.BLOCKED
    assert report["blocked"] is True
    assert report["operation"] == "submit_private_order_preview"
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert report["payload_preview"]["pair"] == "XBT/CAD"
    assert client.private_endpoint_called is False
    assert any("disabled in Slice 19A" in reason for reason in result.reasons)

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] submit preview blocks")


def test_cancel_preview_blocks() -> None:
    client = KrakenPrivateClientShell()
    result = client.cancel_private_order_preview(
        simulated_transaction_id="sim_tx_slice_19a",
        reason="operator review test",
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["operation"] == "cancel_private_order_preview"
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert report["payload_preview"]["simulated_transaction_id"] == "sim_tx_slice_19a"
    assert client.private_endpoint_called is False

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] cancel preview blocks")


def test_status_preview_blocks() -> None:
    client = KrakenPrivateClientShell()
    result = client.query_private_order_status_preview(
        simulated_transaction_id="sim_tx_slice_19a",
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["operation"] == "query_private_order_status_preview"
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert client.private_endpoint_called is False

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] status preview blocks")


def test_theoretical_ready_policy_still_blocks() -> None:
    client = KrakenPrivateClientShell(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    result = client.submit_private_order_preview(make_payload())
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert client.private_endpoint_called is False
    assert any("disabled in Slice 19A" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks private client shell")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenPrivateClientShellError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenPrivateClientShellError")


def test_invalid_inputs_are_rejected() -> None:
    expect_error(
        "private endpoint-capable config rejected",
        lambda: KrakenPrivateClientShell(
            config=KrakenPrivateClientShellConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )

    expect_error(
        "missing simulated transaction id rejected",
        lambda: KrakenPrivateClientShell().cancel_private_order_preview(
            simulated_transaction_id="",
            reason="operator review test",
        ),
    )

    expect_error(
        "wrong payload type rejected",
        lambda: KrakenPrivateClientShell().submit_private_order_preview(
            object(),  # type: ignore[arg-type]
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_client_shell.py"
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

    print("[OK] private client shell source contains no private execution endpoint names")


def main() -> None:
    print("Slice 19A validation: Disabled Kraken Private Client Shell")
    print("=" * 80)

    test_shell_capabilities_are_disabled()
    test_submit_preview_blocks()
    test_cancel_preview_blocks()
    test_status_preview_blocks()
    test_theoretical_ready_policy_still_blocks()
    test_invalid_inputs_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 19A disabled Kraken private client shell validation passed.")
    print("[PASS] Private client shell remains disabled and blocked.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
