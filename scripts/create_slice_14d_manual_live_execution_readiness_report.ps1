# Slice 14D - Manual Live Execution Readiness Report
# Creates a safe readiness report that combines the existing safety layers.
# This script does not enable live trading and does not call Kraken execution endpoints.

$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 14D MANUAL LIVE EXECUTION READINESS REPORT ==="

$Root = Get-Location
$ExecutionDir = Join-Path $Root "tradingagents\execution"
$ScriptsDir = Join-Path $Root "scripts"
$DocsDir = Join-Path $Root "docs"

New-Item -ItemType Directory -Force $ExecutionDir | Out-Null
New-Item -ItemType Directory -Force $ScriptsDir | Out-Null

$InitPath = Join-Path $ExecutionDir "__init__.py"
if (Test-Path $InitPath) {
    Write-Host "[SKIPPED] .\tradingagents\execution\__init__.py already exists; preserving current package exports."
} else {
    @'
"""
Execution safety package.

This package contains disabled-by-default execution safety components.
No live trading execution is enabled by default.
"""
'@ | Set-Content -Path $InitPath -Encoding UTF8
    Write-Host "[WRITTEN] .\tradingagents\execution\__init__.py"
}

$ReadinessPath = Join-Path $ExecutionDir "manual_live_execution_readiness.py"
@'
"""
Manual live execution readiness report.

Slice 14D purpose:
- Combine the existing safety layers into one safe-to-log readiness report.
- Report whether future manual live execution is blocked or theoretically ready.
- Keep default behavior blocked.
- Avoid printing secrets.
- Avoid calling Kraken execution endpoints.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT call funding, transfer, or account-moving endpoints.
This module does NOT require trading permissions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping

from tradingagents.execution.kraken_live_execution_client import (
    KrakenLiveExecutionClient,
)
from tradingagents.execution.live_execution_preflight import (
    LiveExecutionPreflight,
    LiveExecutionPreflightResult,
)
from tradingagents.execution.safety_config import (
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


class ManualLiveExecutionReadinessError(ValueError):
    """Raised when readiness data is unsafe or malformed."""


@dataclass(frozen=True)
class ReadinessComponentStatus:
    """Safe status for one readiness component."""

    name: str
    status: str
    blocked: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)

    def safe_report(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "blocked": self.blocked,
            "reasons": list(self.reasons),
        }


@dataclass(frozen=True)
class ManualLiveExecutionReadinessReport:
    """Safe-to-log combined readiness report."""

    live_execution_blocked: bool
    theoretically_ready: bool
    components: tuple[ReadinessComponentStatus, ...]
    secrets_included: bool = False
    execution_endpoint_called: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "live_execution_blocked": self.live_execution_blocked,
            "theoretically_ready": self.theoretically_ready,
            "components": [component.safe_report() for component in self.components],
            "secrets_included": self.secrets_included,
            "execution_endpoint_called": self.execution_endpoint_called,
        }


def build_manual_live_execution_readiness_report(
    *,
    config: LiveExecutionSafetyConfig | None = None,
    env: Mapping[str, str] | None = None,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
) -> ManualLiveExecutionReadinessReport:
    """
    Build a safe readiness report for future manual live execution.

    Defaults are intentionally blocked:
    - safety config defaults to kill switch on and live trading disabled
    - risk gate readiness defaults to false
    - manual approval readiness defaults to false

    This function does not call any Kraken endpoint.
    """

    safety_config = config if config is not None else LiveExecutionSafetyConfig.from_env(env)

    preflight = LiveExecutionPreflight(config=safety_config, env=env)
    preflight_result = preflight.run()

    client = KrakenLiveExecutionClient(safety_config=safety_config)

    components = (
        _component_from_safety_config(safety_config),
        _component_from_preflight(preflight_result),
        _component_from_client(client),
        _component_from_boolean(
            name="risk_gate",
            ready=risk_gate_ready,
            blocked_reason="Risk gate has not been marked ready for live execution.",
        ),
        _component_from_boolean(
            name="manual_approval",
            ready=manual_approval_ready,
            blocked_reason="Manual approval workflow has not been marked ready for live execution.",
        ),
    )

    live_execution_blocked = any(component.blocked for component in components)
    theoretically_ready = not live_execution_blocked

    report = ManualLiveExecutionReadinessReport(
        live_execution_blocked=live_execution_blocked,
        theoretically_ready=theoretically_ready,
        components=components,
        secrets_included=False,
        execution_endpoint_called=False,
    )

    validate_readiness_report_is_safe(report)

    return report


def assert_manual_live_execution_ready(
    *,
    config: LiveExecutionSafetyConfig | None = None,
    env: Mapping[str, str] | None = None,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
) -> ManualLiveExecutionReadinessReport:
    """
    Build readiness report and raise if live execution remains blocked.

    In default project state, this must raise safely.
    """

    report = build_manual_live_execution_readiness_report(
        config=config,
        env=env,
        risk_gate_ready=risk_gate_ready,
        manual_approval_ready=manual_approval_ready,
    )

    if report.live_execution_blocked:
        reasons = []
        for component in report.components:
            reasons.extend(component.reasons)

        joined = "; ".join(reasons) if reasons else "Readiness report is blocked."
        raise ManualLiveExecutionReadinessError(
            f"Manual live execution readiness failed: {joined}"
        )

    return report


def _component_from_safety_config(
    config: LiveExecutionSafetyConfig,
) -> ReadinessComponentStatus:
    reasons: list[str] = []

    try:
        config.validate_config_only()
    except SafetyConfigError as exc:
        reasons.append(str(exc))

    if config.kill_switch:
        reasons.append("KILL_SWITCH is true.")

    if not config.live_trading_enabled:
        reasons.append("LIVE_TRADING_ENABLED is false.")

    if config.max_live_trade_value <= 0:
        reasons.append("MAX_LIVE_TRADE_VALUE is zero or negative.")

    if not config.explicit_confirmation:
        reasons.append("Explicit live trading confirmation is missing.")

    return ReadinessComponentStatus(
        name="safety_config",
        status="blocked" if reasons else "ready",
        blocked=bool(reasons),
        reasons=tuple(reasons),
    )


def _component_from_preflight(
    result: LiveExecutionPreflightResult,
) -> ReadinessComponentStatus:
    return ReadinessComponentStatus(
        name="live_execution_preflight",
        status="ready" if result.allowed else "blocked",
        blocked=not result.allowed,
        reasons=tuple(result.reasons),
    )


def _component_from_client(
    client: KrakenLiveExecutionClient,
) -> ReadinessComponentStatus:
    report = client.safe_report()

    reasons: list[str] = []

    if report.get("live_execution_client_enabled") is not False:
        reasons.append("Live execution client is not disabled as expected.")

    if report.get("execution_endpoint_called") is not False:
        reasons.append("Execution endpoint call was reported.")

    if report.get("secrets_included") is not False:
        reasons.append("Client report included secrets.")

    return ReadinessComponentStatus(
        name="kraken_live_execution_client",
        status="blocked_by_design" if not reasons else "unsafe",
        blocked=True,
        reasons=tuple(reasons or ("Client is disabled by design in Slice 14D.",)),
    )


def _component_from_boolean(
    *,
    name: str,
    ready: bool,
    blocked_reason: str,
) -> ReadinessComponentStatus:
    return ReadinessComponentStatus(
        name=name,
        status="ready" if ready else "blocked",
        blocked=not ready,
        reasons=tuple() if ready else (blocked_reason,),
    )


def validate_readiness_report_is_safe(
    report: ManualLiveExecutionReadinessReport,
) -> None:
    """Validate that a readiness report is safe to log."""

    report_text = str(report.safe_report()).lower()

    forbidden_terms = (
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "token",
        "private key",
        "secret=",
    )

    for term in forbidden_terms:
        if term in report_text:
            raise ManualLiveExecutionReadinessError(
                f"Readiness report contains forbidden secret-related term: {term}"
            )

    if report.secrets_included:
        raise ManualLiveExecutionReadinessError("Readiness report includes secrets.")

    if report.execution_endpoint_called:
        raise ManualLiveExecutionReadinessError(
            "Readiness report says an execution endpoint was called."
        )
'@ | Set-Content -Path $ReadinessPath -Encoding UTF8
Write-Host "[WRITTEN] .\tradingagents\execution\manual_live_execution_readiness.py"

$TestPath = Join-Path $ScriptsDir "test_manual_live_execution_readiness_report.py"
@'
"""
Validation script for Slice 14D.

