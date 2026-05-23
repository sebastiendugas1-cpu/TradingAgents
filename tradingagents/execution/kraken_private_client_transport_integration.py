"""
Slice 20C private client shell + private transport shell integration.

This module connects the disabled Kraken private client shell boundary to the
disabled Kraken private transport shell boundary.

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

from dataclasses import dataclass
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.kraken_private_client_shell import KrakenPrivateClientShell
from tradingagents.execution.kraken_private_transport_shell import (
    KrakenPrivateTransportPreviewRequest,
    KrakenPrivateTransportShell,
    assert_kraken_private_transport_shell_report_is_safe,
)


class KrakenPrivateClientTransportIntegrationError(ValueError):
    """Raised when the safe disabled integration detects an unsafe result."""


@dataclass(frozen=True)
class KrakenPrivateClientTransportIntegrationResult:
    """Safe blocked result for the private client to transport integration."""

    integration_id: str
    operation: str
    status: str
    blocked: bool
    message: str
    private_client_report: Mapping[str, Any]
    transport_report: Mapping[str, Any]
    transport_preview_result: Mapping[str, Any]
    execution_allowed: bool = False
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
            "private_client_report": dict(self.private_client_report),
            "transport_report": dict(self.transport_report),
            "transport_preview_result": dict(self.transport_preview_result),
            "execution_allowed": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "secrets_included": False,
        }


def build_private_client_transport_preview(
    *,
    private_client: KrakenPrivateClientShell | None = None,
    transport: KrakenPrivateTransportShell | None = None,
    payload_preview: Mapping[str, Any] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> KrakenPrivateClientTransportIntegrationResult:
    """
    Route a safe preview from the disabled private client shell boundary into
    the disabled private transport shell boundary.

    No endpoint is called. No network call is made. No request is signed.
    """

    private_client = private_client or KrakenPrivateClientShell()
    transport = transport or KrakenPrivateTransportShell()

    private_client_report = _safe_private_client_report(private_client)

    request = KrakenPrivateTransportPreviewRequest(
        method_name="private_client_shell_submit_preview",
        path_name="private_transport_shell_preview_path",
        payload_preview=dict(payload_preview or {}),
        metadata={
            "slice": "20C",
            "source": "kraken_private_client_transport_integration",
            **dict(metadata or {}),
        },
    )

    transport_preview = transport.preview_private_request(request)
    transport_preview_report = transport_preview.safe_report()
    transport_report = transport.safe_report()

    assert_kraken_private_transport_shell_report_is_safe(transport_preview_report)
    assert_kraken_private_transport_shell_report_is_safe(transport_report)

    result = KrakenPrivateClientTransportIntegrationResult(
        integration_id=f"kraken_private_client_transport_{uuid4().hex}",
        operation="private_client_shell_to_transport_shell_preview",
        status="blocked",
        blocked=True,
        message=(
            "Private client shell to private transport shell integration is "
            "blocked and non-executable."
        ),
        private_client_report=private_client_report,
        transport_report=transport_report,
        transport_preview_result=transport_preview_report,
        execution_allowed=False,
        network_call_made=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_private_client_transport_integration_report_is_safe(result.safe_report())

    return result


def _safe_private_client_report(
    private_client: KrakenPrivateClientShell,
) -> dict[str, Any]:
    """
    Build a safe private client shell report without invoking private execution.

    The private client shell API is intentionally disabled. This helper only
    uses safe reporting/capability methods.
    """

    report: dict[str, Any] = {}

    if hasattr(private_client, "safe_report"):
        maybe_report = private_client.safe_report()
        if isinstance(maybe_report, Mapping):
            report.update(dict(maybe_report))

    if hasattr(private_client, "capabilities"):
        maybe_capabilities = private_client.capabilities()
        if isinstance(maybe_capabilities, Mapping):
            report["capabilities"] = dict(maybe_capabilities)

    report.setdefault("enabled", False)
    report.setdefault("dry_run_only", True)
    report.setdefault("blocked", True)
    report.setdefault("execution_allowed", False)
    report.setdefault("private_endpoint_called", False)
    report.setdefault("network_call_made", False)
    report.setdefault("secrets_included", False)
    report.setdefault("source", "KrakenPrivateClientShell")

    return report


def assert_private_client_transport_integration_report_is_safe(
    report: Mapping[str, Any],
) -> None:
    """Validate that the integration report is safe to log and non-executable."""

    if report.get("secrets_included") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report includes secrets."
        )

    if report.get("network_call_made") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report indicates a network call."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report indicates a private endpoint call."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report must not allow execution."
        )

    transport_preview = report.get("transport_preview_result")
    if isinstance(transport_preview, Mapping):
        if transport_preview.get("network_call_made") is not False:
            raise KrakenPrivateClientTransportIntegrationError(
                "Transport preview indicates a network call."
            )

        if transport_preview.get("private_endpoint_called") is not False:
            raise KrakenPrivateClientTransportIntegrationError(
                "Transport preview indicates a private endpoint call."
            )

        if transport_preview.get("execution_allowed") is not False:
            raise KrakenPrivateClientTransportIntegrationError(
                "Transport preview must not allow execution."
            )

    text = str(report).lower()
    forbidden_secret_terms = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "token=",
        "signature",
        "nonce",
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise KrakenPrivateClientTransportIntegrationError(
                f"Unsafe secret-like term detected: {term}"
            )
