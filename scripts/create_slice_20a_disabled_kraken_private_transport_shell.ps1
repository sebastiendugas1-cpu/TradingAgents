$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 20A DISABLED KRAKEN PRIVATE TRANSPORT SHELL ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$transportPath = ".\tradingagents\execution\kraken_private_transport_shell.py"
$testPath = ".\scripts\test_kraken_private_transport_shell.py"

$transportContent = @'
"""
Slice 20A disabled Kraken private transport shell.

This module defines the future private HTTP transport boundary.

It does not:
- create a requests/http session
- send network traffic
- sign private requests
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

from tradingagents.execution.live_execution_activation_policy import (
    LiveExecutionActivationEvidence,
    LiveExecutionActivationPolicyResult,
    evaluate_live_execution_activation_policy,
)


class KrakenPrivateTransportShellError(ValueError):
    """Raised when the disabled Kraken private transport shell blocks use."""


class KrakenPrivateTransportShellStatus(str, Enum):
    """Transport shell result status."""

    BLOCKED = "blocked"
    DISABLED = "disabled"
    NOT_IMPLEMENTED = "not_implemented"


@dataclass(frozen=True)
class KrakenPrivateTransportShellConfig:
    """Safe-to-log config for the disabled private transport shell."""

    transport_name: str = "KrakenPrivateTransportShell"
    enabled: bool = False
    dry_run_only: bool = True
    require_activation_policy: bool = True
    allow_network_calls: bool = False
    allow_private_endpoint_calls: bool = False
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def safe_report(self) -> dict[str, Any]:
        return {
            "transport_name": self.transport_name,
            "enabled": self.enabled,
            "dry_run_only": self.dry_run_only,
            "require_activation_policy": self.require_activation_policy,
            "allow_network_calls": self.allow_network_calls,
            "allow_private_endpoint_calls": self.allow_private_endpoint_calls,
            "network_calls_enabled": False,
            "private_endpoint_calls_enabled": False,
            "secrets_included": False,
        }


@dataclass(frozen=True)
class KrakenPrivateTransportPreviewRequest:
    """
    Safe preview request for future private transport.

    This is not signed and not sent.
    """

    method_name: str
    path_name: str
    payload_preview: Mapping[str, Any] = field(default_factory=dict)
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        if not str(self.method_name or "").strip():
            raise KrakenPrivateTransportShellError("method_name is required.")

        if not str(self.path_name or "").strip():
            raise KrakenPrivateTransportShellError("path_name is required.")

    def safe_report(self) -> dict[str, Any]:
        self.validate()

        return {
            "method_name": str(self.method_name).strip(),
            "path_name": str(self.path_name).strip(),
            "payload_preview": dict(self.payload_preview or {}),
            "metadata": dict(self.metadata or {}),
            "signed": False,
            "sent": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "secrets_included": False,
        }


@dataclass(frozen=True)
class KrakenPrivateTransportShellResult:
    """Safe-to-log blocked private transport shell result."""

    result_id: str
    transport_name: str
    operation: str
    status: KrakenPrivateTransportShellStatus
    blocked: bool
    message: str
    reasons: tuple[str, ...]
    request_preview: Mapping[str, Any] | None = None
    activation_policy_report: Mapping[str, Any] | None = None
    secrets_included: bool = False
    network_call_made: bool = False
    private_endpoint_called: bool = False
    execution_allowed: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "result_id": self.result_id,
            "transport_name": self.transport_name,
            "operation": self.operation,
            "status": self.status.value,
            "blocked": self.blocked,
            "message": self.message,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "request_preview": dict(self.request_preview or {}),
            "activation_policy_report": dict(self.activation_policy_report or {}),
            "secrets_included": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "execution_allowed": False,
        }


class KrakenPrivateTransportShell:
    """
    Disabled shell for future Kraken private HTTP transport.

    This class intentionally contains no session, no signer, no network client,
    and no endpoint implementation. All operations return blocked results.
    """

    def __init__(
        self,
        *,
        config: KrakenPrivateTransportShellConfig | None = None,
        activation_evidence: LiveExecutionActivationEvidence | None = None,
    ) -> None:
        self.config = config or KrakenPrivateTransportShellConfig()
        self.activation_evidence = activation_evidence
        self.network_call_made = False
        self.private_endpoint_called = False

        if self.config.allow_network_calls:
            raise KrakenPrivateTransportShellError(
                "Network calls are not allowed in Slice 20A."
            )

        if self.config.allow_private_endpoint_calls:
            raise KrakenPrivateTransportShellError(
                "Private endpoint calls are not allowed in Slice 20A."
            )

    def activation_policy_result(self) -> LiveExecutionActivationPolicyResult:
        return evaluate_live_execution_activation_policy(self.activation_evidence)

    def capabilities(self) -> dict[str, Any]:
        return {
            "transport_name": self.config.transport_name,
            "enabled": False,
            "dry_run_only": True,
            "can_sign_private_requests": False,
            "can_send_network_requests": False,
            "can_call_private_endpoints": False,
            "requires_activation_policy": True,
            "network_calls_enabled": False,
            "private_endpoint_calls_enabled": False,
            "secrets_included": False,
        }

    def preview_private_request(
        self,
        request: KrakenPrivateTransportPreviewRequest,
    ) -> KrakenPrivateTransportShellResult:
        """
        Accept a future private transport preview request and block it.

        No request is signed. No network call is made.
        """

        if not isinstance(request, KrakenPrivateTransportPreviewRequest):
            raise KrakenPrivateTransportShellError(
                "request must be a KrakenPrivateTransportPreviewRequest."
            )

        request_report = request.safe_report()

        return self._blocked_result(
            operation="preview_private_request",
            request_preview=request_report,
        )

    def safe_report(self) -> dict[str, Any]:
        policy_report = self.activation_policy_result().safe_report()

        return {
            "transport_name": self.config.transport_name,
            "slice": "20A",
            "enabled": False,
            "dry_run_only": True,
            "network_call_made": False,
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
        request_preview: Mapping[str, Any] | None = None,
    ) -> KrakenPrivateTransportShellResult:
        policy_result = self.activation_policy_result()

        reasons = tuple(str(reason) for reason in policy_result.reasons)
        reasons += (
            "Kraken private transport shell is disabled in Slice 20A.",
            "No request signing is implemented.",
            "No network call is implemented.",
            "No private endpoint call is implemented.",
        )

        return KrakenPrivateTransportShellResult(
            result_id=f"kraken_private_transport_{uuid4().hex}",
            transport_name=self.config.transport_name,
            operation=operation,
            status=KrakenPrivateTransportShellStatus.BLOCKED,
            blocked=True,
            message="Operation blocked by disabled Kraken private transport shell.",
            reasons=reasons,
            request_preview=request_preview,
            activation_policy_report=policy_result.safe_report(),
            secrets_included=False,
            network_call_made=False,
            private_endpoint_called=False,
            execution_allowed=False,
        )


def assert_kraken_private_transport_shell_report_is_safe(
    report: Mapping[str, Any],
) -> None:
    """Validate that the private transport shell report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenPrivateTransportShellError("Private transport report includes secrets.")

    if report.get("network_call_made") is not False:
        raise KrakenPrivateTransportShellError(
            "Private transport report indicates a network call."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenPrivateTransportShellError(
            "Private transport report indicates a private endpoint call."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPrivateTransportShellError(
            "Private transport report must not allow execution."
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
            raise KrakenPrivateTransportShellError(
                f"Unsafe secret-like term detected: {term}"
            )
'@

$testContent = @'
"""
Validation script for Slice 20A.

This validates the disabled Kraken private transport shell.

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

from pathlib import Path

from tradingagents.execution.kraken_private_transport_shell import (
    KrakenPrivateTransportPreviewRequest,
    KrakenPrivateTransportShell,
    KrakenPrivateTransportShellConfig,
    KrakenPrivateTransportShellError,
    KrakenPrivateTransportShellStatus,
    assert_kraken_private_transport_shell_report_is_safe,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)


def make_request() -> KrakenPrivateTransportPreviewRequest:
    return KrakenPrivateTransportPreviewRequest(
        method_name="private_order_preview",
        path_name="private_order_preview_path",
        payload_preview={
            "pair": "XBT/CAD",
            "type": "buy",
            "ordertype": "limit",
            "volume": "0.000085168",
            "price": "100000",
            "validate": True,
        },
        metadata={"source": "slice_20a_test"},
    )


def test_transport_capabilities_are_disabled() -> None:
    transport = KrakenPrivateTransportShell()
    report = transport.safe_report()
    capabilities = report["capabilities"]

    assert report["enabled"] is False
    assert report["dry_run_only"] is True
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert capabilities["can_sign_private_requests"] is False
    assert capabilities["can_send_network_requests"] is False
    assert capabilities["can_call_private_endpoints"] is False
    assert capabilities["network_calls_enabled"] is False
    assert capabilities["private_endpoint_calls_enabled"] is False

    assert_kraken_private_transport_shell_report_is_safe(report)

    print("[OK] private transport shell capabilities are disabled")


def test_preview_private_request_blocks() -> None:
    transport = KrakenPrivateTransportShell()
    result = transport.preview_private_request(make_request())
    report = result.safe_report()

    assert result.status == KrakenPrivateTransportShellStatus.BLOCKED
    assert report["blocked"] is True
    assert report["operation"] == "preview_private_request"
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert report["request_preview"]["sent"] is False
    assert report["request_preview"]["signed"] is False
    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False
    assert any("disabled in Slice 20A" in reason for reason in result.reasons)

    assert_kraken_private_transport_shell_report_is_safe(report)

    print("[OK] preview private request blocks")


def test_theoretical_ready_policy_still_blocks() -> None:
    transport = KrakenPrivateTransportShell(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    result = transport.preview_private_request(make_request())
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False
    assert any("disabled in Slice 20A" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks transport shell")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenPrivateTransportShellError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenPrivateTransportShellError")


def test_invalid_inputs_are_rejected() -> None:
    expect_error(
        "network-capable config rejected",
        lambda: KrakenPrivateTransportShell(
            config=KrakenPrivateTransportShellConfig(
                allow_network_calls=True,
            )
        ),
    )

    expect_error(
        "private-endpoint-capable config rejected",
        lambda: KrakenPrivateTransportShell(
            config=KrakenPrivateTransportShellConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )

    expect_error(
        "missing method name rejected",
        lambda: KrakenPrivateTransportShell().preview_private_request(
            KrakenPrivateTransportPreviewRequest(
                method_name="",
                path_name="private_order_preview_path",
            )
        ),
    )

    expect_error(
        "wrong request type rejected",
        lambda: KrakenPrivateTransportShell().preview_private_request(
            object(),  # type: ignore[arg-type]
        ),
    )


def test_source_contains_no_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_transport_shell.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "requests.",
        "httpx.",
        "urllib.",
        "session.",
        ".post(",
        ".get(",
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

    print("[OK] private transport shell source contains no network/private endpoint calls")


def main() -> None:
    print("Slice 20A validation: Disabled Kraken Private Transport Shell")
    print("=" * 80)

    test_transport_capabilities_are_disabled()
    test_preview_private_request_blocks()
    test_theoretical_ready_policy_still_blocks()
    test_invalid_inputs_are_rejected()
    test_source_contains_no_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 20A disabled Kraken private transport shell validation passed.")
    print("[PASS] Private transport shell remains disabled and blocked.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $transportPath -Value $transportContent -Encoding UTF8
Write-Host "[WRITTEN] $transportPath"

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
## Slice 20A — Disabled Kraken Private Transport Shell

Status: Implemented pending validation.

Goal:
Create a disabled private transport shell for future Kraken private HTTP request handling.

Scope:
- Create `tradingagents/execution/kraken_private_transport_shell.py`.
- Create `scripts/test_kraken_private_transport_shell.py`.
- Define safe config, preview request, and result models.
- Define a blocked preview private request method.
- Require activation policy evaluation.
- Validate that no network or private endpoint call exists.

Safety:
- No network call.
- No request signing.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 20A — Disabled Kraken Private Transport Shell

A disabled Kraken private transport shell has been added.

The shell:
- has no HTTP/session object
- has no signing implementation
- has no network request implementation
- blocks private request previews
- requires activation policy evaluation
- reports no network or private endpoint calls
"@

$decisionBlock = @"
## Slice 20A Decision — Add Disabled Private Transport Shell Before Any Network Code

Decision:
Add a disabled Kraken private transport shell before any future network or signing implementation.

Reason:
The system needs a safe transport boundary before any code that could sign or send private requests can be considered.

Result:
The project now has a tested disabled private transport shell with blocked preview methods and no network calls.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 20A — Disabled Kraken Private Transport Shell" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 20A — Disabled Kraken Private Transport Shell" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 20A Decision — Add Disabled Private Transport Shell Before Any Network Code" -Block $decisionBlock

python -m py_compile $transportPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 20A FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_private_transport_shell.py", `
    ".\scripts\test_kraken_private_transport_shell.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 20A script completed."