This script validates the manual live execution readiness report.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path

from tradingagents.execution.manual_live_execution_readiness import (
    ManualLiveExecutionReadinessError,
    assert_manual_live_execution_ready,
    build_manual_live_execution_readiness_report,
)
from tradingagents.execution.safety_config import (
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
)


def expect_readiness_error(label: str, func) -> None:
    try:
        func()
    except ManualLiveExecutionReadinessError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualLiveExecutionReadinessError")


def test_default_readiness_report_is_blocked() -> None:
    report = build_manual_live_execution_readiness_report()

    assert report.live_execution_blocked is True
    assert report.theoretically_ready is False
    assert report.secrets_included is False
    assert report.execution_endpoint_called is False

    component_names = {component.name for component in report.components}
    assert "safety_config" in component_names
    assert "live_execution_preflight" in component_names
    assert "kraken_live_execution_client" in component_names
    assert "risk_gate" in component_names
    assert "manual_approval" in component_names

    print("[OK] default readiness report is blocked")


def test_default_assert_readiness_blocks() -> None:
    expect_readiness_error(
        "default assert readiness blocks live execution",
        lambda: assert_manual_live_execution_ready(),
    )


def test_permissive_config_still_blocked_by_disabled_client() -> None:
    config = LiveExecutionSafetyConfig(
        live_trading_enabled=True,
        kill_switch=False,
        max_live_trade_value=Decimal("10"),
        explicit_confirmation=LIVE_TRADING_CONFIRMATION_PHRASE,
    )

    report = build_manual_live_execution_readiness_report(
        config=config,
        risk_gate_ready=True,
        manual_approval_ready=True,
    )

    assert report.live_execution_blocked is True
    assert report.theoretically_ready is False

    client_component = next(
        component
        for component in report.components
        if component.name == "kraken_live_execution_client"
    )

    assert client_component.blocked is True
    assert client_component.status == "blocked_by_design"

    print("[OK] permissive config remains blocked by disabled client skeleton")


