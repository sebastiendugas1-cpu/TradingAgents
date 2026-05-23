# ============================ Slice 9 Validation - Strategy Scoring Engine ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import (  # noqa: E402
    AgentOpinion,
    DecisionStatus,
    SignalDirection,
    StrategyScoringEngine,
    StrategyScoringError,
    aggregate_agent_opinions,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def make_opinion(
    *,
    agent_role: str,
    asset: str,
    direction: SignalDirection,
    confidence: int,
    risk_score: int,
    rationale: str,
    concerns: list[str] | None = None,
) -> AgentOpinion:
    return AgentOpinion(
        agent_role=agent_role,
        asset=asset,
        direction=direction,
        confidence=confidence,
        rationale=rationale,
        concerns=concerns or [],
        metadata={"risk_score": risk_score},
    )


def main() -> int:
    print("Running Slice 9 strategy scoring engine validation...")

    opinions = [
        make_opinion(
            agent_role="market_structure",
            asset="BTC/USD",
            direction=SignalDirection.LONG,
            confidence=86,
            risk_score=35,
            rationale="Trend and structure are constructive.",
        ),
        make_opinion(
            agent_role="technical_analysis",
            asset="BTC/USD",
            direction=SignalDirection.LONG,
            confidence=80,
            risk_score=40,
            rationale="Momentum confirms the setup.",
        ),
        make_opinion(
            agent_role="news_sentiment",
            asset="BTC/USD",
            direction=SignalDirection.NEUTRAL,
            confidence=55,
            risk_score=50,
            rationale="No major negative catalyst.",
        ),
    ]

    recommendation = aggregate_agent_opinions(asset="BTC/USD", opinions=opinions)

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
            make_opinion(
                agent_role="technical_analysis",
                asset="ETH/USD",
                direction=SignalDirection.LONG,
                confidence=62,
                risk_score=65,
                rationale="Potential setup but risk is elevated.",
            )
        ],
    )

    assert_equal(manual_review.action, DecisionStatus.MANUAL_REVIEW, "moderate setup requires manual review")

    blocked = scoring_engine.score_opinions(
        asset="SOL/USD",
        opinions=[
            make_opinion(
                agent_role="risk_manager",
                asset="SOL/USD",
                direction=SignalDirection.LONG,
                confidence=90,
                risk_score=90,
                rationale="High confidence but unacceptable risk.",
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