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
