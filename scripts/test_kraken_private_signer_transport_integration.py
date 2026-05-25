"""
Validation script for Slice 21C.

This validates the disabled private request signer shell to private transport
shell integration.

It does not:
- load secret material
- generate a nonce
- generate a private request signature
- sign private requests
- create a requests/http session
- send network traffic
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.kraken_private_request_signer_shell import (
    KrakenPrivateRequestSignerShell,
    KrakenPrivateSigningPreviewRequest,
)
from tradingagents.execution.kraken_private_signer_transport_integration import (
    KrakenPrivateSignerTransportIntegrationError,
    assert_private_signer_transport_integration_report_is_safe,
    build_private_signer_transport_preview,
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


def test_signer_transport_preview_blocks_safely() -> None:
    result = build_private_signer_transport_preview(payload_preview=make_payload())
    report = result.safe_report()

    assert report["operation"] == "private_request_signer_shell_to_transport_shell_preview"
    assert report["status"] == "blocked"
    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False

    signing_preview = report["signing_preview_result"]
    assert signing_preview["blocked"] is True
    assert signing_preview["operation"] == "preview_sign_private_request"
    assert signing_preview["secret_material_loaded"] is False
    assert signing_preview["nonce_generated"] is False
    assert signing_preview["signature_generated"] is False
    assert signing_preview["network_call_made"] is False
    assert signing_preview["private_endpoint_called"] is False
    assert signing_preview["execution_allowed"] is False
    assert signing_preview["secrets_included"] is False

    signer_request_preview = signing_preview["request_preview"]
    assert signer_request_preview["signed"] is False
    assert signer_request_preview["sent"] is False
    assert signer_request_preview["secret_material_loaded"] is False
    assert signer_request_preview["nonce_generated"] is False
    assert signer_request_preview["signature_generated"] is False

    transport_preview = report["transport_preview_result"]
    assert transport_preview["blocked"] is True
    assert transport_preview["operation"] == "preview_private_request"
    assert transport_preview["network_call_made"] is False
    assert transport_preview["private_endpoint_called"] is False
    assert transport_preview["execution_allowed"] is False
    assert transport_preview["secrets_included"] is False

    transport_request_preview = transport_preview["request_preview"]
    assert transport_request_preview["signed"] is False
    assert transport_request_preview["sent"] is False

    assert_private_signer_transport_integration_report_is_safe(report)

    print("[OK] signer transport preview blocks safely")


def test_custom_signer_and_transport_still_block_and_record_no_calls() -> None:
    signer = KrakenPrivateRequestSignerShell()
    transport = KrakenPrivateTransportShell()

    result = build_private_signer_transport_preview(
        signer=signer,
        transport=transport,
        payload_preview=make_payload(),
        metadata={"source": "slice_21c_test"},
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["execution_allowed"] is False

    assert signer.secret_material_loaded is False
    assert signer.nonce_generated is False
    assert signer.signature_generated is False
    assert signer.network_call_made is False
    assert signer.private_endpoint_called is False

    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False

    assert_private_signer_transport_integration_report_is_safe(report)

    print("[OK] custom signer and transport still block and record no calls")


def test_explicit_signing_request_routes_safely() -> None:
    request = KrakenPrivateSigningPreviewRequest(
        method_name="private_signer_transport_preview",
        path_name="private_signer_transport_preview_path",
        payload_preview=make_payload(),
        metadata={"source": "slice_21c_explicit_request_test"},
    )

    result = build_private_signer_transport_preview(signing_request=request)
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["execution_allowed"] is False

    assert_private_signer_transport_integration_report_is_safe(report)

    print("[OK] explicit signing request routes safely")


def test_invalid_report_is_rejected() -> None:
    unsafe_reports = [
        {"execution_allowed": True},
        {"secret_material_loaded": True},
        {"nonce_generated": True},
        {"signature_generated": True},
        {"network_call_made": True},
        {"private_endpoint_called": True},
        {"secrets_included": True},
        {"signing_preview_result": {"signature_generated": True}},
        {"transport_preview_result": {"network_call_made": True}},
        {"signer_report": {"secret_material_loaded": True}},
        {"transport_report": {"private_endpoint_called": True}},
        {"signing_preview_result": {"request_preview": {"signed": True}}},
        {"transport_preview_result": {"request_preview": {"sent": True}}},
        {"payload": {"api_secret": "not-allowed"}},
    ]

    for unsafe_report in unsafe_reports:
        try:
            assert_private_signer_transport_integration_report_is_safe(unsafe_report)
        except KrakenPrivateSignerTransportIntegrationError:
            continue

        raise AssertionError(f"Unsafe report was not rejected: {unsafe_report}")

    print("[OK] unsafe integration reports are rejected")


def test_source_contains_no_signing_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_signer_transport_integration.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "import hmac",
        "import hashlib",
        "import base64",
        "import os",
        "hmac.",
        "hashlib.",
        "base64.",
        "os.environ",
        "time.time(",
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

    print("[OK] integration source contains no signing/network/private endpoint calls")


def main() -> None:
    print("Slice 21C validation: Private Request Signer Shell + Transport Shell Integration")
    print("=" * 80)

    test_signer_transport_preview_blocks_safely()
    test_custom_signer_and_transport_still_block_and_record_no_calls()
    test_explicit_signing_request_routes_safely()
    test_invalid_report_is_rejected()
    test_source_contains_no_signing_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 21C signer transport integration validation passed.")
    print("[PASS] Private signer shell routes to disabled transport shell safely.")
    print("[PASS] No secret material usage was introduced.")
    print("[PASS] No nonce or signature generation was introduced.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
