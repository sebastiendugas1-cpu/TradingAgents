$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 18C KRAKEN ORDER TRANSLATOR + ADAPTER SKELETON INTEGRATION ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$integrationPath = ".\tradingagents\execution\kraken_order_translation_adapter_integration.py"
$testPath = ".\scripts\test_kraken_order_translation_adapter_integration.py"

$integrationContent = @'
"""
Slice 18C Kraken order translator + adapter skeleton integration.

This module connects the Kraken-style review payload translator to the disabled
Kraken live adapter skeleton.

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

from tradingagents.execution.execution_adapter import (
    ExecutionAdapterResult,
    SubmitOrderRequest,
    assert_adapter_report_is_safe,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.kraken_live_adapter_skeleton import (
    KrakenLiveAdapterSkeleton,
    assert_kraken_adapter_skeleton_report_is_safe,
)
from tradingagents.execution.kraken_private_order_request_translator import (
    KrakenOrderTranslationResult,
    assert_translation_report_is_safe,
    translate_submit_request_to_kraken_private_order_payload,
)
from tradingagents.execution.manual_execution_command import ManualExecutionCommand
from tradingagents.execution.manual_execution_command_builder import (
    ManualExecutionCommandBuildResult,
    build_manual_execution_command_from_order_intent,
)


class KrakenOrderTranslationAdapterIntegrationError(ValueError):
    """Raised when the integration result is unsafe or invalid."""


@dataclass(frozen=True)
class KrakenOrderTranslationAdapterIntegrationResult:
    """Safe-to-log integration result."""

    integration_id: str
    builder_result: ManualExecutionCommandBuildResult
    command: ManualExecutionCommand
    submit_request: SubmitOrderRequest
    translation_result: KrakenOrderTranslationResult
    adapter_result: ExecutionAdapterResult
    final_status: str
    blocked: bool
    execution_allowed: bool
    private_endpoint_called: bool = False
    secrets_included: bool = False

    def safe_report(self) -> dict[str, Any]:
        translation_report = self.translation_result.safe_report()
        adapter_report = self.adapter_result.safe_report()

        assert_translation_report_is_safe(translation_report)
        assert_adapter_report_is_safe(adapter_report)

        return {
            "integration_id": self.integration_id,
            "builder_id": self.builder_result.builder_id,
            "package_id": self.builder_result.package_id,
            "audit_id": self.builder_result.audit_id,
            "command_id": self.command.command_id,
            "request_id": self.submit_request.request_id,
            "adapter_result_id": self.adapter_result.result_id,
            "final_status": self.final_status,
            "blocked": self.blocked,
            "execution_allowed": False,
            "translation_payload": translation_report["payload"],
            "translation_report": translation_report,
            "adapter_report": adapter_report,
            "secrets_included": False,
            "private_endpoint_called": False,
        }


def build_translate_and_route_to_kraken_skeleton(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    audit_file_path: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    metadata: Mapping[str, Any] | None = None,
    adapter: KrakenLiveAdapterSkeleton | None = None,
) -> KrakenOrderTranslationAdapterIntegrationResult:
    """
    Build a command, translate to a Kraken-style review payload, and route through
    the disabled Kraken adapter skeleton.

    No endpoint is called.
    """

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
            "source": "slice_18c_kraken_translation_adapter_integration",
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

    submit_request = SubmitOrderRequest(
        request_id=f"kraken_translate_submit_{uuid4().hex}",
        command=command,
        readiness_report=build_default_blocked_readiness_report(),
        metadata={
            "source": "slice_18c_kraken_translation_adapter_integration",
            "review_only": True,
        },
    )

    translation_result = translate_submit_request_to_kraken_private_order_payload(
        submit_request,
        userref=command.command_id,
    )

    selected_adapter = adapter or KrakenLiveAdapterSkeleton()
    assert_kraken_adapter_skeleton_report_is_safe(selected_adapter.safe_report())

    adapter_result = selected_adapter.submit_order(submit_request)

    result = KrakenOrderTranslationAdapterIntegrationResult(
        integration_id=f"kraken_translation_adapter_{uuid4().hex}",
        builder_result=builder_result,
        command=command,
        submit_request=submit_request,
        translation_result=translation_result,
        adapter_result=adapter_result,
        final_status="kraken_order_translation_adapter_integration_blocked",
        blocked=True,
        execution_allowed=False,
        private_endpoint_called=False,
        secrets_included=False,
    )

    assert_integration_report_is_safe(result.safe_report())

    return result


def _command_from_builder_result(
    *,
    builder_result: ManualExecutionCommandBuildResult,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None,
) -> ManualExecutionCommand:
    command_report = dict(builder_result.command_report or {})

    command_id = str(command_report.get("command_id") or builder_result.command_id)
    package_id = str(command_report.get("package_id") or builder_result.package_id)
    audit_id = str(command_report.get("audit_id") or builder_result.audit_id)
    status = command_report.get("status") or builder_result.command_status

    if not command_id:
        raise KrakenOrderTranslationAdapterIntegrationError("command_id is required.")
    if not package_id:
        raise KrakenOrderTranslationAdapterIntegrationError("package_id is required.")
    if not audit_id:
        raise KrakenOrderTranslationAdapterIntegrationError("audit_id is required.")

    from tradingagents.execution.manual_execution_command import parse_status

    parsed_status = parse_status(status)

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
            "source": "slice_18c_kraken_translation_adapter_integration",
            "review_only": True,
        },
    )


def assert_integration_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that the integration report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenOrderTranslationAdapterIntegrationError(
            "Integration report must not include secrets."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenOrderTranslationAdapterIntegrationError(
            "Integration report must not report private endpoint calls."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenOrderTranslationAdapterIntegrationError(
            "Integration report must not allow execution."
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
            raise KrakenOrderTranslationAdapterIntegrationError(
                f"Unsafe secret-like term detected: {term}"
            )
'@

$testContent = @'
"""
Validation script for Slice 18C.