def test_risk_and_manual_approval_readiness_are_reported() -> None:
    report = build_manual_live_execution_readiness_report(
        risk_gate_ready=False,
        manual_approval_ready=False,
    )

    risk_component = next(
        component for component in report.components if component.name == "risk_gate"
    )
    approval_component = next(
        component for component in report.components if component.name == "manual_approval"
    )

    assert risk_component.blocked is True
    assert approval_component.blocked is True

    report_ready_inputs = build_manual_live_execution_readiness_report(
        risk_gate_ready=True,
        manual_approval_ready=True,
    )

    ready_risk_component = next(
        component
        for component in report_ready_inputs.components
        if component.name == "risk_gate"
    )
    ready_approval_component = next(
        component
        for component in report_ready_inputs.components
        if component.name == "manual_approval"
    )

    assert ready_risk_component.blocked is False
    assert ready_approval_component.blocked is False

    print("[OK] risk gate and manual approval readiness are reported")


def test_safe_report_excludes_secrets() -> None:
    report = build_manual_live_execution_readiness_report(
        env={
            "KRAKEN_API_KEY": "should_not_print",
            "KRAKEN_API_SECRET": "should_not_print",
            "LIVE_TRADING_ENABLED": "false",
            "KILL_SWITCH": "true",
            "MAX_LIVE_TRADE_VALUE": "0",
        }
    )

    safe = report.safe_report()
    safe_text = str(safe).lower()

    assert safe["secrets_included"] is False
    assert safe["execution_endpoint_called"] is False

    forbidden_terms = [
        "should_not_print",
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
    ]

    for term in forbidden_terms:
        assert term not in safe_text

    print("[OK] readiness report is safe to log")


def test_dangerous_environment_blocks_readiness() -> None:
    report = build_manual_live_execution_readiness_report(
        env={
            "ENABLE_WITHDRAWAL_FEATURE": "true",
            "LIVE_TRADING_ENABLED": "false",
            "KILL_SWITCH": "true",
            "MAX_LIVE_TRADE_VALUE": "0",
        }
    )

    assert report.live_execution_blocked is True

    preflight_component = next(
        component
        for component in report.components
        if component.name == "live_execution_preflight"
    )

    assert preflight_component.blocked is True
    assert any("Dangerous environment/configuration term" in reason for reason in preflight_component.reasons)

    print("[OK] dangerous environment terms keep readiness blocked")


