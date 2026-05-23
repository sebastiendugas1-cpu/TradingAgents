"""
Validation script for Slice 20A.

This validates the disabled Kraken private transport shell.

It does not:
- create a requests/http session
- send network traffic
- sign private requests
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.kraken_private_transport_shell import (
    KrakenPrivateTransportPreviewRequest,
    KrakenPrivateTransportShell,
    KrakenPrivateTransportShellConfig,
    KrakenPrivateTransportShellError,
    KrakenPrivateTransportShellStatus,
    assert_kraken_private_transport_shell_report_is_safe,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)


def make_request() -> KrakenPrivateTransportPreviewRequest:
    return KrakenPrivateTransportPreviewRequest(
        method_name="private_order_preview",
        path_name="private_order_preview_path",
        payload_preview={
            "pair": "XBT/CAD",
            "type": "buy",
            "ordertype": "limit",
            "volume": "0.000085168",
            "price": "100000",
            "validate": True,
        },
        metadata={"source": "slice_20a_test"},
    )


def test_transport_capabilities_are_disabled() -> None:
    transport = KrakenPrivateTransportShell()
    report = transport.safe_report()
    capabilities = report["capabilities"]

    assert report["enabled"] is False
    assert report["dry_run_only"] is True
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert capabilities["can_sign_private_requests"] is False
    assert capabilities["can_send_network_requests"] is False
    assert capabilities["can_call_private_endpoints"] is False
    assert capabilities["network_calls_enabled"] is False
    assert capabilities["private_endpoint_calls_enabled"] is False

    assert_kraken_private_transport_shell_report_is_safe(report)

    print("[OK] private transport shell capabilities are disabled")


def test_preview_private_request_blocks() -> None:
    transport = KrakenPrivateTransportShell()
    result = transport.preview_private_request(make_request())
    report = result.safe_report()

    assert result.status == KrakenPrivateTransportShellStatus.BLOCKED
    assert report["blocked"] is True
    assert report["operation"] == "preview_private_request"
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert report["request_preview"]["sent"] is False
    assert report["request_preview"]["signed"] is False
    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False
    assert any("disabled in Slice 20A" in reason for reason in result.reasons)

    assert_kraken_private_transport_shell_report_is_safe(report)

    print("[OK] preview private request blocks")


def test_theoretical_ready_policy_still_blocks() -> None:
    transport = KrakenPrivateTransportShell(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    result = transport.preview_private_request(make_request())
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False
    assert any("disabled in Slice 20A" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks transport shell")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenPrivateTransportShellError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenPrivateTransportShellError")


def test_invalid_inputs_are_rejected() -> None:
    expect_error(
        "network-capable config rejected",
        lambda: KrakenPrivateTransportShell(
            config=KrakenPrivateTransportShellConfig(
                allow_network_calls=True,
            )
        ),
    )

    expect_error(
        "private-endpoint-capable config rejected",
        lambda: KrakenPrivateTransportShell(
            config=KrakenPrivateTransportShellConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )

    expect_error(
        "missing method name rejected",
        lambda: KrakenPrivateTransportShell().preview_private_request(
            KrakenPrivateTransportPreviewRequest(
                method_name="",
                path_name="private_order_preview_path",
            )
        ),
    )

    expect_error(
        "wrong request type rejected",
        lambda: KrakenPrivateTransportShell().preview_private_request(
            object(),  # type: ignore[arg-type]
        ),
    )


def test_source_contains_no_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_transport_shell.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "requests.get(",
        "requests.post(",
        "requests.Session(",
        "httpx.get(",
        "httpx.post(",
        "httpx.Client(",
        "urllib.request",
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

    print("[OK] private transport shell source contains no network/private endpoint calls")


def main() -> None:
    print("Slice 20A validation: Disabled Kraken Private Transport Shell")
    print("=" * 80)

    test_transport_capabilities_are_disabled()
    test_preview_private_request_blocks()
    test_theoretical_ready_policy_still_blocks()
    test_invalid_inputs_are_rejected()
    test_source_contains_no_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 20A disabled Kraken private transport shell validation passed.")
    print("[PASS] Private transport shell remains disabled and blocked.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()


