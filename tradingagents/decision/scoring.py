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


def _opinion_risk_score(opinion: AgentOpinion) -> int:
    raw_value = opinion.metadata.get("risk_score", 50)
    try:
        return int(raw_value)
    except (TypeError, ValueError) as exc:
        raise StrategyScoringError(f"opinion.metadata.risk_score must be an integer. Got: {raw_value!r}") from exc


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
            forced_reason='; '.join(recommendation.reasons),
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
        risk_score = self._validate_score(_opinion_risk_score(opinion), "_opinion_risk_score(opinion)")

        directional_multiplier = 0.0

        if opinion.direction in {SignalDirection.LONG, SignalDirection.SHORT}:
            directional_multiplier = 1.0
        elif opinion.direction == SignalDirection.NEUTRAL:
            directional_multiplier = 0.35

        risk_penalty = risk_score / 100
        weighted_score = confidence * directional_multiplier * (1 - risk_penalty)

        return AgentScoreBreakdown(
            agent_name=str(opinion.agent_role),
            direction=opinion.direction,
            confidence=confidence,
            risk_score=risk_score,
            weighted_score=weighted_score,
            notes=tuple(opinion.concerns),
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
        return round(mean(_opinion_risk_score(opinion) for opinion in opinions))

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




