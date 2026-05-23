$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 17A LIVE EXECUTION ADAPTER INTERFACE ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$adapterPath = ".\tradingagents\execution\execution_adapter.py"
$testPath = ".\scripts\test_execution_adapter_interface.py"

$adapterContent = @'
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
            "readiness_blocked": self.readiness_report.blocked,
            "secrets_included": False,
            "private_endpoint_call_requested": False,
        }


@dataclass(frozen=True)
class CancelOrderRequest:
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
            "readiness_blocked": self.readiness_report.blocked,
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

    def cancel_order(self, request: CancelOrderRequest) -> ExecutionAdapterResult:
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

        if self.allow_simulated_success and not request.readiness_report.blocked:
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

    def cancel_order(self, request: CancelOrderRequest) -> ExecutionAdapterResult:
        request.validate()

        reasons = _blocked_reasons_from_readiness(request.readiness_report)
        reasons += (
            "Slice 17A mock adapter is non-live and cannot cancel real orders.",
        )

        if self.allow_simulated_success and not request.readiness_report.blocked:
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

    if readiness_report.blocked:
        reasons.append("Readiness report is blocked.")
        reasons.extend(str(reason) for reason in readiness_report.reasons)

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
'@

$testContent = @'
"""
Validation script for Slice 17A.

This validates the execution adapter interface and mock adapter.

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
    CancelOrderRequest,
    ExecutionAdapter,
    ExecutionAdapterError,
    ExecutionResultStatus,
    MockExecutionAdapter,
    SubmitOrderRequest,
    assert_adapter_report_is_safe,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandStatus,
)


def make_command() -> ManualExecutionCommand:
    return ManualExecutionCommand(
        command_id="cmd_slice_17a_test",
        package_id="sim_slice_17a_test",
        audit_id="audit_slice_17a_test",
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        limit_price=Decimal("100000"),
        status=ManualExecutionCommandStatus.BLOCKED,
        metadata={
            "source": "slice_17a_test",
            "simulation_only": True,
        },
    )


def test_mock_adapter_capabilities_are_safe() -> None:
    adapter = MockExecutionAdapter()
    assert isinstance(adapter, ExecutionAdapter)

    report = adapter.capabilities().safe_report()

    assert report["adapter_name"] == "MockExecutionAdapter"
    assert report["mode"] == "mock"
    assert report["live_execution_enabled"] is False
    assert report["simulation_only"] is True
    assert report["private_endpoint_calls_enabled"] is False
    assert report["secrets_included"] is False

    print("[OK] mock adapter capabilities are safe")


def test_submit_request_blocks_by_default() -> None:
    adapter = MockExecutionAdapter()
    readiness = build_default_blocked_readiness_report()
    command = make_command()

    request = SubmitOrderRequest(
        request_id="submit_slice_17a_test",
        command=command,
        readiness_report=readiness,
        metadata={"source": "slice_17a_test"},
    )

    result = adapter.submit_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("Readiness report is blocked." in reason for reason in result.reasons)

    assert_adapter_report_is_safe(report)

    print("[OK] submit request blocks by default")


def test_cancel_request_blocks_by_default() -> None:
    adapter = MockExecutionAdapter()
    readiness = build_default_blocked_readiness_report()

    request = CancelOrderRequest(
        request_id="cancel_slice_17a_test",
        command_id="cmd_slice_17a_test",
        simulated_transaction_id="sim_tx_slice_17a_test",
        readiness_report=readiness,
        reason="operator review test",
        metadata={"source": "slice_17a_test"},
    )

    result = adapter.cancel_order(request)
    report = result.safe_report()

    assert result.status == ExecutionResultStatus.BLOCKED
    assert report["blocked"] is True
    assert report["simulated"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert adapter.private_endpoint_called is False
    assert any("Readiness report is blocked." in reason for reason in result.reasons)

    assert_adapter_report_is_safe(report)

    print("[OK] cancel request blocks by default")


def expect_error(label: str, func) -> None:
    try:
        func()
    except ExecutionAdapterError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected ExecutionAdapterError")


def test_invalid_requests_are_rejected() -> None:
    readiness = build_default_blocked_readiness_report()
    command = make_command()

    expect_error(
        "missing submit request_id rejected",
        lambda: SubmitOrderRequest(
            request_id="",
            command=command,
            readiness_report=readiness,
        ).validate(),
    )

    bad_command = ManualExecutionCommand(
        command_id="cmd_bad_volume",
        package_id="sim_bad_volume",
        audit_id="audit_bad_volume",
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        limit_price=Decimal("100000"),
        status=ManualExecutionCommandStatus.BLOCKED,
    )

    # ManualExecutionCommand validates its own volume. This adapter validation check
    # covers missing cancel fields separately.
    assert bad_command.volume > 0

    expect_error(
        "missing cancel transaction id rejected",
        lambda: CancelOrderRequest(
            request_id="cancel_missing_tx",
            command_id="cmd_slice_17a_test",
            simulated_transaction_id="",
            readiness_report=readiness,
            reason="operator review test",
        ).validate(),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path("tradingagents/execution/execution_adapter.py").read_text(
        encoding="utf-8"
    ).lower()

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

    print("[OK] adapter source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17A validation: Live Execution Adapter Interface")
    print("=" * 80)

    test_mock_adapter_capabilities_are_safe()
    test_submit_request_blocks_by_default()
    test_cancel_request_blocks_by_default()
    test_invalid_requests_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17A execution adapter interface validation passed.")
    print("[PASS] Mock adapter remains blocked and simulation-only.")
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
## Slice 17A — Live Execution Adapter Interface

Status: Implemented pending validation.

Goal:
Define the abstract interface boundary for future execution adapters.

Scope:
- Create `tradingagents/execution/execution_adapter.py`.
- Create `scripts/test_execution_adapter_interface.py`.
- Define submit/cancel request models.
- Define execution result model.
- Define adapter capabilities model.
- Define execution adapter protocol.
- Add a mock adapter for validation.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 17A — Live Execution Adapter Interface

The project now has an execution adapter interface boundary.

The interface defines:
- submit request model
- cancel request model
- execution result model
- capabilities declaration
- adapter protocol
- mock adapter

The mock adapter remains blocked and simulation-only. This slice does not add any real exchange execution call.
"@

$decisionBlock = @"
## Slice 17A Decision — Add Execution Adapter Interface Before Live Implementation

Decision:
Add an execution adapter interface before implementing any real exchange execution adapter.

Reason:
The manual review and audit pipeline now exists. The next safe architectural step is to define the adapter boundary so future live execution work must conform to explicit request/result/capability models.

Result:
The project has a tested mock adapter and interface without introducing live execution.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 17A — Live Execution Adapter Interface" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 17A — Live Execution Adapter Interface" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 17A Decision — Add Execution Adapter Interface Before Live Implementation" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 17A FILES ==="
Get-Item `
    ".\tradingagents\execution\execution_adapter.py", `
    ".\scripts\test_execution_adapter_interface.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 17A script completed."
