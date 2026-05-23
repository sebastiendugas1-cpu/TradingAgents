# ============================ Slice 13D - Risk Gate Engine ============================
# Purpose:
# Creates a safe pre-execution risk gate for trade proposals.
# This slice does NOT place orders, cancel orders, call Kraken trading endpoints,
# or enable live trading. It only decides whether a manually approved proposal is
# allowed to move to a future dry-run/order-preview step.

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$RiskPath = Join-Path $ProjectRoot "tradingagents\risk"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $RiskPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-ProjectFile (Join-Path $RiskPath "__init__.py") @'
# ============================ Risk Package Exports ============================

from tradingagents.risk.engine import (
    RiskGateConfig,
    RiskGateDecision,
    RiskGateEngine,
    RiskGateResult,
    RiskGateViolation,
)

__all__ = [
    "RiskGateConfig",
    "RiskGateDecision",
    "RiskGateEngine",
    "RiskGateResult",
    "RiskGateViolation",
]
'@

Write-ProjectFile (Join-Path $RiskPath "engine.py") @'
# ============================ Risk Gate Engine ============================
"""
Safe risk-gate logic for manually approved trade proposals.

This layer does not place orders.
This layer does not call Kraken trading endpoints.
This layer does not cancel orders.
This layer does not access funding or withdrawals.

Its only job is to decide whether a proposal is safe enough to move forward to a
future dry-run/order-preview step.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


class RiskGateDecision(str, Enum):
    """Risk gate outcome."""

    APPROVED_FOR_DRY_RUN = "approved_for_dry_run"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class RiskGateViolation:
    """One reason the risk gate blocked a proposal."""

    code: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return asdict(self)


@dataclass(frozen=True)
class RiskGateConfig:
    """Hard safety settings for proposal risk checks."""

    allowed_symbols: tuple[str, ...] = ("BTC/USD", "ETH/USD", "SOL/USD")
    max_trade_value: float = 100.0
    max_risk_score: int = 70
    min_confidence_score: int = 55
    require_manual_approval: bool = True
    kill_switch_enabled: bool = False
    allowed_decision_statuses: tuple[str, ...] = ("paper_trade", "manual_review")
    max_daily_loss_placeholder: float = 25.0
    max_total_exposure_placeholder: float = 500.0

    def __post_init__(self) -> None:
        if self.max_trade_value <= 0:
            raise ValueError("max_trade_value must be greater than zero.")
        if self.max_risk_score < 0 or self.max_risk_score > 100:
            raise ValueError("max_risk_score must be between 0 and 100.")
        if self.min_confidence_score < 0 or self.min_confidence_score > 100:
            raise ValueError("min_confidence_score must be between 0 and 100.")
        if self.max_daily_loss_placeholder < 0:
            raise ValueError("max_daily_loss_placeholder cannot be negative.")
        if self.max_total_exposure_placeholder < 0:
            raise ValueError("max_total_exposure_placeholder cannot be negative.")
        if not self.allowed_symbols:
            raise ValueError("allowed_symbols cannot be empty.")

    @property
    def normalized_allowed_symbols(self) -> set[str]:
        return {symbol.strip().upper() for symbol in self.allowed_symbols if symbol.strip()}


@dataclass(frozen=True)
class RiskGateResult:
    """Safe pre-execution decision produced by the risk gate."""

    decision: RiskGateDecision
    asset: str
    estimated_trade_value: float
    risk_score: int
    confidence_score: int
    violations: tuple[RiskGateViolation, ...] = field(default_factory=tuple)
    notes: tuple[str, ...] = field(default_factory=tuple)

    @property
    def passed(self) -> bool:
        return self.decision == RiskGateDecision.APPROVED_FOR_DRY_RUN

    @property
    def blocked(self) -> bool:
        return self.decision == RiskGateDecision.BLOCKED

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["decision"] = self.decision.value
        data["violations"] = [violation.to_dict() for violation in self.violations]
        return data


class RiskGateEngine:
    """Evaluate whether a trade proposal can proceed to dry-run preview."""

    def __init__(self, config: RiskGateConfig | None = None) -> None:
        self.config = config or RiskGateConfig()

    def evaluate_proposal(self, proposal: Any) -> RiskGateResult:
        """Evaluate a trade proposal using hard safety rules.

        The proposal object is intentionally duck-typed so the gate can work with
        the Slice 13B TradeProposal model and test doubles.
        """

        asset = _normalize_asset(_read_attr(proposal, "asset", ""))
        estimated_trade_value = _read_float(proposal, "estimated_value", default=0.0)
        risk_score = _extract_risk_score(proposal)
        confidence_score = _extract_confidence_score(proposal)
        approval_status = _enum_value(_read_attr(proposal, "approval_status", ""))
        decision_status = _extract_decision_status(proposal)

        violations: list[RiskGateViolation] = []
        notes: list[str] = []

        if self.config.kill_switch_enabled:
            violations.append(
                RiskGateViolation(
                    code="kill_switch_enabled",
                    message="Risk gate kill switch is enabled. No proposal may proceed.",
                )
            )

        if not asset:
            violations.append(RiskGateViolation(code="missing_asset", message="Proposal asset is missing."))
        elif asset not in self.config.normalized_allowed_symbols:
            violations.append(
                RiskGateViolation(
                    code="symbol_not_allowed",
                    message=f"Asset {asset} is not in the configured allowed symbol list.",
                )
            )

        if self.config.require_manual_approval and approval_status != "approved":
            violations.append(
                RiskGateViolation(
                    code="manual_approval_required",
                    message="Proposal must be explicitly manually approved before dry-run preview.",
                )
            )

        if estimated_trade_value <= 0:
            violations.append(
                RiskGateViolation(
                    code="invalid_trade_value",
                    message="Estimated trade value must be greater than zero.",
                )
            )
        elif estimated_trade_value > self.config.max_trade_value:
            violations.append(
                RiskGateViolation(
                    code="trade_value_too_large",
                    message=(
                        f"Estimated trade value {estimated_trade_value:.2f} exceeds "
                        f"limit {self.config.max_trade_value:.2f}."
                    ),
                )
            )

        if risk_score > self.config.max_risk_score:
            violations.append(
                RiskGateViolation(
                    code="risk_score_too_high",
                    message=f"Risk score {risk_score} exceeds limit {self.config.max_risk_score}.",
                )
            )

        if confidence_score < self.config.min_confidence_score:
            violations.append(
                RiskGateViolation(
                    code="confidence_score_too_low",
                    message=(
                        f"Confidence score {confidence_score} is below minimum "
                        f"{self.config.min_confidence_score}."
                    ),
                )
            )

        if decision_status and decision_status not in self.config.allowed_decision_statuses:
            violations.append(
                RiskGateViolation(
                    code="decision_status_not_allowed",
                    message=f"Decision status {decision_status!r} is not allowed by the risk gate.",
                )
            )

        notes.append("Daily loss and total exposure checks are placeholders until live execution accounting exists.")
        notes.append("Passing this gate allows only future dry-run/order-preview workflow, not order placement.")

        decision = RiskGateDecision.BLOCKED if violations else RiskGateDecision.APPROVED_FOR_DRY_RUN

        return RiskGateResult(
            decision=decision,
            asset=asset,
            estimated_trade_value=round(estimated_trade_value, 8),
            risk_score=risk_score,
            confidence_score=confidence_score,
            violations=tuple(violations),
            notes=tuple(notes),
        )


def _read_attr(obj: Any, name: str, default: Any = None) -> Any:
    value = getattr(obj, name, default)
    if callable(value):
        try:
            return value()
        except TypeError:
            return default
    return value


def _read_float(obj: Any, name: str, default: float = 0.0) -> float:
    value = _read_attr(obj, name, default)
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _read_int_from_obj(obj: Any, names: tuple[str, ...], default: int) -> int:
    for name in names:
        value = _read_attr(obj, name, None)
        if value is not None:
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
    return default


def _extract_risk_score(proposal: Any) -> int:
    direct = _read_int_from_obj(proposal, ("risk_score",), default=-1)
    if direct >= 0:
        return direct

    risk_summary = _read_attr(proposal, "risk_summary", None)
    if risk_summary is not None:
        value = _read_int_from_obj(risk_summary, ("risk_score",), default=-1)
        if value >= 0:
            return value

    scorecard = _read_attr(proposal, "strategy_scorecard", None) or _read_attr(proposal, "scorecard", None)
    if scorecard is not None:
        value = _read_int_from_obj(scorecard, ("risk_score",), default=-1)
        if value >= 0:
            return value

    return 50


def _extract_confidence_score(proposal: Any) -> int:
    direct = _read_int_from_obj(proposal, ("confidence_score", "confidence"), default=-1)
    if direct >= 0:
        return direct

    scorecard = _read_attr(proposal, "strategy_scorecard", None) or _read_attr(proposal, "scorecard", None)
    if scorecard is not None:
        value = _read_int_from_obj(scorecard, ("confidence_score", "confidence"), default=-1)
        if value >= 0:
            return value

    return 0


def _extract_decision_status(proposal: Any) -> str:
    scorecard = _read_attr(proposal, "strategy_scorecard", None) or _read_attr(proposal, "scorecard", None)
    if scorecard is not None:
        return _enum_value(_read_attr(scorecard, "action", None) or _read_attr(scorecard, "status", ""))
    return _enum_value(_read_attr(proposal, "decision_status", ""))


def _normalize_asset(asset: Any) -> str:
    return str(asset or "").strip().upper()


def _enum_value(value: Any) -> str:
    raw = getattr(value, "value", value)
    return str(raw or "").strip().lower()
'@

Write-ProjectFile (Join-Path $ScriptsPath "test_risk_gate_engine.py") @'
# ============================ Slice 13D Validation - Risk Gate Engine ============================

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import DecisionStatus  # noqa: E402
from tradingagents.risk import RiskGateConfig, RiskGateDecision, RiskGateEngine  # noqa: E402


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def make_proposal(**overrides):
    data = {
        "asset": "BTC/USD",
        "approval_status": "approved",
        "estimated_value": 50.0,
        "risk_summary": SimpleNamespace(risk_score=35),
        "strategy_scorecard": SimpleNamespace(
            action=DecisionStatus.PAPER_TRADE,
            risk_score=35,
            confidence_score=82,
        ),
    }
    data.update(overrides)
    return SimpleNamespace(**data)


def violation_codes(result):
    return {violation.code for violation in result.violations}


def main() -> int:
    print("Running Slice 13D risk gate engine validation...")

    engine = RiskGateEngine(
        RiskGateConfig(
            allowed_symbols=("BTC/USD", "ETH/USD"),
            max_trade_value=100.0,
            max_risk_score=70,
            min_confidence_score=55,
        )
    )

    passed = engine.evaluate_proposal(make_proposal())
    assert_equal(passed.decision, RiskGateDecision.APPROVED_FOR_DRY_RUN, "safe proposal approved for dry-run only")
    assert_true(passed.passed, "safe proposal passed")
    assert_true(not passed.blocked, "safe proposal not blocked")

    pending = engine.evaluate_proposal(make_proposal(approval_status="pending"))
    assert_equal(pending.decision, RiskGateDecision.BLOCKED, "pending proposal blocked")
    assert_true("manual_approval_required" in violation_codes(pending), "manual approval violation present")

    oversized = engine.evaluate_proposal(make_proposal(estimated_value=150.0))
    assert_equal(oversized.decision, RiskGateDecision.BLOCKED, "oversized proposal blocked")
    assert_true("trade_value_too_large" in violation_codes(oversized), "oversized violation present")

    risky = engine.evaluate_proposal(make_proposal(risk_summary=SimpleNamespace(risk_score=90)))
    assert_equal(risky.decision, RiskGateDecision.BLOCKED, "high-risk proposal blocked")
    assert_true("risk_score_too_high" in violation_codes(risky), "risk violation present")

    low_confidence = engine.evaluate_proposal(
        make_proposal(strategy_scorecard=SimpleNamespace(action=DecisionStatus.PAPER_TRADE, risk_score=35, confidence_score=30))
    )
    assert_equal(low_confidence.decision, RiskGateDecision.BLOCKED, "low-confidence proposal blocked")
    assert_true("confidence_score_too_low" in violation_codes(low_confidence), "confidence violation present")

    bad_symbol = engine.evaluate_proposal(make_proposal(asset="DOGE/USD"))
    assert_equal(bad_symbol.decision, RiskGateDecision.BLOCKED, "disallowed symbol blocked")
    assert_true("symbol_not_allowed" in violation_codes(bad_symbol), "symbol violation present")

    blocked_scorecard = engine.evaluate_proposal(
        make_proposal(strategy_scorecard=SimpleNamespace(action=DecisionStatus.BLOCKED, risk_score=35, confidence_score=82))
    )
    assert_equal(blocked_scorecard.decision, RiskGateDecision.BLOCKED, "blocked scorecard blocked")
    assert_true("decision_status_not_allowed" in violation_codes(blocked_scorecard), "decision status violation present")

    kill_switch = RiskGateEngine(RiskGateConfig(kill_switch_enabled=True)).evaluate_proposal(make_proposal())
    assert_equal(kill_switch.decision, RiskGateDecision.BLOCKED, "kill switch blocks proposal")
    assert_true("kill_switch_enabled" in violation_codes(kill_switch), "kill switch violation present")

    result_text = str(passed.to_dict()).lower()
    assert_true("api_key" not in result_text, "risk result does not mention API keys")
    assert_true("withdraw" not in result_text, "risk result does not mention withdrawals")
    assert_true("place_order" not in result_text, "risk result does not mention order placement")

    try:
        RiskGateConfig(max_trade_value=0)
        raise AssertionError("Invalid max_trade_value should fail.")
    except ValueError:
        print("[OK] Invalid risk gate config rejected")

    print("Risk gate engine validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# Update docs / decision log.
$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 13D Risk Gate Engine

Decision:

Added a safe risk gate engine that evaluates manually approved trade proposals before any future dry-run/order-preview workflow.

The risk gate checks:

- Kill switch state.
- Manual approval requirement.
- Allowed symbols.
- Maximum trade value.
- Maximum risk score.
- Minimum confidence score.
- Allowed decision statuses.

This slice does not place orders, cancel orders, call trading endpoints, access funding, or withdraw assets.
'@

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
Add-Content -Path $RoadmapPath -Encoding UTF8 -Value @'

## Slice 13D — Risk Gate Engine

Status: Complete.

Goal:

Create a hard safety gate that evaluates manually approved trade proposals before they can move to future dry-run/order-preview workflow.

Safety:

- No live trading.
- No order placement.
- No order cancellation.
- No funding actions.
- No withdrawals.

Commit message:

```text
Add risk gate engine
```
'@

# Ensure local risk output is ignored for future use.
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
$GitIgnoreText = Get-Content $GitIgnorePath -Raw
if ($GitIgnoreText -notmatch "(?m)^\.risk-gate-output/") {
    Add-Content -Path $GitIgnorePath -Encoding UTF8 -Value "`n# Local risk gate outputs`n.risk-gate-output/"
}

Write-Host "=== SLICE 13D FILES CREATED ==="
Write-Host ""
Write-Host "=== RUNNING SLICE 13D VALIDATION ==="
python .\scripts\test_risk_gate_engine.py

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "Slice 13D script completed."
Write-Host ""
Get-ChildItem $RiskPath | Select-Object Name, Length, LastWriteTime
