$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 19C PRIVATE CLIENT SHELL + PAYLOAD REVIEW INTEGRATION ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$integrationPath = ".\tradingagents\execution\kraken_payload_review_private_client_integration.py"
$testPath = ".\scripts\test_kraken_payload_review_private_client_integration.py"

$integrationContent = @'
"""
Slice 19C Kraken payload review + disabled private client shell integration.

This module connects the payload review path to the disabled Kraken private
client shell submit preview.

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

from tradingagents.execution.kraken_payload_review_private_client_shell_types import (
    PLACEHOLDER_IMPORT_NOTE,
)
from tradingagents.execution.kraken_private_client_shell import (
    KrakenPrivateClientShell,
    KrakenPrivateClientShellResult,
    assert_kraken_private_client_shell_report_is_safe,
)
from tradingagents.execution.kraken_order_translation_adapter_integration import (
    KrakenOrderTranslationAdapterIntegrationResult,
    build_translate_and_route_to_kraken_skeleton,
)


class KrakenPayloadReviewPrivateClientIntegrationError(ValueError):
    """Raised when payload review/private client integration is unsafe."""


@dataclass(frozen=True)
class KrakenPayloadReviewPrivateClientIntegrationResult:
    """Safe-to-log integration result."""

    integration_id: str
    payload_review_result: KrakenOrderTranslationAdapterIntegrationResult
    private_client_result: KrakenPrivateClientShellResult
    final_status: str
    blocked: bool
    execution_allowed: bool
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        payload_review_report = self.payload_review_result.safe_report()
        private_client_report = self.private_client_result.safe_report()

        assert_kraken_private_client_shell_report_is_safe(private_client_report)

        return {
            "integration_id": self.integration_id,
            "final_status": self.final_status,
            "blocked": self.blocked,
            "execution_allowed": False,
            "private_endpoint_called": False,
            "secrets_included": False,
            "command_id": payload_review_report["command_id"],
            "request_id": payload_review_report["request_id"],
            "audit_id": payload_review_report["audit_id"],
            "package_id": payload_review_report["package_id"],
            "kraken_payload": payload_review_report["translation_payload"],
            "payload_review_report": payload_review_report,
            "private_client_report": private_client_report,
        }


def build_payload_review_and_route_to_private_client_shell(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    audit_file_path: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    metadata: Mapping[str, Any] | None = None,
    private_client: KrakenPrivateClientShell | None = None,
) -> KrakenPayloadReviewPrivateClientIntegrationResult:
    """
    Build a Kraken-style validate=true payload review and route that preview
    payload into the disabled private client shell.

    No endpoint is called.
    """

    payload_review_result = build_translate_and_route_to_kraken_skeleton(
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        audit_file_path=audit_file_path,
        env=env,
        metadata={
            **dict(metadata or {}),
            "source": "slice_19c_payload_review_private_client_integration",
        },
    )

    selected_client = private_client or KrakenPrivateClientShell()
    payload = payload_review_result.translation_result.payload

    private_client_result = selected_client.submit_private_order_preview(payload)

    result = KrakenPayloadReviewPrivateClientIntegrationResult(
        integration_id=f"kraken_payload_private_client_{uuid4().hex}",
        payload_review_result=payload_review_result,
        private_client_result=private_client_result,
        final_status="kraken_payload_review_private_client_shell_blocked",
        blocked=True,
        execution_allowed=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_integration_report_is_safe(result.safe_report())

    return result


def assert_integration_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that the integration report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenPayloadReviewPrivateClientIntegrationError(
            "Integration report must not include secrets."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenPayloadReviewPrivateClientIntegrationError(
            "Integration report must not report private endpoint calls."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPayloadReviewPrivateClientIntegrationError(
            "Integration report must not allow execution."
        )

    private_client_report = dict(report.get("private_client_report") or {})
    assert_kraken_private_client_shell_report_is_safe(private_client_report)

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
            raise KrakenPayloadReviewPrivateClientIntegrationError(
                f"Unsafe secret-like term detected: {term}"
            )
'@

# Remove accidental placeholder import by writing a clean version after generating
$integrationContent = $integrationContent.Replace("from tradingagents.execution.kraken_payload_review_private_client_shell_types import (`n    PLACEHOLDER_IMPORT_NOTE,`n)`r`n", "")
$integrationContent = $integrationContent.Replace("from tradingagents.execution.kraken_payload_review_private_client_shell_types import (`r`n    PLACEHOLDER_IMPORT_NOTE,`r`n)`r`n", "")
$integrationContent = $integrationContent.Replace("from tradingagents.execution.kraken_payload_review_private_client_shell_types import (`n    PLACEHOLDER_IMPORT_NOTE,`n)`n", "")
$integrationContent = $integrationContent.Replace("from tradingagents.execution.kraken_payload_review_private_client_shell_types import (    PLACEHOLDER_IMPORT_NOTE,)", "")

$testContent = @'
"""
Validation script for Slice 19C.

This validates the payload review + disabled private client shell integration.

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

