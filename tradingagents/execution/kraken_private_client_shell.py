"""
Slice 19A disabled Kraken private client shell.

This module defines the boundary for future Kraken private client behavior.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

Every method is blocked by default. This file is an interface shell only.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.kraken_private_order_request_translator import (
    KrakenPrivateOrderPayload,
)
from tradingagents.execution.live_execution_activation_policy import (
    LiveExecutionActivationEvidence,
    LiveExecutionActivationPolicyResult,
    evaluate_live_execution_activation_policy,
)


class KrakenPrivateClientShellError(ValueError):
    """Raised when the disabled Kraken private client shell blocks an operation."""


class KrakenPrivateClientShellStatus(str, Enum):
    """Private client shell result status."""

    BLOCKED = "blocked"
    DISABLED = "disabled"
    NOT_IMPLEMENTED = "not_implemented"


@dataclass(frozen=True)
class KrakenPrivateClientShellConfig:
    """Safe-to-log config for the disabled private client shell."""

    client_name: str = "KrakenPrivateClientShell"
    enabled: bool = False
    dry_run_only: bool = True
    require_activation_policy: bool = True
    allow_private_endpoint_calls: bool = False
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def safe_report(self) -> dict[str, Any]:
        return {
            "client_name": self.client_name,
            "enabled": self.enabled,
            "dry_run_only": self.dry_run_only,
            "require_activation_policy": self.require_activation_policy,
            "allow_private_endpoint_calls": self.allow_private_endpoint_calls,
            "secrets_included": False,
            "private_endpoint_calls_enabled": False,
        }


@dataclass(frozen=True)
class KrakenPrivateClientShellResult:
    """Safe-to-log blocked private client shell result."""

    result_id: str
    client_name: str
    operation: str
    status: KrakenPrivateClientShellStatus
    blocked: bool
    message: str
    reasons: tuple[str, ...]
    payload_preview: Mapping[str, Any] | None = None
    activation_policy_report: Mapping[str, Any] | None = None
    secrets_included: bool = False
    private_endpoint_called: bool = False
    execution_allowed: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "result_id": self.result_id,
            "client_name": self.client_name,
            "operation": self.operation,
            "status": self.status.value,
            "blocked": self.blocked,
            "message": self.message,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "payload_preview": dict(self.payload_preview or {}),
            "activation_policy_report": dict(self.activation_policy_report or {}),
            "secrets_included": False,
            "private_endpoint_called": False,
            "execution_allowed": False,
        }


class KrakenPrivateClientShell:
    """
    Disabled shell for future Kraken private client methods.

    This class intentionally contains no network transport and no private endpoint
    implementation. All operations return blocked results.
    """

    def __init__(
        self,
        *,
        config: KrakenPrivateClientShellConfig | None = None,
        activation_evidence: LiveExecutionActivationEvidence | None = None,
    ) -> None:
        self.config = config or KrakenPrivateClientShellConfig()
        self.activation_evidence = activation_evidence
        self.private_endpoint_called = False

        if self.config.allow_private_endpoint_calls:
            raise KrakenPrivateClientShellError(
                "Private endpoint calls are not allowed in Slice 19A."
            )

    def activation_policy_result(self) -> LiveExecutionActivationPolicyResult:
        return evaluate_live_execution_activation_policy(self.activation_evidence)

    def capabilities(self) -> dict[str, Any]:
        return {
            "client_name": self.config.client_name,
            "enabled": False,
            "dry_run_only": True,
            "can_submit_private_order": False,
            "can_cancel_private_order": False,
            "can_query_private_order_status": False,
            "requires_activation_policy": True,
            "private_endpoint_calls_enabled": False,
            "secrets_included": False,
        }

    def submit_private_order_preview(
        self,
        payload: KrakenPrivateOrderPayload,
    ) -> KrakenPrivateClientShellResult:
        """
        Accept a Kraken-style payload object for preview only and block it.

        No endpoint is called.
        """

        if not isinstance(payload, KrakenPrivateOrderPayload):
            raise KrakenPrivateClientShellError(
                "payload must be a KrakenPrivateOrderPayload."
            )

        return self._blocked_result(
            operation="submit_private_order_preview",
            payload_preview=payload.safe_report(),
        )

    def cancel_private_order_preview(
        self,
        *,
        simulated_transaction_id: str,
        reason: str,
    ) -> KrakenPrivateClientShellResult:
        """
        Accept a simulated transaction id for preview only and block it.

        No endpoint is called.
        """

        txid = str(simulated_transaction_id or "").strip()
        note = str(reason or "").strip()

        if not txid:
            raise KrakenPrivateClientShellError("simulated_transaction_id is required.")
        if not note:
            raise KrakenPrivateClientShellError("reason is required.")

        return self._blocked_result(
            operation="cancel_private_order_preview",
            payload_preview={
                "simulated_transaction_id": txid,
                "reason": note,
                "preview_only": True,
            },
        )

    def query_private_order_status_preview(
        self,
        *,
        simulated_transaction_id: str,
    ) -> KrakenPrivateClientShellResult:
        """
        Accept a simulated transaction id for status preview only and block it.

        No endpoint is called.
        """

        txid = str(simulated_transaction_id or "").strip()

        if not txid:
            raise KrakenPrivateClientShellError("simulated_transaction_id is required.")

        return self._blocked_result(
            operation="query_private_order_status_preview",
            payload_preview={
                "simulated_transaction_id": txid,
                "preview_only": True,
            },
        )

    def safe_report(self) -> dict[str, Any]:
        policy_report = self.activation_policy_result().safe_report()

        return {
            "client_name": self.config.client_name,
            "slice": "19A",
            "enabled": False,
            "dry_run_only": True,
            "private_endpoint_called": False,
            "secrets_included": False,
            "execution_allowed": False,
            "config": self.config.safe_report(),
            "capabilities": self.capabilities(),
            "activation_policy": policy_report,
        }

    def _blocked_result(
        self,
        *,
        operation: str,
        payload_preview: Mapping[str, Any] | None = None,
    ) -> KrakenPrivateClientShellResult:
        policy_result = self.activation_policy_result()

        reasons = tuple(str(reason) for reason in policy_result.reasons)
        reasons += (
            "Kraken private client shell is disabled in Slice 19A.",
            "No private endpoint call is implemented.",
        )

        return KrakenPrivateClientShellResult(
            result_id=f"kraken_private_shell_{uuid4().hex}",
            client_name=self.config.client_name,
            operation=operation,
            status=KrakenPrivateClientShellStatus.BLOCKED,
            blocked=True,
            message="Operation blocked by disabled Kraken private client shell.",
            reasons=reasons,
            payload_preview=payload_preview,
            activation_policy_report=policy_result.safe_report(),
            secrets_included=False,
            private_endpoint_called=False,
            execution_allowed=False,
        )


def assert_kraken_private_client_shell_report_is_safe(
    report: Mapping[str, Any],
) -> None:
    """Validate that the private client shell report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenPrivateClientShellError("Private client report includes secrets.")

    if report.get("private_endpoint_called") is not False:
        raise KrakenPrivateClientShellError(
            "Private client report indicates a private endpoint call."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPrivateClientShellError(
            "Private client report must not allow execution."
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
            raise KrakenPrivateClientShellError(
                f"Unsafe secret-like term detected: {term}"
            )
