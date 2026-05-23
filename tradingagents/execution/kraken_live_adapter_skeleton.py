"""
Slice 17F Kraken live adapter skeleton behind activation policy.

This module creates a future-live Kraken adapter skeleton behind the existing
ExecutionAdapter interface and Slice 17D activation policy.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

The adapter is intentionally blocked by default and contains no exchange
private endpoint calls.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.execution_adapter import (
    ExecutionAction,
    ExecutionAdapterCapabilities,
    ExecutionAdapterError,
    ExecutionAdapterMode,
    ExecutionAdapterResult,
    ExecutionResultStatus,
    OrderCancellationRequest,
    SubmitOrderRequest,
)
from tradingagents.execution.live_execution_activation_policy import (
    LiveExecutionActivationEvidence,
    LiveExecutionActivationPolicyResult,
    evaluate_live_execution_activation_policy,
)


class KrakenLiveAdapterSkeletonError(ExecutionAdapterError):
    """Raised when the Kraken adapter skeleton blocks unsafe use."""


@dataclass(frozen=True)
class KrakenLiveAdapterSkeletonConfig:
    """
    Configuration for the future-live Kraken adapter skeleton.

    This config is safe to log and intentionally defaults to disabled.
    """

    adapter_name: str = "KrakenLiveAdapterSkeleton"
    enabled: bool = False
    dry_run_only: bool = True
    require_activation_policy: bool = True
    allow_private_endpoint_calls: bool = False
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def safe_report(self) -> dict[str, Any]:
        return {
            "adapter_name": self.adapter_name,
            "enabled": self.enabled,
            "dry_run_only": self.dry_run_only,
            "require_activation_policy": self.require_activation_policy,
            "allow_private_endpoint_calls": self.allow_private_endpoint_calls,
            "secrets_included": False,
            "private_endpoint_calls_enabled": False,
        }


class KrakenLiveAdapterSkeleton:
    """
    Future-live Kraken adapter skeleton.

    The class implements the ExecutionAdapter shape, but all submit/cancel paths
    are blocked. It is a boundary object for future implementation only.
    """

    def __init__(
        self,
        *,
        config: KrakenLiveAdapterSkeletonConfig | None = None,
        activation_evidence: LiveExecutionActivationEvidence | None = None,
    ) -> None:
        self.config = config or KrakenLiveAdapterSkeletonConfig()
        self.activation_evidence = activation_evidence
        self.private_endpoint_called = False

        if self.config.allow_private_endpoint_calls:
            raise KrakenLiveAdapterSkeletonError(
                "Private endpoint calls are not allowed in Slice 17F."
            )

    def capabilities(self) -> ExecutionAdapterCapabilities:
        return ExecutionAdapterCapabilities(
            adapter_name=self.config.adapter_name,
            mode=ExecutionAdapterMode.FUTURE_LIVE,
            can_submit_orders=False,
            can_cancel_orders=False,
            live_execution_enabled=False,
            requires_manual_approval=True,
            requires_risk_gate=True,
            requires_readiness_report=True,
            simulation_only=True,
            private_endpoint_calls_enabled=False,
            secrets_included=False,
        )

    def activation_policy_result(self) -> LiveExecutionActivationPolicyResult:
        return evaluate_live_execution_activation_policy(self.activation_evidence)

    def submit_order(self, request: SubmitOrderRequest) -> ExecutionAdapterResult:
        request.validate()

        policy_result = self.activation_policy_result()
        reasons = _policy_reasons(policy_result)
        reasons += (
            "Kraken live adapter skeleton is disabled in Slice 17F.",
            "No private endpoint call is implemented.",
        )

        return ExecutionAdapterResult(
            result_id=f"kraken_skeleton_result_{uuid4().hex}",
            adapter_name=self.config.adapter_name,
            action=ExecutionAction.SUBMIT,
            status=ExecutionResultStatus.BLOCKED,
            blocked=True,
            simulated=False,
            request_id=request.request_id,
            command_id=request.command.command_id,
            message="Submit request blocked by Kraken live adapter skeleton.",
            reasons=reasons,
            external_transaction_id=None,
            private_endpoint_called=False,
            secrets_included=False,
        )

    def cancel_order(self, request: OrderCancellationRequest) -> ExecutionAdapterResult:
        request.validate()

        policy_result = self.activation_policy_result()
        reasons = _policy_reasons(policy_result)
        reasons += (
            "Kraken live adapter skeleton is disabled in Slice 17F.",
            "No private endpoint call is implemented.",
        )

        return ExecutionAdapterResult(
            result_id=f"kraken_skeleton_result_{uuid4().hex}",
            adapter_name=self.config.adapter_name,
            action=ExecutionAction.CANCEL,
            status=ExecutionResultStatus.BLOCKED,
            blocked=True,
            simulated=False,
            request_id=request.request_id,
            command_id=request.command_id,
            message="Cancellation request blocked by Kraken live adapter skeleton.",
            reasons=reasons,
            external_transaction_id=None,
            private_endpoint_called=False,
            secrets_included=False,
        )

    def safe_report(self) -> dict[str, Any]:
        policy_report = self.activation_policy_result().safe_report()
        capabilities_report = self.capabilities().safe_report()

        return {
            "adapter_name": self.config.adapter_name,
            "slice": "17F",
            "enabled": False,
            "dry_run_only": True,
            "simulation_only": True,
            "private_endpoint_called": False,
            "secrets_included": False,
            "config": self.config.safe_report(),
            "capabilities": capabilities_report,
            "activation_policy": policy_report,
        }


def _policy_reasons(
    policy_result: LiveExecutionActivationPolicyResult,
) -> tuple[str, ...]:
    if policy_result.reasons:
        return tuple(str(reason) for reason in policy_result.reasons)

    return ("Activation policy did not provide approval.",)


def assert_kraken_adapter_skeleton_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that the skeleton report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenLiveAdapterSkeletonError("Skeleton report must not include secrets.")

    if report.get("private_endpoint_called") is not False:
        raise KrakenLiveAdapterSkeletonError(
            "Skeleton report must not report private endpoint calls."
        )

    if report.get("enabled") is not False:
        raise KrakenLiveAdapterSkeletonError("Skeleton adapter must remain disabled.")

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
            raise KrakenLiveAdapterSkeletonError(
                f"Unsafe secret-like term detected: {term}"
            )
