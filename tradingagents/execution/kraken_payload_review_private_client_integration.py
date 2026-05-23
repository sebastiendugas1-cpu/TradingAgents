"""
Slice 19C Kraken payload review + disabled private client shell integration.

This module connects the payload review path to the disabled Kraken private
client shell submit preview.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.kraken_private_client_shell import (
    KrakenPrivateClientShell,
    KrakenPrivateClientShellResult,
    assert_kraken_private_client_shell_report_is_safe,
)
from tradingagents.execution.kraken_order_translation_adapter_integration import (
    KrakenOrderTranslationAdapterIntegrationResult,
    build_translate_and_route_to_kraken_skeleton,
)


class KrakenPayloadReviewPrivateClientIntegrationError(ValueError):
    """Raised when payload review/private client integration is unsafe."""


@dataclass(frozen=True)
class KrakenPayloadReviewPrivateClientIntegrationResult:
    """Safe-to-log integration result."""

    integration_id: str
    payload_review_result: KrakenOrderTranslationAdapterIntegrationResult
    private_client_result: KrakenPrivateClientShellResult
    final_status: str
    blocked: bool
    execution_allowed: bool
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        payload_review_report = self.payload_review_result.safe_report()
        private_client_report = self.private_client_result.safe_report()

        assert_kraken_private_client_shell_report_is_safe(private_client_report)

        return {
            "integration_id": self.integration_id,
            "final_status": self.final_status,
            "blocked": self.blocked,
            "execution_allowed": False,
            "private_endpoint_called": False,
            "secrets_included": False,
            "command_id": payload_review_report["command_id"],
            "request_id": payload_review_report["request_id"],
            "audit_id": payload_review_report["audit_id"],
            "package_id": payload_review_report["package_id"],
            "kraken_payload": payload_review_report["translation_payload"],
            "payload_review_report": payload_review_report,
            "private_client_report": private_client_report,
        }


def build_payload_review_and_route_to_private_client_shell(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    audit_file_path: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    metadata: Mapping[str, Any] | None = None,
    private_client: KrakenPrivateClientShell | None = None,
) -> KrakenPayloadReviewPrivateClientIntegrationResult:
    """
    Build a Kraken-style validate=true payload review and route that preview
    payload into the disabled private client shell.

    No endpoint is called.
    """

    payload_review_result = build_translate_and_route_to_kraken_skeleton(
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        audit_file_path=audit_file_path,
        env=env,
        metadata={
            **dict(metadata or {}),
            "source": "slice_19c_payload_review_private_client_integration",
        },
    )

    selected_client = private_client or KrakenPrivateClientShell()
    payload = payload_review_result.translation_result.payload

    private_client_result = selected_client.submit_private_order_preview(payload)

    result = KrakenPayloadReviewPrivateClientIntegrationResult(
        integration_id=f"kraken_payload_private_client_{uuid4().hex}",
        payload_review_result=payload_review_result,
        private_client_result=private_client_result,
        final_status="kraken_payload_review_private_client_shell_blocked",
        blocked=True,
        execution_allowed=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_integration_report_is_safe(result.safe_report())

    return result


def assert_integration_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that the integration report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenPayloadReviewPrivateClientIntegrationError(
            "Integration report must not include secrets."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenPayloadReviewPrivateClientIntegrationError(
            "Integration report must not report private endpoint calls."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPayloadReviewPrivateClientIntegrationError(
            "Integration report must not allow execution."
        )

    private_client_report = dict(report.get("private_client_report") or {})
    assert_kraken_private_client_shell_report_is_safe(private_client_report)

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
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise KrakenPayloadReviewPrivateClientIntegrationError(
                f"Unsafe secret-like term detected: {term}"
            )
