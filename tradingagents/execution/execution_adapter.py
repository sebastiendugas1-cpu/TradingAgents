"""
Slice 17A execution adapter interface.

This module defines the abstract boundary for future execution adapters.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

The only concrete adapter included here is a mock adapter for tests.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from enum import Enum
from typing import Any, Mapping, Protocol, runtime_checkable
from uuid import uuid4

from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandStatus,
)
from tradingagents.execution.manual_live_execution_readiness import (
    ManualLiveExecutionReadinessReport,
    build_manual_live_execution_readiness_report,
)


class ExecutionAdapterError(ValueError):
    """Raised when an execution adapter request is unsafe or invalid."""


class ExecutionAction(str, Enum):
    """Execution actions represented by the adapter interface."""

    SUBMIT = "submit"
    CANCEL = "cancel"


class ExecutionAdapterMode(str, Enum):
    """Adapter mode."""

    MOCK = "mock"
    DISABLED = "disabled"
    FUTURE_LIVE = "future_live"


class ExecutionResultStatus(str, Enum):
    """Execution result status."""

    BLOCKED = "blocked"
    SIMULATED = "simulated"
    REJECTED = "rejected"
    NOT_IMPLEMENTED = "not_implemented"


@dataclass(frozen=True)
class ExecutionAdapterCapabilities:
    """Safe-to-log capabilities declaration."""

    adapter_name: str
    mode: ExecutionAdapterMode
    can_submit_orders: bool
    can_cancel_orders: bool
    live_execution_enabled: bool
    requires_manual_approval: bool
    requires_risk_gate: bool
    requires_readiness_report: bool
    simulation_only: bool
    private_endpoint_calls_enabled: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "adapter_name": self.adapter_name,
            "mode": self.mode.value,
            "can_submit_orders": self.can_submit_orders,
            "can_cancel_orders": self.can_cancel_orders,
            "live_execution_enabled": self.live_execution_enabled,
            "requires_manual_approval": self.requires_manual_approval,
            "requires_risk_gate": self.requires_risk_gate,
            "requires_readiness_report": self.requires_readiness_report,
            "simulation_only": self.simulation_only,
            "private_endpoint_calls_enabled": self.private_endpoint_calls_enabled,
            "secrets_included": self.secrets_included,
        }


@dataclass(frozen=True)
class SubmitOrderRequest:
    """
    A safe request model for future order submission.

    Slice 17A only validates and routes this model through a mock adapter.
    """

    request_id: str
    command: ManualExecutionCommand
    readiness_report: ManualLiveExecutionReadinessReport
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        require_text(self.request_id, "request_id")

        if not isinstance(self.command, ManualExecutionCommand):
            raise ExecutionAdapterError("command must be a ManualExecutionCommand.")

        if not isinstance(self.readiness_report, ManualLiveExecutionReadinessReport):
            raise ExecutionAdapterError(
                "readiness_report must be a ManualLiveExecutionReadinessReport."
            )

        if self.command.status not in {
            ManualExecutionCommandStatus.BLOCKED,
            ManualExecutionCommandStatus.READY_FOR_REVIEW,
            ManualExecutionCommandStatus.APPROVED_FOR_FUTURE_EXECUTION,
        }:
            raise ExecutionAdapterError("Unsupported command status for adapter request.")

        validate_positive_decimal(self.command.volume, "volume")

        if self.command.order_type == "limit":
            if self.command.limit_price is None:
                raise ExecutionAdapterError("limit_price is required for limit requests.")
            validate_positive_decimal(self.command.limit_price, "limit_price")

    def safe_report(self) -> dict[str, Any]:
        self.validate()

        return {
            "request_id": self.request_id,
            "action": ExecutionAction.SUBMIT.value,
            "command_id": self.command.command_id,
            "package_id": self.command.package_id,
            "audit_id": self.command.audit_id,
            "pair": self.command.pair,
            "side": self.command.side,
            "order_type": self.command.order_type,
            "volume": str(self.command.volume),
            "limit_price": str(self.command.limit_price)
            if self.command.limit_price is not None
            else None,
            "command_status": self.command.status.value,
            "readiness_blocked": self.readiness_report.live_execution_blocked,
            "secrets_included": False,
            "private_endpoint_call_requested": False,
        }


@dataclass(frozen=True)
class OrderCancellationRequest:
    """
    A safe request model for future order cancellation.

    Slice 17A only validates and routes this model through a mock adapter.
    """

    request_id: str
    command_id: str
    simulated_transaction_id: str
    readiness_report: ManualLiveExecutionReadinessReport
    reason: str
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        require_text(self.request_id, "request_id")
        require_text(self.command_id, "command_id")
        require_text(self.simulated_transaction_id, "simulated_transaction_id")
        require_text(self.reason, "reason")

        if not isinstance(self.readiness_report, ManualLiveExecutionReadinessReport):
            raise ExecutionAdapterError(
                "readiness_report must be a ManualLiveExecutionReadinessReport."
            )

    def safe_report(self) -> dict[str, Any]:
        self.validate()

        return {
            "request_id": self.request_id,
            "action": ExecutionAction.CANCEL.value,
            "command_id": self.command_id,
            "simulated_transaction_id": self.simulated_transaction_id,
            "readiness_blocked": self.readiness_report.live_execution_blocked,
            "reason": self.reason,
            "secrets_included": False,
            "private_endpoint_call_requested": False,
        }


@dataclass(frozen=True)
class ExecutionAdapterResult:
    """Safe-to-log execution adapter result."""

    result_id: str
    adapter_name: str
    action: ExecutionAction
    status: ExecutionResultStatus
    blocked: bool
    simulated: bool
    request_id: str
    command_id: str
    message: str
    reasons: tuple[str, ...] = field(default_factory=tuple)
    external_transaction_id: str | None = None
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "result_id": self.result_id,
            "adapter_name": self.adapter_name,
            "action": self.action.value,
            "status": self.status.value,
            "blocked": self.blocked,
            "simulated": self.simulated,
            "request_id": self.request_id,
            "command_id": self.command_id,
            "message": self.message,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "external_transaction_id": self.external_transaction_id,
            "private_endpoint_called": self.private_endpoint_called,
            "secrets_included": self.secrets_included,
        }


@runtime_checkable
class ExecutionAdapter(Protocol):
    """Protocol for future execution adapters."""

    def capabilities(self) -> ExecutionAdapterCapabilities:
        """Return safe-to-log adapter capabilities."""
        ...

    def submit_order(self, request: SubmitOrderRequest) -> ExecutionAdapterResult:
        """Submit an order request or block it safely."""
        ...

    def cancel_order(self, request: OrderCancellationRequest) -> ExecutionAdapterResult:
        """Cancel an order request or block it safely."""
        ...


class MockExecutionAdapter:
    """
    Mock execution adapter for tests and local development.

    This adapter never calls private execution endpoints. It only returns blocked or
    simulated results.
    """

    adapter_name = "MockExecutionAdapter"

    def __init__(self, *, allow_simulated_success: bool = False) -> None:
        self.allow_simulated_success = bool(allow_simulated_success)
        self.private_endpoint_called = False

    def capabilities(self) -> ExecutionAdapterCapabilities:
        return ExecutionAdapterCapabilities(
            adapter_name=self.adapter_name,
            mode=ExecutionAdapterMode.MOCK,
            can_submit_orders=True,
            can_cancel_orders=True,
            live_execution_enabled=False,
            requires_manual_approval=True,
            requires_risk_gate=True,
            requires_readiness_report=True,
            simulation_only=True,
            private_endpoint_calls_enabled=False,
            secrets_included=False,
        )

    def submit_order(self, request: SubmitOrderRequest) -> ExecutionAdapterResult:
        request.validate()

        reasons = _blocked_reasons_from_readiness(request.readiness_report)
        reasons += (
            "Slice 17A mock adapter is non-live and cannot submit real orders.",
        )

        if self.allow_simulated_success and not request.readiness_report.live_execution_blocked:
            return ExecutionAdapterResult(
                result_id=f"exec_result_{uuid4().hex}",
                adapter_name=self.adapter_name,
                action=ExecutionAction.SUBMIT,
                status=ExecutionResultStatus.SIMULATED,
                blocked=True,
                simulated=True,
                request_id=request.request_id,
                command_id=request.command.command_id,
                message="Simulated submit accepted by mock adapter only.",
                reasons=("Mock adapter simulation only; no live execution.",),
                external_transaction_id=f"sim_tx_{uuid4().hex[:12]}",
                private_endpoint_called=False,
                secrets_included=False,
            )

        return ExecutionAdapterResult(
            result_id=f"exec_result_{uuid4().hex}",
            adapter_name=self.adapter_name,
            action=ExecutionAction.SUBMIT,
            status=ExecutionResultStatus.BLOCKED,
            blocked=True,
            simulated=False,
            request_id=request.request_id,
            command_id=request.command.command_id,
            message="Submit request blocked by mock adapter.",
            reasons=reasons,
            external_transaction_id=None,
            private_endpoint_called=False,
            secrets_included=False,
        )

    def cancel_order(self, request: OrderCancellationRequest) -> ExecutionAdapterResult:
        request.validate()

        reasons = _blocked_reasons_from_readiness(request.readiness_report)
        reasons += (
            "Slice 17A mock adapter is non-live and cannot cancel real orders.",
        )

        if self.allow_simulated_success and not request.readiness_report.live_execution_blocked:
            return ExecutionAdapterResult(
                result_id=f"exec_result_{uuid4().hex}",
                adapter_name=self.adapter_name,
                action=ExecutionAction.CANCEL,
                status=ExecutionResultStatus.SIMULATED,
                blocked=True,
                simulated=True,
                request_id=request.request_id,
                command_id=request.command_id,
                message="Simulated cancel accepted by mock adapter only.",
                reasons=("Mock adapter simulation only; no live execution.",),
                external_transaction_id=request.simulated_transaction_id,
                private_endpoint_called=False,
                secrets_included=False,
            )

        return ExecutionAdapterResult(
            result_id=f"exec_result_{uuid4().hex}",
            adapter_name=self.adapter_name,
            action=ExecutionAction.CANCEL,
            status=ExecutionResultStatus.BLOCKED,
            blocked=True,
            simulated=False,
            request_id=request.request_id,
            command_id=request.command_id,
            message="Cancel request blocked by mock adapter.",
            reasons=reasons,
            external_transaction_id=None,
            private_endpoint_called=False,
            secrets_included=False,
        )


def build_default_blocked_readiness_report() -> ManualLiveExecutionReadinessReport:
    """Build the default blocked readiness report."""

    return build_manual_live_execution_readiness_report()


def _blocked_reasons_from_readiness(
    readiness_report: ManualLiveExecutionReadinessReport,
) -> tuple[str, ...]:
    reasons: list[str] = []

    if readiness_report.live_execution_blocked:
        reasons.append("Readiness report is blocked.")

        for component in readiness_report.components:
            if getattr(component, "blocked", False):
                component_name = getattr(component, "name", "unknown_component")
                component_reasons = getattr(component, "reasons", ())

                if component_reasons:
                    for reason in component_reasons:
                        reasons.append(f"{component_name}: {reason}")
                else:
                    reasons.append(f"{component_name}: blocked")

    return tuple(reasons)

def require_text(value: str, field_name: str) -> str:
    text = str(value or "").strip()

    if not text:
        raise ExecutionAdapterError(f"{field_name} is required.")

    return text


def validate_positive_decimal(value: str | Decimal, field_name: str) -> Decimal:
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ExecutionAdapterError(f"{field_name} must be a valid decimal number.") from exc

    if parsed <= Decimal("0"):
        raise ExecutionAdapterError(f"{field_name} must be greater than zero.")

    return parsed


def assert_adapter_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that an adapter report is safe to log."""

    text = str(report).lower()

    forbidden_terms = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "token=",
    )

    for term in forbidden_terms:
        if term in text:
            raise ExecutionAdapterError(f"Unsafe adapter report term detected: {term}")

    if report.get("secrets_included") is not False:
        raise ExecutionAdapterError("Adapter report must not include secrets.")

    if report.get("private_endpoint_called") is not False:
        raise ExecutionAdapterError("Adapter report must not report private endpoint calls.")




