$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 17F KRAKEN LIVE ADAPTER SKELETON BEHIND ACTIVATION POLICY ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$adapterPath = ".\tradingagents\execution\kraken_live_adapter_skeleton.py"
$testPath = ".\scripts\test_kraken_live_adapter_skeleton.py"

$adapterContent = @'
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
'@

$testContent = @'
"""
Validation script for Slice 17F.

This validates the Kraken live adapter skeleton behind activation policy.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path

from tradingagents.execution.execution_adapter import (
    ExecutionResultStatus,
    OrderCancellationRequest,
    SubmitOrderRequest,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.kraken_live_adapter_skeleton import (
    KrakenLiveAdapterSkeleton,
    KrakenLiveAdapterSkeletonConfig,
    KrakenLiveAdapterSkeletonError,
    assert_kraken_adapter_skeleton_report_is_safe,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandStatus,
)


def make_command() -> ManualExecutionCommand:
    return ManualExecutionCommand(
        command_id="cmd_slice_17f_test",
        package_id="sim_slice_17f_test",
        audit_id="audit_slice_17f_test",
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        limit_price=Decimal("100000"),
        status=ManualExecutionCommandStatus.BLOCKED,
        metadata={"source": "slice_17f_test"},
    )


def test_skeleton_capabilities_are_disabled() -> None:
    adapter = KrakenLiveAdapterSkeleton()
    report = adapter.capabilities().safe_report()

    assert report["adapter_name"] == "KrakenLiveAdapterSkeleton"
    assert report["mode"] == "future_live"
    assert report["can_submit_orders"] is False
    assert report["can_cancel_orders"] is False
    assert report["live_execution_enabled"] is False
    assert report["simulation_only"] is True
    assert report["private_endpoint_calls_enabled"] is False
    assert report["secrets_included"] is False

    assert_kraken_adapter_skeleton_report_is_safe(adapter.safe_report())

    print("[OK] skeleton capabilities are disabled")


def test_submit_blocks_with_default_policy() -> None:
    adapter = KrakenLiveAdapterSkeleton()
    command = make_command()
    readiness = build_default_blocked_readiness_report()

    request = SubmitOrderRequest(
        request_id="submit_slice_17f_test",
        command=command,
        readiness_report=readiness,
        metadata={"source": "slice_17f_test"},
    )

    result = adapter.submit_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("disabled in Slice 17F" in reason for reason in result.reasons)

    print("[OK] submit blocks with default policy")


def test_cancel_blocks_with_default_policy() -> None:
    adapter = KrakenLiveAdapterSkeleton()
    readiness = build_default_blocked_readiness_report()

    request = OrderCancellationRequest(
        request_id="cancel_slice_17f_test",
        command_id="cmd_slice_17f_test",
        simulated_transaction_id="sim_tx_slice_17f_test",
        readiness_report=readiness,
        reason="operator review test",
        metadata={"source": "slice_17f_test"},
    )

    result = adapter.cancel_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("disabled in Slice 17F" in reason for reason in result.reasons)

    print("[OK] cancel blocks with default policy")


def test_theoretical_ready_policy_still_blocks() -> None:
    adapter = KrakenLiveAdapterSkeleton(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    command = make_command()
    readiness = build_default_blocked_readiness_report()

    request = SubmitOrderRequest(
        request_id="submit_slice_17f_ready_policy_test",
        command=command,
        readiness_report=readiness,
    )

    result = adapter.submit_order(request)
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("disabled in Slice 17F" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks skeleton")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenLiveAdapterSkeletonError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenLiveAdapterSkeletonError")


def test_private_endpoint_enabled_config_rejected() -> None:
    expect_error(
        "private endpoint-capable config rejected",
        lambda: KrakenLiveAdapterSkeleton(
            config=KrakenLiveAdapterSkeletonConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_live_adapter_skeleton.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
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

    print("[OK] skeleton source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17F validation: Kraken Live Adapter Skeleton Behind Activation Policy")
    print("=" * 80)

    test_skeleton_capabilities_are_disabled()
    test_submit_blocks_with_default_policy()
    test_cancel_blocks_with_default_policy()
    test_theoretical_ready_policy_still_blocks()
    test_private_endpoint_enabled_config_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17F Kraken live adapter skeleton validation passed.")
    print("[PASS] Skeleton remains disabled behind activation policy.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $adapterPath -Value $adapterContent -Encoding UTF8
Write-Host "[WRITTEN] $adapterPath"

Set-Content -Path $testPath -Value $testContent -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

function Add-DocBlockOnce {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing doc file: $Path"
    }

    $existing = Get-Content $Path -Raw

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`n$Block" -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @"
## Slice 17F — Kraken Live Adapter Skeleton Behind Activation Policy

Status: Implemented pending validation.

Goal:
Create a disabled Kraken live adapter skeleton behind the execution adapter interface and activation policy.

Scope:
- Create `tradingagents/execution/kraken_live_adapter_skeleton.py`.
- Create `scripts/test_kraken_live_adapter_skeleton.py`.
- Declare skeleton capabilities as disabled/future-live.
- Require activation policy evaluation.
- Block submit/cancel paths by default.
- Validate no private endpoint call exists.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 17F — Kraken Live Adapter Skeleton Behind Activation Policy

A disabled Kraken live adapter skeleton has been added behind:
- the execution adapter interface
- the activation policy
- default blocking behavior

The skeleton:
- declares future-live capabilities
- remains disabled
- blocks submit/cancel requests
- reports no private endpoint calls
- includes no real exchange execution call
"@

$decisionBlock = @"
## Slice 17F Decision — Add Disabled Kraken Adapter Skeleton Behind Policy

Decision:
Add a Kraken live adapter skeleton, but keep it disabled and blocked behind activation policy.

Reason:
The project needs a future-live adapter boundary before any real exchange execution implementation can be considered.

Result:
The project has a tested Kraken adapter skeleton that remains non-executing and policy-blocked.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 17F — Kraken Live Adapter Skeleton Behind Activation Policy" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 17F — Kraken Live Adapter Skeleton Behind Activation Policy" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 17F Decision — Add Disabled Kraken Adapter Skeleton Behind Policy" -Block $decisionBlock

python -m py_compile $adapterPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 17F FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_live_adapter_skeleton.py", `
    ".\scripts\test_kraken_live_adapter_skeleton.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 17F script completed."
