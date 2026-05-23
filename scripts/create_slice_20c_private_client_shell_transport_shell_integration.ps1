$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 20C PRIVATE CLIENT SHELL + TRANSPORT SHELL INTEGRATION ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$integrationPath = ".\tradingagents\execution\kraken_private_client_transport_integration.py"
$testPath = ".\scripts\test_kraken_private_client_transport_integration.py"

if (-not (Test-Path ".\tradingagents\execution\kraken_private_client_shell.py")) {
    throw "Missing private client shell module from Slice 19A."
}

if (-not (Test-Path ".\tradingagents\execution\kraken_private_transport_shell.py")) {
    throw "Missing private transport shell module from Slice 20A."
}

$integrationContent = @'
"""
Slice 20C private client shell + private transport shell integration.

This module connects the disabled Kraken private client shell boundary to the
disabled Kraken private transport shell boundary.

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

from dataclasses import dataclass
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.kraken_private_client_shell import KrakenPrivateClientShell
from tradingagents.execution.kraken_private_transport_shell import (
    KrakenPrivateTransportPreviewRequest,
    KrakenPrivateTransportShell,
    assert_kraken_private_transport_shell_report_is_safe,
)


class KrakenPrivateClientTransportIntegrationError(ValueError):
    """Raised when the safe disabled integration detects an unsafe result."""


@dataclass(frozen=True)
class KrakenPrivateClientTransportIntegrationResult:
    """Safe blocked result for the private client to transport integration."""

    integration_id: str
    operation: str
    status: str
    blocked: bool
    message: str
    private_client_report: Mapping[str, Any]
    transport_report: Mapping[str, Any]
    transport_preview_result: Mapping[str, Any]
    execution_allowed: bool = False
    network_call_made: bool = False
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "integration_id": self.integration_id,
            "operation": self.operation,
            "status": self.status,
            "blocked": self.blocked,
            "message": self.message,
            "private_client_report": dict(self.private_client_report),
            "transport_report": dict(self.transport_report),
            "transport_preview_result": dict(self.transport_preview_result),
            "execution_allowed": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "secrets_included": False,
        }


def build_private_client_transport_preview(
    *,
    private_client: KrakenPrivateClientShell | None = None,
    transport: KrakenPrivateTransportShell | None = None,
    payload_preview: Mapping[str, Any] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> KrakenPrivateClientTransportIntegrationResult:
    """
    Route a safe preview from the disabled private client shell boundary into
    the disabled private transport shell boundary.

    No endpoint is called. No network call is made. No request is signed.
    """

    private_client = private_client or KrakenPrivateClientShell()
    transport = transport or KrakenPrivateTransportShell()

    private_client_report = _safe_private_client_report(private_client)

    request = KrakenPrivateTransportPreviewRequest(
        method_name="private_client_shell_submit_preview",
        path_name="private_transport_shell_preview_path",
        payload_preview=dict(payload_preview or {}),
        metadata={
            "slice": "20C",
            "source": "kraken_private_client_transport_integration",
            **dict(metadata or {}),
        },
    )

    transport_preview = transport.preview_private_request(request)
    transport_preview_report = transport_preview.safe_report()
    transport_report = transport.safe_report()

    assert_kraken_private_transport_shell_report_is_safe(transport_preview_report)
    assert_kraken_private_transport_shell_report_is_safe(transport_report)

    result = KrakenPrivateClientTransportIntegrationResult(
        integration_id=f"kraken_private_client_transport_{uuid4().hex}",
        operation="private_client_shell_to_transport_shell_preview",
        status="blocked",
        blocked=True,
        message=(
            "Private client shell to private transport shell integration is "
            "blocked and non-executable."
        ),
        private_client_report=private_client_report,
        transport_report=transport_report,
        transport_preview_result=transport_preview_report,
        execution_allowed=False,
        network_call_made=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_private_client_transport_integration_report_is_safe(result.safe_report())

    return result


def _safe_private_client_report(
    private_client: KrakenPrivateClientShell,
) -> dict[str, Any]:
    """
    Build a safe private client shell report without invoking private execution.

    The private client shell API is intentionally disabled. This helper only
    uses safe reporting/capability methods.
    """

    report: dict[str, Any] = {}

    if hasattr(private_client, "safe_report"):
        maybe_report = private_client.safe_report()
        if isinstance(maybe_report, Mapping):
            report.update(dict(maybe_report))

    if hasattr(private_client, "capabilities"):
        maybe_capabilities = private_client.capabilities()
        if isinstance(maybe_capabilities, Mapping):
            report["capabilities"] = dict(maybe_capabilities)

    report.setdefault("enabled", False)
    report.setdefault("dry_run_only", True)
    report.setdefault("blocked", True)
    report.setdefault("execution_allowed", False)
    report.setdefault("private_endpoint_called", False)
    report.setdefault("network_call_made", False)
    report.setdefault("secrets_included", False)
    report.setdefault("source", "KrakenPrivateClientShell")

    return report


def assert_private_client_transport_integration_report_is_safe(
    report: Mapping[str, Any],
) -> None:
    """Validate that the integration report is safe to log and non-executable."""

    if report.get("secrets_included") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report includes secrets."
        )

    if report.get("network_call_made") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report indicates a network call."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report indicates a private endpoint call."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPrivateClientTransportIntegrationError(
            "Integration report must not allow execution."
        )

    transport_preview = report.get("transport_preview_result")
    if isinstance(transport_preview, Mapping):
        if transport_preview.get("network_call_made") is not False:
            raise KrakenPrivateClientTransportIntegrationError(
                "Transport preview indicates a network call."
            )

        if transport_preview.get("private_endpoint_called") is not False:
            raise KrakenPrivateClientTransportIntegrationError(
                "Transport preview indicates a private endpoint call."
            )

        if transport_preview.get("execution_allowed") is not False:
            raise KrakenPrivateClientTransportIntegrationError(
                "Transport preview must not allow execution."
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
            raise KrakenPrivateClientTransportIntegrationError(
                f"Unsafe secret-like term detected: {term}"
            )
'@

$testContent = @'
"""
Validation script for Slice 20C.