def test_readiness_source_contains_no_kraken_execution_endpoint_names() -> None:
    source_path = Path("tradingagents/execution/manual_live_execution_readiness.py")
    source = source_path.read_text(encoding="utf-8").lower()

    forbidden_terms = [
        "addorder",
        "cancelorder",
        "withdraw",
        "deposit",
        "tradebalance",
        "ledgers",
    ]

    for term in forbidden_terms:
        assert term not in source

    print("[OK] readiness source contains no Kraken execution endpoint names")


def main() -> None:
    print("Slice 14D validation: Manual Live Execution Readiness Report")
    print("=" * 80)

    test_default_readiness_report_is_blocked()
    test_default_assert_readiness_blocks()
    test_permissive_config_still_blocked_by_disabled_client()
    test_risk_and_manual_approval_readiness_are_reported()
    test_safe_report_excludes_secrets()
    test_dangerous_environment_blocks_readiness()
    test_readiness_source_contains_no_kraken_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 14D manual live execution readiness report validation passed.")
    print("[PASS] Default readiness remains blocked.")
    print("[PASS] No Kraken execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@ | Set-Content -Path $TestPath -Encoding UTF8
Write-Host "[WRITTEN] .\scripts\test_manual_live_execution_readiness_report.py"

function Add-DocBlockIfMissing {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )
    $text = Get-Content -Path $Path -Raw
    if ($text -notmatch [regex]::Escape($Marker)) {
        $text = $text.TrimEnd() + "`r`n`r`n" + $Block.Trim() + "`r`n"
        Set-Content -Path $Path -Value $text -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains Slice 14D block."
    }
}

$RoadmapBlock = @'
## Slice 14D — Manual Live Execution Readiness Report

Status: Implemented pending validation.

Goal:
Create a final readiness report that combines all safety layers before any future manual live execution can be considered.

Scope:
- Report safety configuration status.
- Report live execution preflight status.
- Report disabled Kraken execution client status.
- Report risk gate readiness status.
- Report manual approval readiness status.
- Produce a safe-to-log readiness report.
- Keep default state blocked.
- Do not call Kraken execution endpoints.
- Do not place or cancel orders.
- Do not require trading, funding, or withdrawal permissions.

Files introduced:
- `tradingagents/execution/manual_live_execution_readiness.py`
- `scripts/test_manual_live_execution_readiness_report.py`

Validation:
- Confirms default readiness is blocked.
- Confirms readiness assertion fails safely by default.
- Confirms permissive config remains blocked by the disabled client skeleton.
- Confirms risk gate and manual approval readiness are reported.
- Confirms safe report does not expose secrets.
- Confirms no execution endpoint names are present in readiness source.
'@

$ControlsBlock = @'
## Slice 14D — Manual Live Execution Readiness Report

The project now includes a combined manual live execution readiness report.

The readiness report combines:
- Safety config status.
- Live execution preflight status.
- Disabled Kraken live execution client status.
- Risk gate readiness status.
- Manual approval readiness status.

Default result:
- Live execution remains blocked.
- The report is safe to log.
- No secrets are printed.
- No Kraken execution endpoints are called.
- No trading, funding, or withdrawal permission is required.

This slice is still a safety/reporting slice only. It does not enable live trading.
'@

$DecisionBlock = @'
## Slice 14D Decision — Add Final Manual Live Execution Readiness Report

Decision:
Before any future manual live order slice, the project must provide one combined readiness report across all safety layers.

Reason:
Separate safety layers now exist:
- Live execution safety config.
- Disabled Kraken live execution client skeleton.
- Live execution permission preflight.
- Risk gate engine.
- Manual approval workflow.

A combined report helps confirm whether the full system is still blocked by default or theoretically ready under intentionally configured conditions.

Result:
The default readiness state remains blocked. The report is safe to log, excludes secrets, and does not call execution endpoints.
'@

Add-DocBlockIfMissing -Path ".\docs\03_ROADMAP.md" -Marker "Slice 14D — Manual Live Execution Readiness Report" -Block $RoadmapBlock
Add-DocBlockIfMissing -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 14D — Manual Live Execution Readiness Report" -Block $ControlsBlock
Add-DocBlockIfMissing -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 14D Decision — Add Final Manual Live Execution Readiness Report" -Block $DecisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 14D FILES ==="
Get-Item `
    ".\tradingagents\execution\manual_live_execution_readiness.py", `
    ".\scripts\test_manual_live_execution_readiness_report.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 14D script completed."
