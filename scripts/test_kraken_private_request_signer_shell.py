"""
Validation script for Slice 21A.

This validates the disabled Kraken private request signer shell.

It does not:
- use API secrets
- read environment secrets
- generate a nonce
- compute HMAC signatures
- compute hashlib digests for signing
- sign private requests
- send network traffic
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.kraken_private_request_signer_shell import (
    KrakenPrivateRequestSignerShell,
    KrakenPrivateRequestSignerShellConfig,
    KrakenPrivateRequestSignerShellError,
    KrakenPrivateRequestSignerShellStatus,
    KrakenPrivateSigningPreviewRequest,
    assert_kraken_private_request_signer_shell_report_is_safe,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)


def make_request() -> KrakenPrivateSigningPreviewRequest:
    return KrakenPrivateSigningPreviewRequest(
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
        metadata={"source": "slice_21a_test"},
    )


def test_signer_capabilities_are_disabled() -> None:
    signer = KrakenPrivateRequestSignerShell()
    report = signer.safe_report()
    capabilities = report["capabilities"]

    assert report["enabled"] is False
    assert report["dry_run_only"] is True
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False

    assert capabilities["can_load_secret_material"] is False
    assert capabilities["can_generate_nonce"] is False
    assert capabilities["can_generate_signature"] is False
    assert capabilities["can_sign_private_requests"] is False
    assert capabilities["can_send_network_requests"] is False
    assert capabilities["can_call_private_endpoints"] is False

    assert signer.secret_material_loaded is False
    assert signer.nonce_generated is False
    assert signer.signature_generated is False
    assert signer.network_call_made is False
    assert signer.private_endpoint_called is False

    assert_kraken_private_request_signer_shell_report_is_safe(report)

    print("[OK] private request signer shell capabilities are disabled")


def test_preview_sign_private_request_blocks() -> None:
    signer = KrakenPrivateRequestSignerShell()
    result = signer.preview_sign_private_request(make_request())
    report = result.safe_report()

    assert result.status == KrakenPrivateRequestSignerShellStatus.BLOCKED
    assert report["blocked"] is True
    assert report["operation"] == "preview_sign_private_request"
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False

    request_preview = report["request_preview"]
    assert request_preview["signed"] is False
    assert request_preview["nonce_generated"] is False
    assert request_preview["signature_generated"] is False
    assert request_preview["secret_material_loaded"] is False
    assert request_preview["sent"] is False

    assert signer.secret_material_loaded is False
    assert signer.nonce_generated is False
    assert signer.signature_generated is False
    assert signer.network_call_made is False
    assert signer.private_endpoint_called is False

    assert any("disabled in Slice 21A" in reason for reason in result.reasons)

    assert_kraken_private_request_signer_shell_report_is_safe(report)

    print("[OK] preview sign private request blocks")


def test_theoretical_ready_policy_still_blocks() -> None:
    signer = KrakenPrivateRequestSignerShell(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    result = signer.preview_sign_private_request(make_request())
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert any("disabled in Slice 21A" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks signer shell")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenPrivateRequestSignerShellError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenPrivateRequestSignerShellError")


def test_invalid_inputs_are_rejected() -> None:
    expect_error(
        "secret-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_secret_material=True,
            )
        ),
    )

    expect_error(
        "nonce-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_nonce_generation=True,
            )
        ),
    )

    expect_error(
        "signature-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_signature_generation=True,
            )
        ),
    )

    expect_error(
        "private-endpoint-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )

    expect_error(
        "missing method name rejected",
        lambda: KrakenPrivateRequestSignerShell().preview_sign_private_request(
            KrakenPrivateSigningPreviewRequest(
                method_name="",
                path_name="private_order_preview_path",
            )
        ),
    )

    expect_error(
        "secret-like payload rejected",
        lambda: KrakenPrivateRequestSignerShell().preview_sign_private_request(
            KrakenPrivateSigningPreviewRequest(
                method_name="private_order_preview",
                path_name="private_order_preview_path",
                payload_preview={"api_secret": "not-allowed"},
            )
        ),
    )

    expect_error(
        "wrong request type rejected",
        lambda: KrakenPrivateRequestSignerShell().preview_sign_private_request(
            object(),  # type: ignore[arg-type]
        ),
    )


def test_source_contains_no_signing_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_request_signer_shell.py"
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

    print("[OK] private request signer shell source contains no signing/network/private endpoint calls")


def main() -> None:
    print("Slice 21A validation: Disabled Kraken Private Request Signer Shell")
    print("=" * 80)

    test_signer_capabilities_are_disabled()
    test_preview_sign_private_request_blocks()
    test_theoretical_ready_policy_still_blocks()
    test_invalid_inputs_are_rejected()
    test_source_contains_no_signing_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 21A disabled Kraken private request signer shell validation passed.")
    print("[PASS] Private signer shell remains disabled and blocked.")
    print("[PASS] No secret material usage was introduced.")
    print("[PASS] No nonce or signature generation was introduced.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
