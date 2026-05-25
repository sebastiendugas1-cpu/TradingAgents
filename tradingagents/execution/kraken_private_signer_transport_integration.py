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
