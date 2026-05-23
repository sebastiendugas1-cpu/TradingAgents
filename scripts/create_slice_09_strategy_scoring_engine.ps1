# ============================ Slice 9 - Strategy Scoring Engine ============================
# Purpose:
# Creates a safe strategy scoring layer that converts structured agent opinions
# into a normalized scorecard and final recommendation.
#
# This slice does NOT place trades.
# This slice does NOT use Kraken private API.
# This slice does NOT execute orders.

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$DecisionPath = Join-Path $ProjectRoot "tradingagents\decision"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

Set-Location $ProjectRoot

New-Item -ItemType Directory -Force -Path $DecisionPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-TextFile (Join-Path $DecisionPath "scoring.py") @'
# ============================ Strategy Scoring Engine ============================
"""
Safe strategy scoring engine.

Purpose:
- Convert structured agent opinions into a normalized scorecard.
- Produce a final recommendation that is limited to safe statuses.
- Never produce a live-trade command.
- Never call exchange APIs.

This module depends on Slice 8 decision models.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from statistics import mean

from tradingagents.decision.models import (
    AgentOpinion,
    DecisionStatus,
    SignalDirection,
    TradeRecommendation,
)


@dataclass(frozen=True)
class AgentScoreBreakdown:
    """Scored contribution from one agent opinion."""

    agent_name: str
    direction: SignalDirection
    confidence: int
    risk_score: int
    weighted_score: float
    notes: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class StrategyScorecard:
    """Final strategy scorecard generated from agent opinions."""

    asset: str
    direction: SignalDirection
    confidence_score: int
    risk_score: int
    action: DecisionStatus
    reason_summary: str
    agent_breakdown: tuple[AgentScoreBreakdown, ...]
    is_actionable_for_simulation: bool

    def to_dict(self) -> dict[str, object]:
        """Return a JSON-serializable representation."""

        return {
            "asset": self.asset,
            "direction": self.direction.value,
            "confidence_score": self.confidence_score,
            "risk_score": self.risk_score,
            "action": self.action.value,
            "reason_summary": self.reason_summary,
            "agent_breakdown": [
                {
                    "agent_name": item.agent_name,
                    "direction": item.direction.value,
                    "confidence": item.confidence,
                    "risk_score": item.risk_score,
                    "weighted_score": round(item.weighted_score, 2),
                    "notes": list(item.notes),
                }
                for item in self.agent_breakdown
            ],
            "is_actionable_for_simulation": self.is_actionable_for_simulation,
        }


class StrategyScoringError(ValueError):
    """Raised when the scoring engine receives invalid input."""


class StrategyScoringEngine:
    """Safe score engine for agent opinions."""

    def __init__(
        self,
        *,
        paper_trade_confidence_threshold: int = 75,
        manual_review_confidence_threshold: int = 55,
        max_paper_trade_risk_score: int = 55,
        max_manual_review_risk_score: int = 75,
    ) -> None:
        self.paper_trade_confidence_threshold = self._validate_score(
            paper_trade_confidence_threshold,
            "paper_trade_confidence_threshold",
        )
        self.manual_review_confidence_threshold = self._validate_score(
            manual_review_confidence_threshold,
            "manual_review_confidence_threshold",
        )
        self.max_paper_trade_risk_score = self._validate_score(
            max_paper_trade_risk_score,
            "max_paper_trade_risk_score",
        )
        self.max_manual_review_risk_score = self._validate_score(
            max_manual_review_risk_score,
            "max_manual_review_risk_score",
        )

        if self.manual_review_confidence_threshold > self.paper_trade_confidence_threshold:
            raise StrategyScoringError(
                "manual_review_confidence_threshold cannot be greater than "
                "paper_trade_confidence_threshold."
            )

        if self.max_paper_trade_risk_score > self.max_manual_review_risk_score:
            raise StrategyScoringError(
                "max_paper_trade_risk_score cannot be greater than "
                "max_manual_review_risk_score."
            )

    def score_recommendation(self, recommendation: TradeRecommendation) -> StrategyScorecard:
        """Score a Slice 8 TradeRecommendation into a StrategyScorecard."""

        if not isinstance(recommendation, TradeRecommendation):
            raise StrategyScoringError("recommendation must be a TradeRecommendation.")

        return self.score_opinions(
            asset=recommendation.asset,
            opinions=tuple(recommendation.agent_opinions),
            forced_status=recommendation.status,
            forced_reason=recommendation.reason,
        )

    def score_opinions(
        self,
        *,
        asset: str,
        opinions: tuple[AgentOpinion, ...] | list[AgentOpinion],
        forced_status: DecisionStatus | None = None,
        forced_reason: str | None = None,
    ) -> StrategyScorecard:
        """Score raw agent opinions directly."""

        if not asset or not str(asset).strip():
            raise StrategyScoringError("asset is required.")

        opinions_tuple = tuple(opinions)

        if not opinions_tuple:
            return StrategyScorecard(
                asset=str(asset).strip(),
                direction=SignalDirection.NEUTRAL,
                confidence_score=0,
                risk_score=0,
                action=DecisionStatus.WATCH,
                reason_summary="No agent opinions were supplied.",
                agent_breakdown=(),
                is_actionable_for_simulation=False,
            )

        for opinion in opinions_tuple:
            if not isinstance(opinion, AgentOpinion):
                raise StrategyScoringError("All opinions must be AgentOpinion instances.")

        breakdown = tuple(self._score_opinion(opinion) for opinion in opinions_tuple)
        direction = self._majority_direction(opinions_tuple)

        confidence_score = self._aggregate_confidence(opinions_tuple, direction)
        risk_score = self._aggregate_risk(opinions_tuple)

        if forced_status == DecisionStatus.BLOCKED:
            action = DecisionStatus.BLOCKED
            reason = forced_reason or "Recommendation was explicitly blocked upstream."
        else:
            action = self._decide_action(
                direction=direction,
                confidence_score=confidence_score,
                risk_score=risk_score,
            )
            reason = self._build_reason_summary(
                direction=direction,
                confidence_score=confidence_score,
                risk_score=risk_score,
                action=action,
            )

        return StrategyScorecard(
            asset=str(asset).strip(),
            direction=direction,
            confidence_score=confidence_score,
            risk_score=risk_score,
            action=action,
            reason_summary=reason,
            agent_breakdown=breakdown,
            is_actionable_for_simulation=action in {
                DecisionStatus.PAPER_TRADE,
                DecisionStatus.MANUAL_REVIEW,
            },
        )

    def _score_opinion(self, opinion: AgentOpinion) -> AgentScoreBreakdown:
        confidence = self._validate_score(opinion.confidence, "opinion.confidence")
        risk_score = self._validate_score(opinion.risk_score, "opinion.risk_score")

        directional_multiplier = 0.0

        if opinion.direction in {SignalDirection.LONG, SignalDirection.SHORT}:
            directional_multiplier = 1.0
        elif opinion.direction == SignalDirection.NEUTRAL:
            directional_multiplier = 0.35

        risk_penalty = risk_score / 100
        weighted_score = confidence * directional_multiplier * (1 - risk_penalty)

        return AgentScoreBreakdown(
            agent_name=opinion.agent_name,
            direction=opinion.direction,
            confidence=confidence,
            risk_score=risk_score,
            weighted_score=weighted_score,
            notes=tuple(opinion.notes),
        )

    def _aggregate_confidence(
        self,
        opinions: tuple[AgentOpinion, ...],
        direction: SignalDirection,
    ) -> int:
        aligned = [
            opinion.confidence
            for opinion in opinions
            if opinion.direction == direction
        ]

        if not aligned:
            aligned = [opinion.confidence for opinion in opinions]

        return round(mean(aligned))

    def _aggregate_risk(self, opinions: tuple[AgentOpinion, ...]) -> int:
        return round(mean(opinion.risk_score for opinion in opinions))

    def _majority_direction(self, opinions: tuple[AgentOpinion, ...]) -> SignalDirection:
        counts = {
            SignalDirection.LONG: 0,
            SignalDirection.SHORT: 0,
            SignalDirection.NEUTRAL: 0,
        }

        confidence_by_direction = {
            SignalDirection.LONG: 0,
            SignalDirection.SHORT: 0,
            SignalDirection.NEUTRAL: 0,
        }

        for opinion in opinions:
            counts[opinion.direction] += 1
            confidence_by_direction[opinion.direction] += opinion.confidence

        ranked = sorted(
            counts,
            key=lambda direction: (
                counts[direction],
                confidence_by_direction[direction],
            ),
            reverse=True,
        )

        return ranked[0]

    def _decide_action(
        self,
        *,
        direction: SignalDirection,
        confidence_score: int,
        risk_score: int,
    ) -> DecisionStatus:
        if direction == SignalDirection.NEUTRAL:
            return DecisionStatus.WATCH

        if risk_score > self.max_manual_review_risk_score:
            return DecisionStatus.BLOCKED

        if (
            confidence_score >= self.paper_trade_confidence_threshold
            and risk_score <= self.max_paper_trade_risk_score
        ):
            return DecisionStatus.PAPER_TRADE

        if (
            confidence_score >= self.manual_review_confidence_threshold
            and risk_score <= self.max_manual_review_risk_score
        ):
            return DecisionStatus.MANUAL_REVIEW

        return DecisionStatus.WATCH

    def _build_reason_summary(
        self,
        *,
        direction: SignalDirection,
        confidence_score: int,
        risk_score: int,
        action: DecisionStatus,
    ) -> str:
        if action == DecisionStatus.BLOCKED:
            return (
                f"Blocked because risk score {risk_score} exceeds the allowed "
                f"manual-review threshold {self.max_manual_review_risk_score}."
            )

        if action == DecisionStatus.PAPER_TRADE:
            return (
                f"Paper-trade candidate: {direction.value} setup with confidence "
                f"{confidence_score} and risk score {risk_score}."
            )

        if action == DecisionStatus.MANUAL_REVIEW:
            return (
                f"Manual review required: {direction.value} setup with confidence "
                f"{confidence_score} and risk score {risk_score}."
            )

        return (
            f"Watch only: direction={direction.value}, confidence={confidence_score}, "
            f"risk={risk_score}."
        )

    @staticmethod
    def _validate_score(value: int, field_name: str) -> int:
        if not isinstance(value, int):
            raise StrategyScoringError(f"{field_name} must be an integer.")

        if value < 0 or value > 100:
            raise StrategyScoringError(f"{field_name} must be between 0 and 100.")

        return value
'@

$InitPath = Join-Path $DecisionPath "__init__.py"
$ExistingInit = ""
if (Test-Path $InitPath) {
    $ExistingInit = Get-Content $InitPath -Raw
}

$UpdatedInit = @'
# ============================ Decision Package Exports ============================

from tradingagents.decision.engine import AgentDecisionEngine
from tradingagents.decision.models import (
    AgentOpinion,
    DecisionStatus,
    RiskAssessment,
    SignalDirection,
    TradeRecommendation,
)
from tradingagents.decision.scoring import (
    AgentScoreBreakdown,
    StrategyScorecard,
    StrategyScoringEngine,
    StrategyScoringError,
)

__all__ = [
    "AgentDecisionEngine",
    "AgentOpinion",
    "DecisionStatus",
    "RiskAssessment",
    "SignalDirection",
    "TradeRecommendation",
    "AgentScoreBreakdown",
    "StrategyScorecard",
    "StrategyScoringEngine",
    "StrategyScoringError",
]
'@

Write-TextFile $InitPath $UpdatedInit

Write-TextFile (Join-Path $ScriptsPath "test_strategy_scoring_engine.py") @'
# ============================ Slice 9 Validation - Strategy Scoring Engine ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import (  # noqa: E402
    AgentDecisionEngine,
    AgentOpinion,
    DecisionStatus,
    SignalDirection,
    StrategyScoringEngine,
    StrategyScoringError,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 9 strategy scoring engine validation...")

    opinions = [
        AgentOpinion(
            agent_name="market_structure",
            direction=SignalDirection.LONG,
            confidence=86,
            risk_score=35,
            summary="Trend and structure are constructive.",
            notes=("higher highs", "support held"),
        ),
        AgentOpinion(
            agent_name="technical_analysis",
            direction=SignalDirection.LONG,
            confidence=80,
            risk_score=40,
            summary="Momentum confirms the setup.",
            notes=("moving average support",),
        ),
        AgentOpinion(
            agent_name="news_sentiment",
            direction=SignalDirection.NEUTRAL,
            confidence=55,
            risk_score=50,
            summary="No major negative catalyst.",
            notes=("neutral headlines",),
        ),
    ]

    decision_engine = AgentDecisionEngine()
    recommendation = decision_engine.build_recommendation(asset="BTC/USD", opinions=opinions)

    scoring_engine = StrategyScoringEngine()
    scorecard = scoring_engine.score_recommendation(recommendation)

    assert_equal(scorecard.asset, "BTC/USD", "scorecard asset")
    assert_equal(scorecard.direction, SignalDirection.LONG, "majority direction")
    assert_equal(scorecard.action, DecisionStatus.PAPER_TRADE, "high-confidence low-risk action")
    assert_true(scorecard.is_actionable_for_simulation, "paper trade actionable for simulation")
    assert_true(scorecard.confidence_score >= 80, "confidence score is high")
    assert_true(scorecard.risk_score <= 55, "risk score under paper threshold")
    assert_equal(len(scorecard.agent_breakdown), 3, "agent breakdown count")

    manual_review = scoring_engine.score_opinions(
        asset="ETH/USD",
        opinions=[
            AgentOpinion(
                agent_name="technical_analysis",
                direction=SignalDirection.LONG,
                confidence=62,
                risk_score=65,
                summary="Potential setup but risk is elevated.",
            )
        ],
    )

    assert_equal(manual_review.action, DecisionStatus.MANUAL_REVIEW, "moderate setup requires manual review")

    blocked = scoring_engine.score_opinions(
        asset="SOL/USD",
        opinions=[
            AgentOpinion(
                agent_name="risk_manager",
                direction=SignalDirection.LONG,
                confidence=90,
                risk_score=90,
                summary="High confidence but unacceptable risk.",
            )
        ],
    )

    assert_equal(blocked.action, DecisionStatus.BLOCKED, "high risk blocks recommendation")
    assert_true(not blocked.is_actionable_for_simulation, "blocked scorecard is not actionable")

    neutral = scoring_engine.score_opinions(asset="AAPL", opinions=[])

    assert_equal(neutral.action, DecisionStatus.WATCH, "no opinions returns watch")
    assert_equal(neutral.direction, SignalDirection.NEUTRAL, "no opinions returns neutral")

    try:
        StrategyScoringEngine(paper_trade_confidence_threshold=101)
        raise AssertionError("Invalid scoring threshold should have failed.")
    except StrategyScoringError:
        print("[OK] Invalid scoring threshold rejected")

    score_dict = scorecard.to_dict()
    assert_equal(score_dict["action"], "paper_trade", "scorecard dictionary action")
    assert_true("live_trade" not in str(score_dict).lower(), "scorecard does not mention live trading")

    print("Strategy scoring engine validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $Roadmap = Get-Content $RoadmapPath -Raw
    $Roadmap = $Roadmap.Replace("## Slice 9 — Strategy Scoring Engine`r`n`r`nGoal:`r`n`r`nConvert agent opinions into measurable trading decisions.", "## Slice 9 — Strategy Scoring Engine`r`n`r`nStatus: Complete.`r`n`r`nGoal:`r`n`r`nConvert agent opinions into measurable trading decisions.")
    $Roadmap = $Roadmap.Replace("## Slice 9 — Strategy Scoring Engine`n`nGoal:`n`nConvert agent opinions into measurable trading decisions.", "## Slice 9 — Strategy Scoring Engine`n`nStatus: Complete.`n`nGoal:`n`nConvert agent opinions into measurable trading decisions.")
    Set-Content -Path $RoadmapPath -Value $Roadmap -Encoding UTF8
}

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 9 Completed: Strategy Scoring Engine

Decision:

Added a safe strategy scoring engine that converts structured agent opinions into a normalized scorecard.

Key points:

- Supports confidence scoring.
- Supports risk scoring.
- Supports agent score breakdown.
- Limits output actions to watch, paper trade, manual review, or blocked.
- Does not support live-trade execution.
- Does not call Kraken private APIs.
- Does not place orders.
'@

Write-Host "=== SLICE 9 FILES CREATED ==="

Write-Host "`n=== RUNNING SLICE 9 VALIDATION ==="
python .\scripts\test_strategy_scoring_engine.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 9 script completed."

Get-ChildItem $DecisionPath | Select-Object Name, Length, LastWriteTime