from tradingagents.execution.kraken_payload_review_private_client_integration import (
    assert_integration_report_is_safe,
    build_payload_review_and_route_to_private_client_shell,
)
from tradingagents.execution.kraken_private_client_shell import KrakenPrivateClientShell


def test_limit_payload_review_routes_to_private_client_shell() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_private_client.jsonl"

        result = build_payload_review_and_route_to_private_client_shell(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_19c_test"},
        )

        report = result.safe_report()
        payload = report["kraken_payload"]
        private_client_report = report["private_client_report"]

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert report["secrets_included"] is False
        assert payload["pair"] == "XBT/CAD"
        assert payload["type"] == "buy"
        assert payload["ordertype"] == "limit"
        assert payload["volume"] == "0.000085168"
        assert payload["price"] == "100000"
        assert payload["validate"] is True
        assert private_client_report["blocked"] is True
        assert private_client_report["operation"] == "submit_private_order_preview"
        assert private_client_report["private_endpoint_called"] is False
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] limit payload review routes to private client shell safely")


def test_market_payload_review_routes_to_private_client_shell() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_private_client_market.jsonl"

        result = build_payload_review_and_route_to_private_client_shell(
            pair="SOL/CAD",
            side="sell",
            order_type="market",
            volume=Decimal("0.1"),
            limit_price=None,
            audit_file_path=audit_path,
            metadata={"source": "slice_19c_test"},
        )

        report = result.safe_report()
        payload = report["kraken_payload"]

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert payload["pair"] == "SOL/CAD"
        assert payload["type"] == "sell"
        assert payload["ordertype"] == "market"
        assert payload["volume"] == "0.1"
        assert payload["price"] is None
        assert payload["validate"] is True
        assert report["private_client_report"]["blocked"] is True
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] market payload review routes to private client shell safely")


def test_custom_private_client_still_blocks() -> None:
    client = KrakenPrivateClientShell()

    result = build_payload_review_and_route_to_private_client_shell(
        pair="ETH/CAD",
        side="buy",
        order_type="limit",
        volume="0.01",
        limit_price="5000",
        private_client=client,
        metadata={"source": "slice_19c_test"},
    )

    report = result.safe_report()

    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False
    assert client.private_endpoint_called is False
    assert report["kraken_payload"]["pair"] == "ETH/CAD"
    assert report["private_client_report"]["private_endpoint_called"] is False

    print("[OK] custom private client still blocks")


def expect_error(label: str, func) -> None:
    try:
        func()
    except Exception as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected failure")


def test_invalid_inputs_fail_safely() -> None:
    expect_error(
        "unsupported pair rejected",
        lambda: build_payload_review_and_route_to_private_client_shell(
            pair="DOGE/CAD",
            side="buy",
            order_type="limit",
            volume="1",
            limit_price="1",
        ),
    )

    expect_error(
        "invalid side rejected",
        lambda: build_payload_review_and_route_to_private_client_shell(
            pair="BTC/CAD",
            side="hold",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
        ),
    )

    expect_error(
        "missing limit price rejected",
        lambda: build_payload_review_and_route_to_private_client_shell(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price=None,
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_payload_review_private_client_integration.py"
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
    print("Slice 19C validation: Payload Review + Private Client Shell Integration")
    print("=" * 80)

    test_limit_payload_review_routes_to_private_client_shell()
    test_market_payload_review_routes_to_private_client_shell()
    test_custom_private_client_still_blocks()
    test_invalid_inputs_fail_safely()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 19C payload review private client integration validation passed.")
    print("[PASS] Payload review routes through disabled private client shell safely.")
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
## Slice 19C — Private Client Shell Integration with Payload Review CLI

Status: Implemented pending validation.

Goal:
Connect the Kraken payload review path to the disabled Kraken private client shell.

Scope:
- Create `tradingagents/execution/kraken_payload_review_private_client_integration.py`.
- Create `scripts/test_kraken_payload_review_private_client_integration.py`.
- Build Kraken-style validate=true payload review.
- Route payload into `KrakenPrivateClientShell.submit_private_order_preview`.
- Return a blocked safe integration report.
- Validate that no private endpoint call exists.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 19C — Payload Review + Private Client Shell Integration

The Kraken payload review path now integrates with the disabled private client shell.

The integration:
- builds a validate=true Kraken-style review payload
- sends that payload to the private client shell preview method
- returns a blocked safe report
- does not call Kraken
- does not enable execution
"@

$decisionBlock = @"
## Slice 19C Decision — Connect Payload Review to Disabled Private Client Shell

Decision:
Connect the Kraken payload review path to the disabled private client shell.

Reason:
Before any private implementation can be considered, the review payload and private client boundary must be tested together.

Result:
The project can now route a reviewed Kraken-style payload into the disabled private client shell while remaining blocked.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 19C — Private Client Shell Integration with Payload Review CLI" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 19C — Payload Review + Private Client Shell Integration" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 19C Decision — Connect Payload Review to Disabled Private Client Shell" -Block $decisionBlock

python -m py_compile $integrationPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 19C FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_payload_review_private_client_integration.py", `
    ".\scripts\test_kraken_payload_review_private_client_integration.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 19C script completed."
