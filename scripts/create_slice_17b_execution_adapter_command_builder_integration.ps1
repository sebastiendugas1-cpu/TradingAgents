$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 17B EXECUTION ADAPTER + COMMAND BUILDER INTEGRATION ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$integrationPath = ".\tradingagents\execution\execution_adapter_command_integration.py"
$testPath = ".\scripts\test_execution_adapter_command_integration.py"

$integrationContent = @'
"""
Slice 17B execution adapter + command builder integration.

This module connects the manual execution command builder to the execution
adapter interface using the mock adapter only.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.execution_adapter import (
    ExecutionAdapter,
    ExecutionAdapterResult,
    MockExecutionAdapter,
    SubmitOrderRequest,
    assert_adapter_report_is_safe,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.manual_execution_command import ManualExecutionCommand
from tradingagents.execution.manual_execution_command_builder import (
    ManualExecutionCommandBuildResult,
    ManualExecutionCommandBuilderError,
    build_manual_execution_command_from_order_intent,
)


class ExecutionAdapterCommandIntegrationError(ValueError):
    """Raised when the adapter command integration is unsafe or invalid."""


@dataclass(frozen=True)
class AdapterCommandIntegrationResult:
    """
    Result of building a manual command and sending it to the mock adapter.

    The result is safe to log and remains non-executable.
    """

    integration_id: str
    builder_result: ManualExecutionCommandBuildResult
    command: ManualExecutionCommand
    submit_request: SubmitOrderRequest
    adapter_result: ExecutionAdapterResult
    adapter_name: str
    final_status: str
    blocked: bool
    simulated: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)
    secrets_included: bool = False
    private_endpoint_called: bool = False

    def safe_report(self) -> dict[str, Any]:
        adapter_report = self.adapter_result.safe_report()
        assert_adapter_report_is_safe(adapter_report)

        return {
            "integration_id": self.integration_id,
            "adapter_name": self.adapter_name,
            "builder_id": self.builder_result.builder_id,
            "package_id": self.builder_result.package_id,
            "audit_id": self.builder_result.audit_id,
            "command_id": self.command.command_id,
            "request_id": self.submit_request.request_id,
            "adapter_result_id": self.adapter_result.result_id,
            "final_status": self.final_status,
            "blocked": self.blocked,
            "simulated": self.simulated,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "builder_report": self.builder_result.safe_report(),
            "submit_request_report": self.submit_request.safe_report(),
            "adapter_report": adapter_report,
            "secrets_included": False,
            "private_endpoint_called": False,
            "execution_allowed": False,
        }


def build_command_and_route_to_mock_adapter(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    audit_file_path: str | Path | None = None,
    adapter: ExecutionAdapter | None = None,
    env: Mapping[str, str] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> AdapterCommandIntegrationResult:
    """
    Build a manual execution command and route it to the mock adapter.

    This is a non-live integration path. It proves the command builder and
    adapter interface can work together without adding real execution.
    """

    selected_adapter = adapter or MockExecutionAdapter()
    capabilities = selected_adapter.capabilities()

    if capabilities.live_execution_enabled:
        raise ExecutionAdapterCommandIntegrationError(
            "Live execution adapters are not allowed in Slice 17B."
        )

    if capabilities.private_endpoint_calls_enabled:
        raise ExecutionAdapterCommandIntegrationError(
            "Private endpoint-capable adapters are not allowed in Slice 17B."
        )

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
            "source": "slice_17b_adapter_command_integration",
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

    readiness_report = build_default_blocked_readiness_report()

    submit_request = SubmitOrderRequest(
        request_id=f"submit_request_{uuid4().hex}",
        command=command,
        readiness_report=readiness_report,
        metadata={
            "source": "slice_17b_adapter_command_integration",
            "simulation_only": True,
        },
    )

    adapter_result = selected_adapter.submit_order(submit_request)
    adapter_report = adapter_result.safe_report()
    assert_adapter_report_is_safe(adapter_report)

    reasons = tuple(builder_result.reasons) + tuple(adapter_result.reasons)

    return AdapterCommandIntegrationResult(
        integration_id=f"adapter_integration_{uuid4().hex}",
        builder_result=builder_result,
        command=command,
        submit_request=submit_request,
        adapter_result=adapter_result,
        adapter_name=capabilities.adapter_name,
        final_status="adapter_command_integration_blocked_from_live_execution",
        blocked=True,
        simulated=adapter_result.simulated,
        reasons=reasons
        or ("Slice 17B adapter command integration is blocked by design.",),
        secrets_included=False,
        private_endpoint_called=False,
    )


def _command_from_builder_result(
    *,
    builder_result: ManualExecutionCommandBuildResult,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None,
) -> ManualExecutionCommand:
    """
    Reconstruct a ManualExecutionCommand from the builder report.

    Slice 15E returns a safe build result, not the command object itself.
    The command report contains all needed safe fields.
    """

    command_report = dict(builder_result.command_report or {})

    command_id = str(command_report.get("command_id") or builder_result.command_id)
    package_id = str(command_report.get("package_id") or builder_result.package_id)
    audit_id = str(command_report.get("audit_id") or builder_result.audit_id)
    status = command_report.get("status") or builder_result.command_status

    if not command_id:
        raise ExecutionAdapterCommandIntegrationError("command_id is required.")
    if not package_id:
        raise ExecutionAdapterCommandIntegrationError("package_id is required.")
    if not audit_id:
        raise ExecutionAdapterCommandIntegrationError("audit_id is required.")

    try:
        from tradingagents.execution.manual_execution_command import (
            ManualExecutionCommandStatus,
            parse_status,
        )

        parsed_status = parse_status(status)
    except Exception as exc:
        raise ExecutionAdapterCommandIntegrationError(
            f"Could not parse command status: {status}"
        ) from exc

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
            "source": "slice_17b_adapter_command_integration",
            "simulation_only": True,
            "adapter_boundary_test": True,
        },
    )


def assert_integration_result_is_safe(
    result: AdapterCommandIntegrationResult,
) -> None:
    """Validate that the integration result is safe to log."""

    report = result.safe_report()

    if report["secrets_included"] is not False:
        raise ExecutionAdapterCommandIntegrationError("Integration report includes secrets.")

    if report["private_endpoint_called"] is not False:
        raise ExecutionAdapterCommandIntegrationError(
            "Integration report indicates a private endpoint call."
        )

    if report["execution_allowed"] is not False:
        raise ExecutionAdapterCommandIntegrationError(
            "Integration report must not allow execution."
        )
'@

$testContent = @'
"""
Validation script for Slice 17B.

