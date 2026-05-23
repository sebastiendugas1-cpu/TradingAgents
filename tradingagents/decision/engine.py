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