This validates the Kraken order translator + disabled adapter skeleton integration.

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

from tradingagents.execution.kraken_live_adapter_skeleton import KrakenLiveAdapterSkeleton
from tradingagents.execution.kraken_order_translation_adapter_integration import (
    assert_integration_report_is_safe,
    build_translate_and_route_to_kraken_skeleton,
)


def test_limit_order_translation_routes_to_disabled_skeleton() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "kraken_translation_adapter.jsonl"

        result = build_translate_and_route_to_kraken_skeleton(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_18c_test"},
        )

        report = result.safe_report()
        payload = report["translation_payload"]

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
        assert report["adapter_report"]["blocked"] is True
        assert report["adapter_report"]["private_endpoint_called"] is False
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] limit order translation routes to disabled skeleton safely")


def test_market_order_translation_routes_to_disabled_skeleton() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "kraken_translation_adapter_market.jsonl"

        result = build_translate_and_route_to_kraken_skeleton(
            pair="SOL/CAD",
            side="sell",
            order_type="market",
            volume=Decimal("0.1"),
            limit_price=None,
            audit_file_path=audit_path,
            metadata={"source": "slice_18c_test"},
        )

        report = result.safe_report()
        payload = report["translation_payload"]

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert payload["pair"] == "SOL/CAD"
        assert payload["type"] == "sell"
        assert payload["ordertype"] == "market"
        assert payload["volume"] == "0.1"
        assert payload["price"] is None
        assert payload["validate"] is True
        assert report["adapter_report"]["blocked"] is True
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] market order translation routes to disabled skeleton safely")


def test_custom_skeleton_still_blocks() -> None:
    adapter = KrakenLiveAdapterSkeleton()

    result = build_translate_and_route_to_kraken_skeleton(
        pair="ETH/CAD",
        side="buy",
        order_type="limit",
        volume="0.01",
        limit_price="5000",
        adapter=adapter,
        metadata={"source": "slice_18c_test"},
    )

    report = result.safe_report()

    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False
    assert adapter.private_endpoint_called is False
    assert report["translation_payload"]["pair"] == "ETH/CAD"

    print("[OK] custom skeleton still blocks")


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
        lambda: build_translate_and_route_to_kraken_skeleton(
            pair="DOGE/CAD",
            side="buy",
            order_type="limit",
            volume="1",
            limit_price="1",
        ),
    )

    expect_error(
        "invalid side rejected",
        lambda: build_translate_and_route_to_kraken_skeleton(
            pair="BTC/CAD",
            side="hold",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
        ),
    )

    expect_error(
        "missing limit price rejected",
        lambda: build_translate_and_route_to_kraken_skeleton(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price=None,
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_order_translation_adapter_integration.py"
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
    print("Slice 18C validation: Kraken Order Translator + Adapter Skeleton Integration")
    print("=" * 80)

    test_limit_order_translation_routes_to_disabled_skeleton()
    test_market_order_translation_routes_to_disabled_skeleton()
    test_custom_skeleton_still_blocks()
    test_invalid_inputs_fail_safely()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 18C Kraken order translator adapter integration validation passed.")
    print("[PASS] Translator routes validate=true payloads through disabled skeleton safely.")
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
## Slice 18C — Kraken Order Translator Integration with Adapter Skeleton

Status: Implemented pending validation.

Goal:
Connect the Kraken order request translator to the disabled Kraken live adapter skeleton.

Scope:
- Create `tradingagents/execution/kraken_order_translation_adapter_integration.py`.
- Create `scripts/test_kraken_order_translation_adapter_integration.py`.
- Build manual command candidates from order intent.
- Build `SubmitOrderRequest`.
- Translate to Kraken-style validate=true review payload.
- Route through disabled `KrakenLiveAdapterSkeleton`.
- Return a blocked safe integration report.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 18C — Kraken Order Translator + Adapter Skeleton Integration

The Kraken-style order payload translator now integrates with the disabled Kraken live adapter skeleton.

The integration:
- builds a command candidate
- builds a submit request
- creates a validate=true Kraken-style review payload
- routes through the disabled skeleton
- returns a blocked safe report
- does not call Kraken
"@

$decisionBlock = @"
## Slice 18C Decision — Connect Kraken Translator to Disabled Adapter Skeleton

Decision:
Connect the Kraken order request translator to the disabled Kraken live adapter skeleton.

Reason:
The translator and skeleton must be tested together before future work can approach any live-capable adapter behavior.

Result:
The project can now prove that a future Kraken order payload can be reviewed and routed through the adapter boundary while remaining blocked.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 18C — Kraken Order Translator Integration with Adapter Skeleton" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 18C — Kraken Order Translator + Adapter Skeleton Integration" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 18C Decision — Connect Kraken Translator to Disabled Adapter Skeleton" -Block $decisionBlock

python -m py_compile $integrationPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 18C FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_order_translation_adapter_integration.py", `
    ".\scripts\test_kraken_order_translation_adapter_integration.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 18C script completed."