This validates the adapter + manual command builder integration.

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
from tempfile import TemporaryDirectory

from tradingagents.execution.execution_adapter import MockExecutionAdapter
from tradingagents.execution.execution_adapter_command_integration import (
    ExecutionAdapterCommandIntegrationError,
    assert_integration_result_is_safe,
    build_command_and_route_to_mock_adapter,
)


def test_command_builder_routes_to_mock_adapter() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "adapter_command_integration.jsonl"

        result = build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_17b_test"},
        )

        report = result.safe_report()

        assert report["adapter_name"] == "MockExecutionAdapter"
        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["secrets_included"] is False
        assert report["private_endpoint_called"] is False
        assert report["builder_id"]
        assert report["package_id"]
        assert report["audit_id"]
        assert report["command_id"]
        assert report["request_id"]
        assert report["adapter_result_id"]
        assert audit_path.exists()

        assert report["adapter_report"]["blocked"] is True
        assert report["adapter_report"]["private_endpoint_called"] is False
        assert report["adapter_report"]["secrets_included"] is False

        assert_integration_result_is_safe(result)

    print("[OK] command builder routes to mock adapter safely")


def test_permissive_mock_adapter_still_non_live() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "adapter_command_integration_permissive.jsonl"

        adapter = MockExecutionAdapter(allow_simulated_success=True)

        result = build_command_and_route_to_mock_adapter(
            pair="SOL/CAD",
            side="buy",
            order_type="limit",
            volume=Decimal("0.1"),
            limit_price=Decimal("200"),
            audit_file_path=audit_path,
            adapter=adapter,
            metadata={"source": "slice_17b_test"},
        )

        report = result.safe_report()

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert adapter.private_endpoint_called is False
        assert audit_path.exists()

        assert_integration_result_is_safe(result)

    print("[OK] permissive mock adapter remains non-live")


def expect_error(label: str, func) -> None:
    try:
        func()
    except Exception as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected failure")


def test_invalid_order_intent_fails_safely() -> None:
    expect_error(
        "invalid side rejected",
        lambda: build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="hold",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
        ),
    )

    expect_error(
        "zero volume rejected",
        lambda: build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0",
            limit_price="100000",
        ),
    )

    expect_error(
        "missing limit price rejected",
        lambda: build_command_and_route_to_mock_adapter(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price=None,
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/execution_adapter_command_integration.py"
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

    print("[OK] integration source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17B validation: Execution Adapter + Command Builder Integration")
    print("=" * 80)

    test_command_builder_routes_to_mock_adapter()
    test_permissive_mock_adapter_still_non_live()
    test_invalid_order_intent_fails_safely()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17B execution adapter command integration validation passed.")
    print("[PASS] Command builder routes to mock adapter safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $integrationPath -Value $integrationContent -Encoding UTF8
Write-Host "[WRITTEN] $integrationPath"

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
## Slice 17B — Execution Adapter Integration with Manual Command Builder

Status: Implemented pending validation.

Goal:
Connect the manual execution command builder to the execution adapter interface using the mock adapter only.

Scope:
- Create `tradingagents/execution/execution_adapter_command_integration.py`.
- Create `scripts/test_execution_adapter_command_integration.py`.
- Build a manual command from order intent.
- Build a submit request for the mock adapter.
- Route the request through `MockExecutionAdapter`.
- Produce a safe blocked integration report.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 17B — Execution Adapter + Command Builder Integration

The manual execution command builder is now connected to the execution adapter interface through the mock adapter only.

This integration proves:
- the command builder can produce a command candidate
- the adapter request model can wrap that command
- the mock adapter returns a blocked/non-live result
- the full report is safe to log

This slice does not add any real exchange execution call.
"@

$decisionBlock = @"
## Slice 17B Decision — Connect Command Builder to Mock Adapter

Decision:
Connect the manual execution command builder to the execution adapter interface using only the mock adapter.

Reason:
After adding the adapter interface, the next safe step is to prove the existing command pipeline can use that boundary without enabling live execution.

Result:
The project can route a command candidate to a mock adapter and receive a blocked safe result.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 17B — Execution Adapter Integration with Manual Command Builder" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 17B — Execution Adapter + Command Builder Integration" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 17B Decision — Connect Command Builder to Mock Adapter" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 17B FILES ==="
Get-Item `
    ".\tradingagents\execution\execution_adapter_command_integration.py", `
    ".\scripts\test_execution_adapter_command_integration.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 17B script completed."
