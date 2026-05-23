$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 19A DISABLED KRAKEN PRIVATE CLIENT SHELL ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$clientPath = ".\tradingagents\execution\kraken_private_client_shell.py"
$testPath = ".\scripts\test_kraken_private_client_shell.py"

$clientContent = @'
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
'@

$testContent = @'
"""
Validation script for Slice 19A.

This validates the disabled Kraken private client shell.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.kraken_private_client_shell import (
    KrakenPrivateClientShell,
    KrakenPrivateClientShellConfig,
    KrakenPrivateClientShellError,
    KrakenPrivateClientShellStatus,
    assert_kraken_private_client_shell_report_is_safe,
)
from tradingagents.execution.kraken_private_order_request_translator import (
    KrakenPrivateOrderPayload,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)


def make_payload() -> KrakenPrivateOrderPayload:
    return KrakenPrivateOrderPayload(
        pair="XBT/CAD",
        type="buy",
        ordertype="limit",
        volume="0.000085168",
        price="100000",
        validate=True,
        userref="cmd_slice_19a_test",
    )


def test_shell_capabilities_are_disabled() -> None:
    client = KrakenPrivateClientShell()
    report = client.safe_report()
    capabilities = report["capabilities"]

    assert report["enabled"] is False
    assert report["dry_run_only"] is True
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert capabilities["can_submit_private_order"] is False
    assert capabilities["can_cancel_private_order"] is False
    assert capabilities["can_query_private_order_status"] is False
    assert capabilities["private_endpoint_calls_enabled"] is False

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] private client shell capabilities are disabled")


def test_submit_preview_blocks() -> None:
    client = KrakenPrivateClientShell()
    result = client.submit_private_order_preview(make_payload())
    report = result.safe_report()

    assert result.status == KrakenPrivateClientShellStatus.BLOCKED
    assert report["blocked"] is True
    assert report["operation"] == "submit_private_order_preview"
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert report["payload_preview"]["pair"] == "XBT/CAD"
    assert client.private_endpoint_called is False
    assert any("disabled in Slice 19A" in reason for reason in result.reasons)

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] submit preview blocks")


def test_cancel_preview_blocks() -> None:
    client = KrakenPrivateClientShell()
    result = client.cancel_private_order_preview(
        simulated_transaction_id="sim_tx_slice_19a",
        reason="operator review test",
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["operation"] == "cancel_private_order_preview"
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert report["payload_preview"]["simulated_transaction_id"] == "sim_tx_slice_19a"
    assert client.private_endpoint_called is False

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] cancel preview blocks")


def test_status_preview_blocks() -> None:
    client = KrakenPrivateClientShell()
    result = client.query_private_order_status_preview(
        simulated_transaction_id="sim_tx_slice_19a",
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["operation"] == "query_private_order_status_preview"
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert client.private_endpoint_called is False

    assert_kraken_private_client_shell_report_is_safe(report)

    print("[OK] status preview blocks")


def test_theoretical_ready_policy_still_blocks() -> None:
    client = KrakenPrivateClientShell(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    result = client.submit_private_order_preview(make_payload())
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert client.private_endpoint_called is False
    assert any("disabled in Slice 19A" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks private client shell")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenPrivateClientShellError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenPrivateClientShellError")


def test_invalid_inputs_are_rejected() -> None:
    expect_error(
        "private endpoint-capable config rejected",
        lambda: KrakenPrivateClientShell(
            config=KrakenPrivateClientShellConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )

    expect_error(
        "missing simulated transaction id rejected",
        lambda: KrakenPrivateClientShell().cancel_private_order_preview(
            simulated_transaction_id="",
            reason="operator review test",
        ),
    )

    expect_error(
        "wrong payload type rejected",
        lambda: KrakenPrivateClientShell().submit_private_order_preview(
            object(),  # type: ignore[arg-type]
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_client_shell.py"
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

    print("[OK] private client shell source contains no private execution endpoint names")


def main() -> None:
    print("Slice 19A validation: Disabled Kraken Private Client Shell")
    print("=" * 80)

    test_shell_capabilities_are_disabled()
    test_submit_preview_blocks()
    test_cancel_preview_blocks()
    test_status_preview_blocks()
    test_theoretical_ready_policy_still_blocks()
    test_invalid_inputs_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 19A disabled Kraken private client shell validation passed.")
    print("[PASS] Private client shell remains disabled and blocked.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $clientPath -Value $clientContent -Encoding UTF8
Write-Host "[WRITTEN] $clientPath"

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
## Slice 19A — Disabled Kraken Private Client Shell

Status: Implemented pending validation.

Goal:
Create a disabled private client shell for future Kraken private operations.

Scope:
- Create `tradingagents/execution/kraken_private_client_shell.py`.
- Create `scripts/test_kraken_private_client_shell.py`.
- Define safe config and result models.
- Define blocked submit preview, cancel preview, and status preview methods.
- Require activation policy evaluation.
- Validate that no private endpoint call exists.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 19A — Disabled Kraken Private Client Shell

A disabled Kraken private client shell has been added.

The shell:
- has no network transport
- has no private endpoint implementation
- blocks submit/cancel/status preview methods
- requires activation policy evaluation
- reports no private endpoint calls
- does not enable execution
"@

$decisionBlock = @"
## Slice 19A Decision — Add Disabled Private Client Shell Before Any Private Implementation

Decision:
Add a disabled Kraken private client shell before any future private endpoint implementation.

Reason:
The system needs a safe private-client boundary before any endpoint-specific implementation can be considered.

Result:
The project now has a tested disabled private client shell with blocked preview methods and no endpoint calls.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 19A — Disabled Kraken Private Client Shell" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 19A — Disabled Kraken Private Client Shell" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 19A Decision — Add Disabled Private Client Shell Before Any Private Implementation" -Block $decisionBlock

python -m py_compile $clientPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 19A FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_private_client_shell.py", `
    ".\scripts\test_kraken_private_client_shell.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 19A script completed."
