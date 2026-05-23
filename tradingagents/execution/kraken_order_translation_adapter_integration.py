"""
Slice 18C Kraken order translator + adapter skeleton integration.

This module connects the Kraken-style review payload translator to the disabled
Kraken live adapter skeleton.

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

from tradingagents.execution.execution_adapter import (
    ExecutionAdapterResult,
    SubmitOrderRequest,
    assert_adapter_report_is_safe,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.kraken_live_adapter_skeleton import (
    KrakenLiveAdapterSkeleton,
    assert_kraken_adapter_skeleton_report_is_safe,
)
from tradingagents.execution.kraken_private_order_request_translator import (
    KrakenOrderTranslationResult,
    assert_translation_report_is_safe,
    translate_submit_request_to_kraken_private_order_payload,
)
from tradingagents.execution.manual_execution_command import ManualExecutionCommand
from tradingagents.execution.manual_execution_command_builder import (
    ManualExecutionCommandBuildResult,
    build_manual_execution_command_from_order_intent,
)


class KrakenOrderTranslationAdapterIntegrationError(ValueError):
    """Raised when the integration result is unsafe or invalid."""


@dataclass(frozen=True)
class KrakenOrderTranslationAdapterIntegrationResult:
    """Safe-to-log integration result."""

    integration_id: str
    builder_result: ManualExecutionCommandBuildResult
    command: ManualExecutionCommand
    submit_request: SubmitOrderRequest
    translation_result: KrakenOrderTranslationResult
    adapter_result: ExecutionAdapterResult
    final_status: str
    blocked: bool
    execution_allowed: bool
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        translation_report = self.translation_result.safe_report()
        adapter_report = self.adapter_result.safe_report()

        assert_translation_report_is_safe(translation_report)
        assert_adapter_report_is_safe(adapter_report)

        return {
            "integration_id": self.integration_id,
            "builder_id": self.builder_result.builder_id,
            "package_id": self.builder_result.package_id,
            "audit_id": self.builder_result.audit_id,
            "command_id": self.command.command_id,
            "request_id": self.submit_request.request_id,
            "adapter_result_id": self.adapter_result.result_id,
            "final_status": self.final_status,
            "blocked": self.blocked,
            "execution_allowed": False,
            "translation_payload": translation_report["payload"],
            "translation_report": translation_report,
            "adapter_report": adapter_report,
            "secrets_included": False,
            "private_endpoint_called": False,
        }


def build_translate_and_route_to_kraken_skeleton(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    audit_file_path: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    metadata: Mapping[str, Any] | None = None,
    adapter: KrakenLiveAdapterSkeleton | None = None,
) -> KrakenOrderTranslationAdapterIntegrationResult:
    """
    Build a command, translate to a Kraken-style review payload, and route through
    the disabled Kraken adapter skeleton.

    No endpoint is called.
    """

    builder_result = build_manual_execution_command_from_order_intent(
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        audit_file_path=audit_file_path,
        env=env,
        metadata={
            **dict(metadata or {}),
            "source": "slice_18c_kraken_translation_adapter_integration",
        },
    )

    command = _command_from_builder_result(
        builder_result=builder_result,
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
    )

    submit_request = SubmitOrderRequest(
        request_id=f"kraken_translate_submit_{uuid4().hex}",
        command=command,
        readiness_report=build_default_blocked_readiness_report(),
        metadata={
            "source": "slice_18c_kraken_translation_adapter_integration",
            "review_only": True,
        },
    )

    translation_result = translate_submit_request_to_kraken_private_order_payload(
        submit_request,
        userref=command.command_id,
    )

    selected_adapter = adapter or KrakenLiveAdapterSkeleton()
    assert_kraken_adapter_skeleton_report_is_safe(selected_adapter.safe_report())

    adapter_result = selected_adapter.submit_order(submit_request)

    result = KrakenOrderTranslationAdapterIntegrationResult(
        integration_id=f"kraken_translation_adapter_{uuid4().hex}",
        builder_result=builder_result,
        command=command,
        submit_request=submit_request,
        translation_result=translation_result,
        adapter_result=adapter_result,
        final_status="kraken_order_translation_adapter_integration_blocked",
        blocked=True,
        execution_allowed=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_integration_report_is_safe(result.safe_report())

    return result


def _command_from_builder_result(
    *,
    builder_result: ManualExecutionCommandBuildResult,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None,
) -> ManualExecutionCommand:
    command_report = dict(builder_result.command_report or {})

    command_id = str(command_report.get("command_id") or builder_result.command_id)
    package_id = str(command_report.get("package_id") or builder_result.package_id)
    audit_id = str(command_report.get("audit_id") or builder_result.audit_id)
    status = command_report.get("status") or builder_result.command_status

    if not command_id:
        raise KrakenOrderTranslationAdapterIntegrationError("command_id is required.")
    if not package_id:
        raise KrakenOrderTranslationAdapterIntegrationError("package_id is required.")
    if not audit_id:
        raise KrakenOrderTranslationAdapterIntegrationError("audit_id is required.")

    from tradingagents.execution.manual_execution_command import parse_status

    parsed_status = parse_status(status)

    return ManualExecutionCommand(
        command_id=command_id,
        package_id=package_id,
        audit_id=audit_id,
        pair=str(pair),
        side=str(side).lower(),
        order_type=str(order_type).lower(),
        volume=Decimal(str(volume)),
        limit_price=Decimal(str(limit_price)) if limit_price is not None else None,
        status=parsed_status,
        metadata={
            "source": "slice_18c_kraken_translation_adapter_integration",
            "review_only": True,
        },
    )


def assert_integration_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that the integration report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenOrderTranslationAdapterIntegrationError(
            "Integration report must not include secrets."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenOrderTranslationAdapterIntegrationError(
            "Integration report must not report private endpoint calls."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenOrderTranslationAdapterIntegrationError(
            "Integration report must not allow execution."
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
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise KrakenOrderTranslationAdapterIntegrationError(
                f"Unsafe secret-like term detected: {term}"
            )
