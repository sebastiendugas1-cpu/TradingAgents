
$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15A MANUAL LIVE ORDER SIMULATION PACKAGE ==="

$Root = "D:\Trading\TradingAgents"
Set-Location $Root

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null
New-Item -ItemType Directory -Force ".\docs" | Out-Null

$initPath = ".\tradingagents\execution\__init__.py"
if (-not (Test-Path $initPath)) {
@'
"""
Execution safety package.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] $initPath"
} else {
    Write-Host "[SKIPPED] $initPath already exists; preserving current package exports."
}

@'
"""
Manual live order simulation package.

Slice 15A purpose:
- Connect the existing manual execution safety layers into one safe simulation package.
- Produce a final execution-style package without placing or canceling any live order.
- Keep all behavior safe to log.
- Keep all future live execution blocked unless later slices intentionally add it.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT require trading, funding, or withdrawal permissions.
"""

from __future__ import annotations

import inspect
from dataclasses import asdict, dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.safety_config import (
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


class ManualLiveOrderSimulationError(SafetyConfigError):
    """Raised when a manual live order simulation package is invalid or blocked."""


@dataclass(frozen=True)
class ManualLiveOrderSimulationInput:
    """
    Input used to build a safe manual live order simulation package.

    This is not an executable live order.
    """

    pair: str
    side: str
    order_type: str
    volume: str
    limit_price: str | None = None
    quote_currency: str = "CAD"
    proposal_id: str = ""
    approval_id: str = ""
    strategy_name: str = ""
    risk_summary: str = ""
    operator_note: str = ""


@dataclass(frozen=True)
class SimulationComponentStatus:
    """Status for one component of the simulated manual execution flow."""

    name: str
    status: str
    blocked: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class ManualLiveOrderSimulationPackage:
    """
    Safe-to-log simulation package.

    This package intentionally does not contain credentials or executable endpoint calls.
    """

    simulation_id: str
    status: str
    blocked: bool
    simulation_only: bool
    order_intent: dict[str, str]
    components: tuple[SimulationComponentStatus, ...]
    blocked_reasons: tuple[str, ...]
    safe_to_log: bool
    secrets_included: bool
    execution_endpoint_called: bool

    def assert_not_executable(self) -> None:
        """Always block execution in Slice 15A."""
        raise ManualLiveOrderSimulationError(
            "Slice 15A produces simulation packages only. Live execution is not implemented."
        )

    def safe_report(self) -> dict[str, Any]:
        """Return a safe-to-log summary."""

        return {
            "simulation_id": self.simulation_id,
            "status": self.status,
            "blocked": self.blocked,
            "simulation_only": self.simulation_only,
            "order_intent": dict(self.order_intent),
            "components": [asdict(component) for component in self.components],
            "blocked_reasons": tuple(self.blocked_reasons),
            "safe_to_log": self.safe_to_log,
            "secrets_included": self.secrets_included,
            "execution_endpoint_called": self.execution_endpoint_called,
        }


def build_manual_live_order_simulation_package(
    simulation_input: ManualLiveOrderSimulationInput,
    *,
    config: LiveExecutionSafetyConfig | None = None,
    env: Mapping[str, str] | None = None,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
) -> ManualLiveOrderSimulationPackage:
    """
    Build a safe end-to-end manual live order simulation package.

    This joins:
    - order intent validation
    - live execution readiness report, when available
    - risk/manual approval readiness flags
    - final simulation-only blocking

    It does not call a live execution endpoint.
    """

    safety_config = config if config is not None else LiveExecutionSafetyConfig.from_env(env)
    order_component = _component_from_order_input(simulation_input)
    readiness_component = _component_from_readiness(
        safety_config=safety_config,
        env=env,
        risk_gate_ready=risk_gate_ready,
        manual_approval_ready=manual_approval_ready,
    )
    dry_run_component = _component_from_dry_run_preview(simulation_input)
    simulation_component = SimulationComponentStatus(
        name="slice_15a_simulation_boundary",
        status="blocked_by_design",
        blocked=True,
        reasons=("Slice 15A is a simulation package only.",),
    )

    components = (
        order_component,
        readiness_component,
        dry_run_component,
        simulation_component,
    )

    blocked_reasons = tuple(
        reason
        for component in components
        if component.blocked
        for reason in component.reasons
    )

    return ManualLiveOrderSimulationPackage(
        simulation_id=f"sim-{uuid4().hex[:12]}",
        status="blocked_simulation_only",
        blocked=True,
        simulation_only=True,
        order_intent=_safe_order_intent(simulation_input),
        components=components,
        blocked_reasons=blocked_reasons,
        safe_to_log=True,
        secrets_included=False,
        execution_endpoint_called=False,
    )


def build_permissive_test_config() -> LiveExecutionSafetyConfig:
    """
    Build a permissive safety config for tests only.

    Even with this config, Slice 15A remains blocked by design.
    """

    return LiveExecutionSafetyConfig(
        live_trading_enabled=True,
        kill_switch=False,
        max_live_trade_value=Decimal("10"),
        explicit_confirmation=LIVE_TRADING_CONFIRMATION_PHRASE,
    )


def _component_from_order_input(
    simulation_input: ManualLiveOrderSimulationInput,
) -> SimulationComponentStatus:
    reasons: list[str] = []

    pair = simulation_input.pair.strip()
    side = simulation_input.side.strip().lower()
    order_type = simulation_input.order_type.strip().lower()
    volume_text = simulation_input.volume.strip()

    if not pair:
        reasons.append("pair is required.")

    if side not in {"buy", "sell"}:
        reasons.append("side must be buy or sell.")

    if order_type not in {"market", "limit"}:
        reasons.append("order_type must be market or limit.")

    try:
        volume = Decimal(volume_text)
        if volume <= Decimal("0"):
            reasons.append("volume must be greater than zero.")
    except (InvalidOperation, ValueError):
        reasons.append("volume must be a valid decimal number.")

    if order_type == "limit":
        if not simulation_input.limit_price:
            reasons.append("limit_price is required for limit orders.")
        else:
            try:
                limit_price = Decimal(simulation_input.limit_price.strip())
                if limit_price <= Decimal("0"):
                    reasons.append("limit_price must be greater than zero.")
            except (InvalidOperation, ValueError, AttributeError):
                reasons.append("limit_price must be a valid decimal number.")

    return SimulationComponentStatus(
        name="order_intent",
        status="blocked" if reasons else "ready_for_simulation",
        blocked=bool(reasons),
        reasons=tuple(reasons),
    )


def _component_from_readiness(
    *,
    safety_config: LiveExecutionSafetyConfig,
    env: Mapping[str, str] | None,
    risk_gate_ready: bool,
    manual_approval_ready: bool,
) -> SimulationComponentStatus:
    """
    Use Slice 14D readiness if available.

    This function is intentionally defensive because earlier slices may evolve names
    or signatures while preserving the same safety meaning.
    """

    try:
        from tradingagents.execution.manual_live_execution_readiness import (
            build_manual_live_execution_readiness_report,
        )
    except Exception as exc:  # pragma: no cover - defensive fallback
        return SimulationComponentStatus(
            name="manual_live_execution_readiness",
            status="blocked",
            blocked=True,
            reasons=(f"Readiness report import failed: {type(exc).__name__}",),
        )

    kwargs: dict[str, Any] = {}
    signature = inspect.signature(build_manual_live_execution_readiness_report)

    if "config" in signature.parameters:
        kwargs["config"] = safety_config
    if "env" in signature.parameters:
        kwargs["env"] = env
    if "risk_gate_ready" in signature.parameters:
        kwargs["risk_gate_ready"] = risk_gate_ready
    if "manual_approval_ready" in signature.parameters:
        kwargs["manual_approval_ready"] = manual_approval_ready

    try:
        readiness_report = build_manual_live_execution_readiness_report(**kwargs)
    except Exception as exc:
        return SimulationComponentStatus(
            name="manual_live_execution_readiness",
            status="blocked",
            blocked=True,
            reasons=(f"Readiness report failed safely: {type(exc).__name__}",),
        )

    blocked = bool(getattr(readiness_report, "blocked", True))
    status = str(getattr(readiness_report, "status", "blocked"))

    reasons: list[str] = []
    for attr in ("blocked_reasons", "reasons"):
        value = getattr(readiness_report, attr, None)
        if value:
            reasons.extend(str(item) for item in value)

    components = getattr(readiness_report, "components", tuple())
    for component in components:
        if getattr(component, "blocked", False):
            component_reasons = getattr(component, "reasons", tuple())
            reasons.extend(str(item) for item in component_reasons)

    if blocked and not reasons:
        reasons.append("Manual live execution readiness report is blocked.")

    return SimulationComponentStatus(
        name="manual_live_execution_readiness",
        status=status,
        blocked=blocked,
        reasons=tuple(dict.fromkeys(reasons)),
    )


def _component_from_dry_run_preview(
    simulation_input: ManualLiveOrderSimulationInput,
) -> SimulationComponentStatus:
    """
    Represent the existing dry-run preview layer as part of the package.

    This deliberately does not import or call any private execution client.
    """

    reasons = (
        "Dry-run preview is represented for simulation only.",
        "No private execution endpoint is called.",
    )

    if simulation_input.order_type.strip().lower() == "limit":
        status = "preview_ready_for_simulation"
    else:
        status = "preview_ready_for_simulation"

    return SimulationComponentStatus(
        name="kraken_dry_run_order_preview",
        status=status,
        blocked=False,
        reasons=reasons,
    )


def _safe_order_intent(
    simulation_input: ManualLiveOrderSimulationInput,
) -> dict[str, str]:
    """Return sanitized order-intent fields only."""

    return {
        "pair": simulation_input.pair.strip(),
        "side": simulation_input.side.strip().lower(),
        "order_type": simulation_input.order_type.strip().lower(),
        "volume": simulation_input.volume.strip(),
        "limit_price": (simulation_input.limit_price or "").strip(),
        "quote_currency": simulation_input.quote_currency.strip().upper(),
        "proposal_id": simulation_input.proposal_id.strip(),
        "approval_id": simulation_input.approval_id.strip(),
        "strategy_name": simulation_input.strategy_name.strip(),
    }


def assert_report_has_no_secret_terms(report: Mapping[str, Any]) -> None:
    """Validate that a report does not contain obvious secret-bearing terms."""

    report_text = str(report).lower()
    forbidden_terms = (
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "secret=",
    )

    for term in forbidden_terms:
        if term in report_text:
            raise ManualLiveOrderSimulationError(
                f"Unsafe report contains forbidden term: {term}"
            )
'@ | Set-Content -Path ".\tradingagents\execution\manual_live_order_simulation_package.py" -Encoding UTF8
Write-Host "[WRITTEN] .\tradingagents\execution\manual_live_order_simulation_package.py"

@'
"""
Validation script for Slice 15A.

This validates an end-to-end manual live order simulation package.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationError,
    ManualLiveOrderSimulationInput,
    assert_report_has_no_secret_terms,
    build_manual_live_order_simulation_package,
    build_permissive_test_config,
)


