# ============================ Slice 8 - Agent Decision Architecture ============================
# Purpose:
# Creates a safe structured agent decision layer.
# No live trading. No Kraken private API. No order execution.

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$DecisionPath = Join-Path $ProjectRoot "tradingagents\decision"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path $DecisionPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $folder = Split-Path $Path -Parent
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
    }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-ProjectFile (Join-Path $DecisionPath "models.py") @'
# ============================ Agent Decision Models ============================
"""
Structured decision models for the TradingAgents crypto / multi-asset project.

This module is intentionally safe:
- It does not place orders.
- It does not call Kraken private APIs.
- It does not perform live trading.
- It only represents structured analysis and recommendations.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


class AgentRole(str, Enum):
    """Supported analysis agent roles."""

    MARKET_STRUCTURE = "market_structure"
    TECHNICAL_ANALYSIS = "technical_analysis"
    NEWS_SENTIMENT = "news_sentiment"
    RISK_MANAGER = "risk_manager"
    STRATEGY_CRITIC = "strategy_critic"
    FINAL_DECISION = "final_decision"


class SignalDirection(str, Enum):
    """Directional view produced by an agent."""

    LONG = "long"
    SHORT = "short"
    NEUTRAL = "neutral"


class DecisionStatus(str, Enum):
    """Safe decision statuses.

    There is intentionally no LIVE_TRADE status in this layer.
    """

    WATCH = "watch"
    PAPER_TRADE = "paper_trade"
    MANUAL_REVIEW = "manual_review"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class AgentOpinion:
    """Structured opinion from a specialized analysis agent."""

    agent_role: AgentRole
    asset: str
    direction: SignalDirection
    confidence: int
    rationale: str
    concerns: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        _validate_score("confidence", self.confidence)
        if not self.asset.strip():
            raise ValueError("AgentOpinion.asset cannot be blank.")
        if not self.rationale.strip():
            raise ValueError("AgentOpinion.rationale cannot be blank.")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class RiskAssessment:
    """Structured risk assessment for a candidate decision."""

    asset: str
    risk_score: int
    max_position_size_pct: float
    blocked: bool
    reasons: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        _validate_score("risk_score", self.risk_score)
        if self.max_position_size_pct < 0 or self.max_position_size_pct > 100:
            raise ValueError("max_position_size_pct must be between 0 and 100.")
        if not self.asset.strip():
            raise ValueError("RiskAssessment.asset cannot be blank.")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class TradeRecommendation:
    """Final safe recommendation produced by the decision layer.

    This is not an order object. It is a recommendation only.
    """

    asset: str
    status: DecisionStatus
    direction: SignalDirection
    confidence: int
    risk_score: int
    summary: str
    reasons: list[str] = field(default_factory=list)
    agent_opinions: list[AgentOpinion] = field(default_factory=list)
    risk_assessment: RiskAssessment | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        _validate_score("confidence", self.confidence)
        _validate_score("risk_score", self.risk_score)
        if not self.asset.strip():
            raise ValueError("TradeRecommendation.asset cannot be blank.")
        if not self.summary.strip():
            raise ValueError("TradeRecommendation.summary cannot be blank.")

    @property
    def is_actionable(self) -> bool:
        """True for simulated or manual-review workflows, never direct live execution."""

        return self.status in {DecisionStatus.PAPER_TRADE, DecisionStatus.MANUAL_REVIEW}

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        return data


def _validate_score(name: str, value: int) -> None:
    if not isinstance(value, int):
        raise TypeError(f"{name} must be an integer.")
    if value < 0 or value > 100:
        raise ValueError(f"{name} must be between 0 and 100.")
'@

Write-ProjectFile (Join-Path $DecisionPath "engine.py") @'
# ============================ Agent Decision Engine ============================
"""
Safe aggregation logic for agent opinions.

This layer converts structured agent opinions into one safe recommendation status:
- WATCH
- PAPER_TRADE
- MANUAL_REVIEW
- BLOCKED

