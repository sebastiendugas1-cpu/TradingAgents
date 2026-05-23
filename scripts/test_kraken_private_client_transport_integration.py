"""
Validation script for Slice 20C.

This validates the disabled Kraken private client shell to private transport
shell integration.

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

from tradingagents.execution.kraken_private_client_transport_integration import (
    KrakenPrivateClientTransportIntegrationError,
    assert_private_client_transport_integration_report_is_safe,
    build_private_client_transport_preview,
)
from tradingagents.execution.kraken_private_transport_shell import KrakenPrivateTransportShell


def make_payload() -> dict[str, object]:
    return {
        "pair": "XBT/CAD",
        "type": "buy",
        "ordertype": "limit",
        "volume": "0.000085168",
        "price": "100000",
        "validate": True,
    }


def test_private_client_transport_preview_blocks_safely() -> None:
    result = build_private_client_transport_preview(payload_preview=make_payload())
    report = result.safe_report()

    assert report["operation"] == "private_client_shell_to_transport_shell_preview"
    assert report["status"] == "blocked"
    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False

    transport_preview = report["transport_preview_result"]
    assert transport_preview["blocked"] is True
    assert transport_preview["operation"] == "preview_private_request"
    assert transport_preview["network_call_made"] is False
    assert transport_preview["private_endpoint_called"] is False
    assert transport_preview["execution_allowed"] is False
    assert transport_preview["secrets_included"] is False
    assert transport_preview["request_preview"]["signed"] is False
    assert transport_preview["request_preview"]["sent"] is False

    assert_private_client_transport_integration_report_is_safe(report)

    print("[OK] private client transport preview blocks safely")


def test_custom_transport_still_blocks_and_records_no_calls() -> None:
    transport = KrakenPrivateTransportShell()

    result = build_private_client_transport_preview(
        transport=transport,
        payload_preview=make_payload(),
        metadata={"source": "slice_20c_test"},
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["execution_allowed"] is False
    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False

    assert_private_client_transport_integration_report_is_safe(report)

    print("[OK] custom transport still blocks and records no calls")


def test_invalid_report_is_rejected() -> None:
    unsafe_reports = [
        {"secrets_included": True},
        {"network_call_made": True},
        {"private_endpoint_called": True},
        {"execution_allowed": True},
        {"transport_preview_result": {"network_call_made": True}},
        {"transport_preview_result": {"private_endpoint_called": True}},
        {"transport_preview_result": {"execution_allowed": True}},
        {"api_key": "not-allowed"},
    ]

    for unsafe_report in unsafe_reports:
        try:
            assert_private_client_transport_integration_report_is_safe(unsafe_report)
        except KrakenPrivateClientTransportIntegrationError:
            continue

        raise AssertionError(f"Unsafe report was not rejected: {unsafe_report}")

    print("[OK] unsafe integration reports are rejected")


def test_source_contains_no_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_client_transport_integration.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "requests.get(",
        "requests.post(",
        "requests.session(",
        "httpx.get(",
        "httpx.post(",
        "httpx.client(",
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

    print("[OK] integration source contains no network/private endpoint calls")


def main() -> None:
    print("Slice 20C validation: Private Client Shell + Transport Shell Integration")
    print("=" * 80)

    test_private_client_transport_preview_blocks_safely()
    test_custom_transport_still_blocks_and_records_no_calls()
    test_invalid_report_is_rejected()
    test_source_contains_no_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 20C private client transport integration validation passed.")
    print("[PASS] Private client shell routes to disabled transport shell safely.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