def expect_simulation_error(label: str, func) -> None:
    try:
        func()
    except ManualLiveOrderSimulationError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualLiveOrderSimulationError")


def sample_limit_input() -> ManualLiveOrderSimulationInput:
    return ManualLiveOrderSimulationInput(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume="0.000085168",
        limit_price="100000",
        quote_currency="CAD",
        proposal_id="proposal-test-001",
        approval_id="approval-test-001",
        strategy_name="slice-15a-simulation",
        risk_summary="test risk summary",
        operator_note="simulation only",
    )


def test_default_package_is_blocked_and_safe() -> None:
    package = build_manual_live_order_simulation_package(sample_limit_input())
    report = package.safe_report()

    assert package.blocked is True
    assert package.simulation_only is True
    assert package.status == "blocked_simulation_only"
    assert package.safe_to_log is True
    assert package.secrets_included is False
    assert package.execution_endpoint_called is False
    assert report["execution_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["order_intent"]["pair"] == "BTC/CAD"
    assert report["order_intent"]["volume"] == "0.000085168"

    component_names = {component.name for component in package.components}
    assert "order_intent" in component_names
    assert "manual_live_execution_readiness" in component_names
    assert "kraken_dry_run_order_preview" in component_names
    assert "slice_15a_simulation_boundary" in component_names

    assert_report_has_no_secret_terms(report)
    expect_simulation_error(
        "simulation package cannot be executed",
        package.assert_not_executable,
    )

    print("[OK] default simulation package is blocked and safe")


def test_permissive_config_still_simulation_only() -> None:
    package = build_manual_live_order_simulation_package(
        sample_limit_input(),
        config=build_permissive_test_config(),
        risk_gate_ready=True,
        manual_approval_ready=True,
    )

    assert package.blocked is True
    assert package.simulation_only is True
    assert package.status == "blocked_simulation_only"
    assert any(
        component.name == "slice_15a_simulation_boundary"
        and component.status == "blocked_by_design"
        for component in package.components
    )

    print("[OK] permissive config still produces simulation-only package")


def test_bad_order_input_is_rejected_in_component() -> None:
    bad_input = ManualLiveOrderSimulationInput(
        pair="",
        side="hold",
        order_type="limit",
        volume="0",
        limit_price="",
    )

    package = build_manual_live_order_simulation_package(bad_input)

    order_component = [
        component for component in package.components if component.name == "order_intent"
    ][0]

    assert order_component.blocked is True
    assert "pair is required." in order_component.reasons
    assert "side must be buy or sell." in order_component.reasons
    assert "volume must be greater than zero." in order_component.reasons
    assert "limit_price is required for limit orders." in order_component.reasons

    print("[OK] invalid order input is captured as blocked component")


def test_dangerous_environment_keeps_package_blocked() -> None:
    package = build_manual_live_order_simulation_package(
        sample_limit_input(),
        env={"KRAKEN_WITHDRAW_PERMISSION": "true"},
    )

    readiness_component = [
        component
        for component in package.components
        if component.name == "manual_live_execution_readiness"
    ][0]

    assert readiness_component.blocked is True
    assert any("Dangerous" in reason for reason in readiness_component.reasons)
    assert package.blocked is True

    print("[OK] dangerous environment keeps simulation package blocked")


def test_report_does_not_leak_secrets() -> None:
    package = build_manual_live_order_simulation_package(
        sample_limit_input(),
        env={
            "KRAKEN_API_KEY": "SHOULD_NOT_APPEAR",
            "KRAKEN_API_SECRET": "SHOULD_NOT_APPEAR",
        },
    )

    report = package.safe_report()
    report_text = str(report)

    assert "SHOULD_NOT_APPEAR" not in report_text
    assert_report_has_no_secret_terms(report)

    print("[OK] simulation report is safe to log")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    from pathlib import Path

    source = Path(
        "tradingagents/execution/manual_live_order_simulation_package.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdrawfunds",
        "depositmethods",
        "wallettransfer",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] simulation source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15A validation: Manual Live Order Simulation Package")
    print("=" * 80)

    test_default_package_is_blocked_and_safe()
    test_permissive_config_still_simulation_only()
    test_bad_order_input_is_rejected_in_component()
    test_dangerous_environment_keeps_package_blocked()
    test_report_does_not_leak_secrets()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15A manual live order simulation package validation passed.")
    print("[PASS] End-to-end manual execution flow is represented safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@ | Set-Content -Path ".\scripts\test_manual_live_order_simulation_package.py" -Encoding UTF8
Write-Host "[WRITTEN] .\scripts\test_manual_live_order_simulation_package.py"

function Add-DocBlockIfMissing {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    $existing = ""
    if (Test-Path $Path) {
        $existing = Get-Content -Path $Path -Raw
    }

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value ""
        Add-Content -Path $Path -Value $Block
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @'
## Slice 15A — Manual Live Order Simulation Package

Status: Implemented pending validation.

Goal:
Connect the existing safety and manual-execution layers into one safe end-to-end simulation package.

Scope:
- Builds a manual live order simulation package.
- Validates order intent.
- Includes manual live execution readiness status.
- Includes dry-run preview representation.
- Keeps the final result blocked by design.
- Does not place or cancel live orders.
- Does not call private execution endpoints.
- Does not require trading, funding, or withdrawal permissions.

Files introduced:
- `tradingagents/execution/manual_live_order_simulation_package.py`
- `scripts/test_manual_live_order_simulation_package.py`

Validation:
- Confirms default package is blocked.
- Confirms permissive config remains simulation-only.
- Confirms invalid order input is captured.
- Confirms dangerous environment terms keep the package blocked.
- Confirms no secrets are printed.
- Confirms no private execution endpoint names are introduced.
'@

$controlsBlock = @'
## Slice 15A — Manual Live Order Simulation Package

Slice 15A connects the manual execution pipeline into a safe simulation package.

The package combines:
- order intent validation
- live execution readiness reporting
- dry-run preview representation
- a final simulation-only boundary

This slice remains blocked by design.

Current restrictions:
- No live order placement.
- No live order cancellation.
- No private execution endpoint calls.
- No funding behavior.
- No withdrawal behavior.
- No trading API permission requirement.

The output is safe to log and does not include secrets.
'@

$decisionBlock = @'
## Slice 15A Decision — Simulate the Full Manual Execution Flow Before Live Execution

Decision:
Before introducing any real live order path, the project will first build an end-to-end manual live order simulation package.

Reason:
The project now has safety config, a disabled live execution client skeleton, permission preflight, readiness reporting, risk gates, manual approval, and dry-run order preview. The next practical step is to connect these pieces into one simulated manual execution package.

Result:
The system can represent the final manual execution flow without calling any private execution endpoint. This gives a safer test target before future live execution work.
'@

Add-DocBlockIfMissing -Path ".\docs\03_ROADMAP.md" -Marker "Slice 15A — Manual Live Order Simulation Package" -Block $roadmapBlock
Add-DocBlockIfMissing -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 15A — Manual Live Order Simulation Package" -Block $controlsBlock
Add-DocBlockIfMissing -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 15A Decision" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15A FILES ==="
Get-Item `
    ".\tradingagents\execution\manual_live_order_simulation_package.py", `
    ".\scripts\test_manual_live_order_simulation_package.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15A script completed."