It does not place orders.
"""

from __future__ import annotations

from collections import Counter

from tradingagents.decision.models import (
    AgentOpinion,
    DecisionStatus,
    RiskAssessment,
    SignalDirection,
    TradeRecommendation,
)


def aggregate_agent_opinions(
    asset: str,
    opinions: list[AgentOpinion],
    risk_assessment: RiskAssessment | None = None,
    *,
    paper_trade_confidence_threshold: int = 75,
    manual_review_confidence_threshold: int = 55,
    block_risk_threshold: int = 85,
) -> TradeRecommendation:
    """Aggregate agent opinions into a safe trade recommendation.

    Rules:
    - If no opinions exist, return WATCH.
    - If risk assessment is blocked, return BLOCKED.
    - If risk score is too high, return BLOCKED.
    - If agents disagree strongly, return MANUAL_REVIEW or WATCH.
    - If confidence is high and risk is acceptable, return PAPER_TRADE.
    - This function never returns a live trading instruction.
    """

    normalized_asset = asset.strip().upper()
    if not normalized_asset:
        raise ValueError("asset cannot be blank.")

    if not opinions:
        return TradeRecommendation(
            asset=normalized_asset,
            status=DecisionStatus.WATCH,
            direction=SignalDirection.NEUTRAL,
            confidence=0,
            risk_score=0,
            summary="No agent opinions available.",
            reasons=["No analysis inputs were provided."],
            agent_opinions=[],
            risk_assessment=risk_assessment,
        )

    for opinion in opinions:
        if opinion.asset.upper() != normalized_asset:
            raise ValueError(
                f"Opinion asset mismatch. Expected {normalized_asset}, got {opinion.asset}."
            )

    risk_score = risk_assessment.risk_score if risk_assessment else _derive_risk_score(opinions)

    if risk_assessment and risk_assessment.blocked:
        return TradeRecommendation(
            asset=normalized_asset,
            status=DecisionStatus.BLOCKED,
            direction=SignalDirection.NEUTRAL,
            confidence=_average_confidence(opinions),
            risk_score=risk_score,
            summary="Recommendation blocked by risk assessment.",
            reasons=risk_assessment.reasons or ["Risk assessment blocked this setup."],
            agent_opinions=opinions,
            risk_assessment=risk_assessment,
        )

    if risk_score >= block_risk_threshold:
        return TradeRecommendation(
            asset=normalized_asset,
            status=DecisionStatus.BLOCKED,
            direction=SignalDirection.NEUTRAL,
            confidence=_average_confidence(opinions),
            risk_score=risk_score,
            summary="Recommendation blocked because risk score is too high.",
            reasons=[f"Risk score {risk_score} is at or above block threshold {block_risk_threshold}."],
            agent_opinions=opinions,
            risk_assessment=risk_assessment,
        )

    majority_direction, majority_count = _majority_direction(opinions)
    average_confidence = _average_confidence(opinions)

    if majority_direction == SignalDirection.NEUTRAL:
        status = DecisionStatus.WATCH
        summary = "Agents are neutral. Watch only."
        reasons = ["Majority direction is neutral."]
    elif majority_count < max(2, len(opinions) // 2 + 1):
        status = DecisionStatus.MANUAL_REVIEW
        summary = "Agents do not show a strong directional consensus. Manual review required."
        reasons = ["No strong directional majority."]
    elif average_confidence >= paper_trade_confidence_threshold:
        status = DecisionStatus.PAPER_TRADE
        summary = "High-confidence setup approved for paper trading only."
        reasons = ["Confidence threshold met for paper trading."]
    elif average_confidence >= manual_review_confidence_threshold:
        status = DecisionStatus.MANUAL_REVIEW
        summary = "Moderate-confidence setup requires manual review."
        reasons = ["Confidence threshold met for manual review only."]
    else:
        status = DecisionStatus.WATCH
        summary = "Confidence is too low. Watch only."
        reasons = ["Confidence below manual review threshold."]

    return TradeRecommendation(
        asset=normalized_asset,
        status=status,
        direction=majority_direction,
        confidence=average_confidence,
        risk_score=risk_score,
        summary=summary,
        reasons=reasons,
        agent_opinions=opinions,
        risk_assessment=risk_assessment,
    )


def _average_confidence(opinions: list[AgentOpinion]) -> int:
    if not opinions:
        return 0
    return round(sum(opinion.confidence for opinion in opinions) / len(opinions))


def _derive_risk_score(opinions: list[AgentOpinion]) -> int:
    concern_count = sum(len(opinion.concerns) for opinion in opinions)
    base_risk = min(80, concern_count * 10)
    return max(0, base_risk)


def _majority_direction(opinions: list[AgentOpinion]) -> tuple[SignalDirection, int]:
    counts = Counter(opinion.direction for opinion in opinions)
    direction, count = counts.most_common(1)[0]
    return direction, count
'@

Write-ProjectFile (Join-Path $DecisionPath "__init__.py") @'
# ============================ Decision Package Exports ============================

from tradingagents.decision.engine import aggregate_agent_opinions
from tradingagents.decision.models import (
    AgentOpinion,
    AgentRole,
    DecisionStatus,
    RiskAssessment,
    SignalDirection,
    TradeRecommendation,
)

__all__ = [
    "AgentOpinion",
    "AgentRole",
    "DecisionStatus",
    "RiskAssessment",
    "SignalDirection",
    "TradeRecommendation",
    "aggregate_agent_opinions",
]
'@

Write-ProjectFile (Join-Path $ScriptsPath "test_agent_decision_architecture.py") @'
# ============================ Slice 8 Test - Agent Decision Architecture ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import (  # noqa: E402
    AgentOpinion,
    AgentRole,
    DecisionStatus,
    RiskAssessment,
    SignalDirection,
    aggregate_agent_opinions,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def main() -> int:
    print("Running Slice 8 agent decision architecture validation...")

    opinions = [
        AgentOpinion(
            agent_role=AgentRole.MARKET_STRUCTURE,
            asset="BTC/USD",
            direction=SignalDirection.LONG,
            confidence=82,
            rationale="Trend structure is bullish.",
        ),
        AgentOpinion(
            agent_role=AgentRole.TECHNICAL_ANALYSIS,
            asset="BTC/USD",
            direction=SignalDirection.LONG,
            confidence=78,
            rationale="Momentum confirms the setup.",
        ),
        AgentOpinion(
            agent_role=AgentRole.NEWS_SENTIMENT,
            asset="BTC/USD",
            direction=SignalDirection.NEUTRAL,
            confidence=72,
            rationale="No major negative headlines detected.",
        ),
    ]

    risk = RiskAssessment(
        asset="BTC/USD",
        risk_score=35,
        max_position_size_pct=2.0,
        blocked=False,
        reasons=[],
    )

    recommendation = aggregate_agent_opinions("BTC/USD", opinions, risk)
    assert_equal(recommendation.status, DecisionStatus.PAPER_TRADE, "high-confidence recommendation is paper trade only")
    assert_equal(recommendation.direction, SignalDirection.LONG, "majority direction")
    assert_equal(recommendation.is_actionable, True, "paper trade is actionable for simulation/manual workflow")

    blocked_risk = RiskAssessment(
        asset="BTC/USD",
        risk_score=90,
        max_position_size_pct=0.0,
        blocked=True,
        reasons=["Daily loss limit reached."],
    )
    blocked = aggregate_agent_opinions("BTC/USD", opinions, blocked_risk)
    assert_equal(blocked.status, DecisionStatus.BLOCKED, "blocked risk assessment blocks recommendation")
    assert_equal(blocked.is_actionable, False, "blocked recommendation is not actionable")

    neutral = aggregate_agent_opinions("BTC/USD", [])
    assert_equal(neutral.status, DecisionStatus.WATCH, "no opinions returns watch")
    assert_equal(neutral.direction, SignalDirection.NEUTRAL, "no opinions returns neutral direction")

    try:
        AgentOpinion(
            agent_role=AgentRole.RISK_MANAGER,
            asset="BTC/USD",
            direction=SignalDirection.NEUTRAL,
            confidence=120,
            rationale="Invalid confidence should fail.",
        )
    except ValueError:
        print("[OK] Invalid confidence rejected")
    else:
        raise AssertionError("Invalid confidence was not rejected")

    allowed_statuses = {status.value for status in DecisionStatus}
    assert_equal("live_trade" in allowed_statuses, False, "live_trade status does not exist")

    print("Agent decision architecture validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    Add-Content -Path $DecisionLogPath -Value @'

## 2026-05-22 — Slice 8 Agent Decision Architecture

Decision:

Added a safe structured decision layer where agents produce analysis and recommendations only.

Key points:

- Agent outputs are structured as opinions, risk assessments, and recommendations.
- Allowed recommendation statuses are WATCH, PAPER_TRADE, MANUAL_REVIEW, and BLOCKED.
- There is intentionally no LIVE_TRADE status in this layer.
- This layer does not place orders or call Kraken private APIs.
'@ -Encoding UTF8
}

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $roadmap = Get-Content $RoadmapPath -Raw
    $roadmap = $roadmap.Replace("## Slice 8 — Modular Agent Decision Architecture`r`n`r`nGoal:`r`n`r`nDefine structured outputs from specialized agents.", "## Slice 8 — Modular Agent Decision Architecture`r`n`r`nStatus: Complete.`r`n`r`nGoal:`r`n`r`nDefine structured outputs from specialized agents.")
    $roadmap = $roadmap.Replace("## Slice 8 — Modular Agent Decision Architecture`n`nGoal:`n`nDefine structured outputs from specialized agents.", "## Slice 8 — Modular Agent Decision Architecture`n`nStatus: Complete.`n`nGoal:`n`nDefine structured outputs from specialized agents.")
    Set-Content -Path $RoadmapPath -Value $roadmap -Encoding UTF8
}

Write-Host "=== SLICE 8 FILES CREATED ==="
Get-ChildItem $DecisionPath | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 8 VALIDATION ==="
python .\scripts\test_agent_decision_architecture.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 8 script completed."
