$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 21C PRIVATE REQUEST SIGNER SHELL + TRANSPORT SHELL INTEGRATION ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$integrationPath = ".\tradingagents\execution\kraken_private_signer_transport_integration.py"
$testPath = ".\scripts\test_kraken_private_signer_transport_integration.py"

if (-not (Test-Path ".\tradingagents\execution\kraken_private_request_signer_shell.py")) {
    throw "Missing private request signer shell module from Slice 21A."
}

if (-not (Test-Path ".\tradingagents\execution\kraken_private_transport_shell.py")) {
    throw "Missing private transport shell module from Slice 20A."
}

$integrationContent = @'
"""
Slice 21C private request signer shell + private transport shell integration.

This module connects the disabled Kraken private request signer shell boundary to
the disabled Kraken private transport shell boundary.

It does not:
- load secret material
- generate a nonce
- generate a private request signature
- sign private requests
- create a requests/http session
- send network traffic
- call private execution endpoints
- place orders
- cancel orders
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.kraken_private_request_signer_shell import (
    KrakenPrivateRequestSignerShell,
    KrakenPrivateSigningPreviewRequest,
    assert_kraken_private_request_signer_shell_report_is_safe,
)
from tradingagents.execution.kraken_private_transport_shell import (
    KrakenPrivateTransportPreviewRequest,
    KrakenPrivateTransportShell,
    assert_kraken_private_transport_shell_report_is_safe,
)


class KrakenPrivateSignerTransportIntegrationError(ValueError):
    """Raised when the disabled signer-to-transport integration is unsafe."""


@dataclass(frozen=True)
class KrakenPrivateSignerTransportIntegrationResult:
    """Safe blocked result for the signer shell to transport shell integration."""

    integration_id: str
    operation: str
    status: str
    blocked: bool
    message: str
    signing_preview_result: Mapping[str, Any]
    transport_preview_result: Mapping[str, Any]
    signer_report: Mapping[str, Any]
    transport_report: Mapping[str, Any]
    execution_allowed: bool = False
    secret_material_loaded: bool = False
    nonce_generated: bool = False
    signature_generated: bool = False
    network_call_made: bool = False
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "integration_id": self.integration_id,
            "operation": self.operation,
            "status": self.status,
            "blocked": self.blocked,
            "message": self.message,
            "signing_preview_result": dict(self.signing_preview_result),
            "transport_preview_result": dict(self.transport_preview_result),
            "signer_report": dict(self.signer_report),
            "transport_report": dict(self.transport_report),
            "execution_allowed": False,
            "secret_material_loaded": False,
            "nonce_generated": False,
            "signature_generated": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "secrets_included": False,
        }


def build_private_signer_transport_preview(
    *,
    signer: KrakenPrivateRequestSignerShell | None = None,
    transport: KrakenPrivateTransportShell | None = None,
    signing_request: KrakenPrivateSigningPreviewRequest | None = None,
    payload_preview: Mapping[str, Any] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> KrakenPrivateSignerTransportIntegrationResult:
    """
    Route a safe preview through the disabled signer shell and disabled
    transport shell.

    No secret is loaded. No nonce is generated. No private request signature is
    generated. No request is sent.
    """

    signer = signer or KrakenPrivateRequestSignerShell()
    transport = transport or KrakenPrivateTransportShell()

    signing_request = signing_request or KrakenPrivateSigningPreviewRequest(
        method_name="private_signer_transport_preview",
        path_name="private_signer_transport_preview_path",
        payload_preview=dict(payload_preview or {}),
        metadata={
            "slice": "21C",
            "source": "kraken_private_signer_transport_integration",
            **dict(metadata or {}),
        },
    )

    signing_preview = signer.preview_sign_private_request(signing_request)
    signing_preview_report = signing_preview.safe_report()
    signer_report = signer.safe_report()

    assert_kraken_private_request_signer_shell_report_is_safe(signing_preview_report)
    assert_kraken_private_request_signer_shell_report_is_safe(signer_report)

    request_preview = dict(signing_preview_report.get("request_preview") or {})
    transport_request = KrakenPrivateTransportPreviewRequest(
        method_name=str(request_preview.get("method_name") or "unsigned_private_preview"),
        path_name=str(request_preview.get("path_name") or "unsigned_private_preview_path"),
        payload_preview=dict(request_preview.get("payload_preview") or {}),
        metadata={
            "slice": "21C",
            "source": "kraken_private_signer_transport_integration",
            "signer_preview_blocked": True,
            "unsigned_only": True,
            **dict(metadata or {}),
        },
    )

    transport_preview = transport.preview_private_request(transport_request)
    transport_preview_report = transport_preview.safe_report()
    transport_report = transport.safe_report()

    assert_kraken_private_transport_shell_report_is_safe(transport_preview_report)
    assert_kraken_private_transport_shell_report_is_safe(transport_report)

    result = KrakenPrivateSignerTransportIntegrationResult(
        integration_id=f"kraken_private_signer_transport_{uuid4().hex}",
        operation="private_request_signer_shell_to_transport_shell_preview",
        status="blocked",
        blocked=True,
        message=(
            "Private request signer shell to private transport shell integration "
            "is blocked and non-executable."
        ),
        signing_preview_result=signing_preview_report,
        transport_preview_result=transport_preview_report,
        signer_report=signer_report,
        transport_report=transport_report,
        execution_allowed=False,
        secret_material_loaded=False,
        nonce_generated=False,
        signature_generated=False,
        network_call_made=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_private_signer_transport_integration_report_is_safe(result.safe_report())

    return result


def assert_private_signer_transport_integration_report_is_safe(
    report: Mapping[str, Any],
) -> None:
    """Validate that the integration report is safe and non-executable."""

    bool_fields = (
        "execution_allowed",
        "secret_material_loaded",
        "nonce_generated",
        "signature_generated",
        "network_call_made",
        "private_endpoint_called",
        "secrets_included",
    )

    for field in bool_fields:
        if report.get(field) is not False:
            raise KrakenPrivateSignerTransportIntegrationError(
                f"Integration report unsafe field is not false: {field}"
            )

    nested_report_names = (
        "signing_preview_result",
        "transport_preview_result",
        "signer_report",
        "transport_report",
    )

    for nested_name in nested_report_names:
        nested = report.get(nested_name)
        if not isinstance(nested, Mapping):
            continue

        for field in bool_fields:
            if field in nested and nested.get(field) is not False:
                raise KrakenPrivateSignerTransportIntegrationError(
                    f"Nested report unsafe field is not false: {nested_name}.{field}"
                )

        request_preview = nested.get("request_preview")
        if isinstance(request_preview, Mapping):
            request_bool_fields = (
                "signed",
                "sent",
                "secret_material_loaded",
                "nonce_generated",
                "signature_generated",
                "network_call_made",
                "private_endpoint_called",
                "secrets_included",
            )
            for field in request_bool_fields:
                if field in request_preview and request_preview.get(field) is not False:
                    raise KrakenPrivateSignerTransportIntegrationError(
                        "Nested request preview unsafe field is not false: "
                        f"{nested_name}.request_preview.{field}"
                    )

    _assert_no_secret_value(report)


def _assert_no_secret_value(value: Any) -> None:
    """
    Reject obvious secret-bearing value patterns.

    This intentionally avoids rejecting safe report key names like
    signature_generated=False or nonce_generated=False.
    """

    if isinstance(value, Mapping):
        for key, item in value.items():
            key_text = str(key).lower()
            if key_text in {
                "api_key",
                "api_secret",
                "kraken_api_key",
                "kraken_api_secret",
                "private_key",
                "bearer_token",
                "access_token",
            }:
                raise KrakenPrivateSignerTransportIntegrationError(
                    f"Unsafe secret-bearing key detected: {key}"
                )

            _assert_no_secret_value(item)
        return

    if isinstance(value, (list, tuple, set)):
        for item in value:
            _assert_no_secret_value(item)
        return

    if isinstance(value, str):
        lowered = value.lower()
        forbidden_value_patterns = (
            "api_secret=",
            "api_key=",
            "kraken_api_secret=",
            "kraken_api_key=",
            "private_key=",
            "bearer ",
        )
        for pattern in forbidden_value_patterns:
            if pattern in lowered:
                raise KrakenPrivateSignerTransportIntegrationError(
                    f"Unsafe secret-bearing value pattern detected: {pattern}"
                )
'@

$testContent = @'
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
'@

Set-Content -Path $integrationPath -Value $integrationContent -Encoding UTF8
Write-Host "[WRITTEN] $integrationPath"

Set-Content -Path $testPath -Value $testContent -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

$roadmapPath = ".\docs\03_ROADMAP.md"
$controlsPath = ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md"
$decisionPath = ".\docs\11_DECISION_LOG.md"

$roadmapMarker = "Slice 21C - Private Request Signer Shell to Transport Shell Integration"
$controlsMarker = "Slice 21C - Private Request Signer Shell to Transport Shell Integration"
$decisionMarker = "Slice 21C Decision - Connect Disabled Signer Boundary to Disabled Transport Boundary"

$roadmap = Get-Content $roadmapPath -Raw
if ($roadmap -notlike "*$roadmapMarker*") {
  Add-Content -Path $roadmapPath -Encoding UTF8 -Value @"

## $roadmapMarker

Status: Implemented pending validation.

Goal:
Connect the disabled Kraken private request signer shell boundary to the disabled Kraken private transport shell boundary.

Scope:
- Create `tradingagents/execution/kraken_private_signer_transport_integration.py`.
- Create `scripts/test_kraken_private_signer_transport_integration.py`.
- Route a safe unsigned preview through the disabled signer shell and disabled transport shell.
- Preserve blocked, non-executable behavior.
- Validate that no secret, nonce, signature, network, or private endpoint behavior exists.

Safety:
- No API secret usage.
- No environment secret reading.
- No nonce generation.
- No signature generation.
- No HMAC or digest signing implementation.
- No network call.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@
  Write-Host "[UPDATED] $roadmapPath"
} else {
  Write-Host "[SKIPPED] $roadmapPath already contains Slice 21C"
}

$controls = Get-Content $controlsPath -Raw
if ($controls -notlike "*$controlsMarker*") {
  Add-Content -Path $controlsPath -Encoding UTF8 -Value @"

## $controlsMarker

A disabled integration has been added between:
- Kraken private request signer shell
- Kraken private transport shell

The integration:
- routes preview payloads only
- returns blocked safe reports
- confirms no secret material is loaded
- confirms no nonce is generated
- confirms no signature is generated
- confirms no request is signed
- confirms no request is sent
- confirms no network/private endpoint call is made
"@
  Write-Host "[UPDATED] $controlsPath"
} else {
  Write-Host "[SKIPPED] $controlsPath already contains Slice 21C"
}

$decision = Get-Content $decisionPath -Raw
if ($decision -notlike "*$decisionMarker*") {
  Add-Content -Path $decisionPath -Encoding UTF8 -Value @"

## $decisionMarker

Decision:
Add a disabled integration between the private request signer shell and private transport shell.

Reason:
Before future signing or private request work, the system needs a tested boundary proving the signer route can connect to transport while remaining blocked and non-executable.

Result:
The project now has a tested signer-to-transport integration with no secret material, no nonce generation, no signature generation, no network calls, no private endpoint calls, and no live trading.
"@
  Write-Host "[UPDATED] $decisionPath"
} else {
  Write-Host "[SKIPPED] $decisionPath already contains Slice 21C"
}

python -m py_compile $integrationPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 21C FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_private_signer_transport_integration.py", `
    ".\scripts\test_kraken_private_signer_transport_integration.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 21C script completed."
