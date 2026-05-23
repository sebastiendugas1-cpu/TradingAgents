# ============================ Slice 11 Validation - Paper Trading Engine ============================

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
    aggregate_agent_opinions,
)
from tradingagents.papertrading import (  # noqa: E402
    PaperOrderRequest,
    PaperOrderSide,
    PaperOrderStatus,
    PaperTradingEngine,
    PaperTradingError,
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
) -> AgentOpinion:
    return AgentOpinion(
        agent_role=agent_role,
        asset=asset,
        direction=direction,
        confidence=confidence,
        rationale=rationale,
        metadata={"risk_score": risk_score},
    )


def main() -> int:
    print("Running Slice 11 paper trading engine validation...")

    engine = PaperTradingEngine(starting_cash=10_000.0, fee_rate=0.001, max_order_notional=5_000.0)

    buy = engine.place_order(
        PaperOrderRequest(
            asset="BTC/USD",
            side=PaperOrderSide.BUY,
            quantity=0.01,
            price=50_000.0,
            reason="Synthetic paper buy.",
            source="unit_test",
        )
    )

    assert_equal(buy.status, PaperOrderStatus.FILLED, "paper buy filled")
    assert_equal(round(engine.positions["BTC/USD"].quantity, 8), 0.01, "paper BTC position created")
    assert_true(engine.cash_balance < 10_000.0, "cash reduced after buy")

    sell = engine.place_order(
        PaperOrderRequest(
            asset="BTC/USD",
            side=PaperOrderSide.SELL,
            quantity=0.005,
            price=55_000.0,
            reason="Synthetic paper sell.",
            source="unit_test",
        )
    )

    assert_equal(sell.status, PaperOrderStatus.FILLED, "paper sell filled")
    assert_equal(round(engine.positions["BTC/USD"].quantity, 8), 0.005, "paper BTC position reduced")
    assert_true(engine.realized_pnl > 0, "realized P/L positive after profitable sell")

    rejected = engine.place_order(
        PaperOrderRequest(
            asset="ETH/USD",
            side=PaperOrderSide.SELL,
            quantity=1.0,
            price=2_000.0,
            reason="Reject sell without position.",
            source="unit_test",
        )
    )

    assert_equal(rejected.status, PaperOrderStatus.REJECTED, "sell without position rejected")

    blocked = engine.place_order(
        PaperOrderRequest(
            asset="BTC/USD",
            side=PaperOrderSide.BUY,
            quantity=1.0,
            price=60_000.0,
            reason="Block oversize order.",
            source="unit_test",
        )
    )

    assert_equal(blocked.status, PaperOrderStatus.BLOCKED, "oversize order blocked")

    opinions = [
        make_opinion(
            agent_role="market_structure",
            asset="SOL/USD",
            direction=SignalDirection.LONG,
            confidence=88,
            risk_score=30,
            rationale="Strong synthetic setup.",
        ),
        make_opinion(
            agent_role="technical_analysis",
            asset="SOL/USD",
            direction=SignalDirection.LONG,
            confidence=84,
            risk_score=35,
            rationale="Momentum confirms synthetic setup.",
        ),
    ]

    recommendation = aggregate_agent_opinions(asset="SOL/USD", opinions=opinions)
    scorecard = StrategyScoringEngine().score_recommendation(recommendation)

    assert_equal(scorecard.action, DecisionStatus.PAPER_TRADE, "scorecard approved for paper trade")

    scorecard_trade = engine.place_from_scorecard(scorecard, quantity=2.0, price=100.0)

    assert_equal(scorecard_trade.status, PaperOrderStatus.FILLED, "scorecard paper trade filled")
    assert_true("SOL/USD" in engine.positions, "SOL paper position created")

    report = engine.report()

    assert_equal(report.trade_count, 5, "paper report trade count")
    assert_equal(report.filled_count, 3, "paper report filled count")
    assert_equal(report.rejected_count, 1, "paper report rejected count")
    assert_equal(report.blocked_count, 1, "paper report blocked count")
    assert_true("live_trade" not in str(report.to_dict()).lower(), "paper report does not mention live trading")

    try:
        PaperTradingEngine(starting_cash=0)
        raise AssertionError("Invalid starting cash should have failed.")
    except PaperTradingError:
        print("[OK] Invalid starting cash rejected")

    print("Paper trading engine validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