This validates the disabled Kraken private client shell to private transport
shell integration.

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

from tradingagents.execution.kraken_private_client_transport_integration import (
    KrakenPrivateClientTransportIntegrationError,
    assert_private_client_transport_integration_report_is_safe,
    build_private_client_transport_preview,
)
from tradingagents.execution.kraken_private_transport_shell import KrakenPrivateTransportShell


def make_payload() -> dict[str, object]:
    return {
        "pair": "XBT/CAD",
        "type": "buy",
        "ordertype": "limit",
        "volume": "0.000085168",
        "price": "100000",
        "validate": True,
    }


def test_private_client_transport_preview_blocks_safely() -> None:
    result = build_private_client_transport_preview(payload_preview=make_payload())
    report = result.safe_report()

    assert report["operation"] == "private_client_shell_to_transport_shell_preview"
    assert report["status"] == "blocked"
    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False

    transport_preview = report["transport_preview_result"]
    assert transport_preview["blocked"] is True
    assert transport_preview["operation"] == "preview_private_request"
    assert transport_preview["network_call_made"] is False
    assert transport_preview["private_endpoint_called"] is False
    assert transport_preview["execution_allowed"] is False
    assert transport_preview["secrets_included"] is False
    assert transport_preview["request_preview"]["signed"] is False
    assert transport_preview["request_preview"]["sent"] is False

    assert_private_client_transport_integration_report_is_safe(report)

    print("[OK] private client transport preview blocks safely")


def test_custom_transport_still_blocks_and_records_no_calls() -> None:
    transport = KrakenPrivateTransportShell()

    result = build_private_client_transport_preview(
        transport=transport,
        payload_preview=make_payload(),
        metadata={"source": "slice_20c_test"},
    )
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["execution_allowed"] is False
    assert transport.network_call_made is False
    assert transport.private_endpoint_called is False

    assert_private_client_transport_integration_report_is_safe(report)

    print("[OK] custom transport still blocks and records no calls")


def test_invalid_report_is_rejected() -> None:
    unsafe_reports = [
        {"secrets_included": True},
        {"network_call_made": True},
        {"private_endpoint_called": True},
        {"execution_allowed": True},
        {"transport_preview_result": {"network_call_made": True}},
        {"transport_preview_result": {"private_endpoint_called": True}},
        {"transport_preview_result": {"execution_allowed": True}},
        {"api_key": "not-allowed"},
    ]

    for unsafe_report in unsafe_reports:
        try:
            assert_private_client_transport_integration_report_is_safe(unsafe_report)
        except KrakenPrivateClientTransportIntegrationError:
            continue

        raise AssertionError(f"Unsafe report was not rejected: {unsafe_report}")

    print("[OK] unsafe integration reports are rejected")


def test_source_contains_no_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_client_transport_integration.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "requests.get(",
        "requests.post(",
        "requests.session(",
        "httpx.get(",
        "httpx.post(",
        "httpx.client(",
        "urllib.request",
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

    print("[OK] integration source contains no network/private endpoint calls")


def main() -> None:
    print("Slice 20C validation: Private Client Shell + Transport Shell Integration")
    print("=" * 80)

    test_private_client_transport_preview_blocks_safely()
    test_custom_transport_still_blocks_and_records_no_calls()
    test_invalid_report_is_rejected()
    test_source_contains_no_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 20C private client transport integration validation passed.")
    print("[PASS] Private client shell routes to disabled transport shell safely.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


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
## Slice 20C — Private Client Shell to Transport Shell Integration

Status: Implemented pending validation.

Goal:
Connect the disabled Kraken private client shell boundary to the disabled Kraken private transport shell boundary.

Scope:
- Create `tradingagents/execution/kraken_private_client_transport_integration.py`.
- Create `scripts/test_kraken_private_client_transport_integration.py`.
- Route a safe payload preview through the disabled transport shell.
- Preserve blocked, non-executable behavior.
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
## Slice 20C — Private Client Shell to Transport Shell Integration

A disabled integration has been added between:
- Kraken private client shell
- Kraken private transport shell

The integration:
- routes preview payloads only
- returns blocked safe reports
- confirms no request is signed
- confirms no request is sent
- confirms no network/private endpoint call is made
"@

$decisionBlock = @"
## Slice 20C Decision — Connect Disabled Private Client Boundary to Disabled Transport Boundary

Decision:
Add a disabled integration between the private client shell and private transport shell.

Reason:
Before future signing or transport work, the system needs a tested boundary proving the private client can route to transport while remaining blocked and non-executable.

Result:
The project now has a tested client-to-transport integration with no network calls, no private endpoint calls, and no live trading.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 20C — Private Client Shell to Transport Shell Integration" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 20C — Private Client Shell to Transport Shell Integration" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 20C Decision — Connect Disabled Private Client Boundary to Disabled Transport Boundary" -Block $decisionBlock

python -m py_compile $integrationPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 20C FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_private_client_transport_integration.py", `
    ".\scripts\test_kraken_private_client_transport_integration.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 20C script completed."
