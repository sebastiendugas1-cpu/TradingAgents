# ============================ Slice 10 Validation - Backtesting Engine ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.backtesting import (  # noqa: E402
    BacktestCandle,
    BacktestConfig,
    BacktestEngine,
    BacktestError,
    BacktestSignal,
)
from tradingagents.decision import DecisionStatus, SignalDirection


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def make_candles() -> list[BacktestCandle]:
    prices = [100, 102, 104, 108, 112, 109, 106, 103, 101, 99]

    candles: list[BacktestCandle] = []

    for index, price in enumerate(prices):
        timestamp = 1_700_000_000 + (index * 3600)
        close = prices[index + 1] if index + 1 < len(prices) else price
        high = max(price, close) + 1
        low = min(price, close) - 1

        candles.append(
            BacktestCandle(
                timestamp=timestamp,
                open=float(price),
                high=float(high),
                low=float(low),
                close=float(close),
                volume=1000.0 + index,
            )
        )

    return candles


def main() -> int:
    print("Running Slice 10 backtesting engine validation...")

    candles = make_candles()

    signals = [
        BacktestSignal(
            asset="BTC/USD",
            timestamp=candles[0].timestamp,
            direction=SignalDirection.LONG,
            action=DecisionStatus.PAPER_TRADE,
            confidence_score=88,
            risk_score=35,
            reason="Strong simulated long setup.",
        ),
        BacktestSignal(
            asset="BTC/USD",
            timestamp=candles[5].timestamp,
            direction=SignalDirection.SHORT,
            action=DecisionStatus.MANUAL_REVIEW,
            confidence_score=72,
            risk_score=45,
            reason="Simulated downside setup.",
        ),
        BacktestSignal(
            asset="BTC/USD",
            timestamp=candles[7].timestamp,
            direction=SignalDirection.LONG,
            action=DecisionStatus.BLOCKED,
            confidence_score=90,
            risk_score=90,
            reason="Blocked signal should not create a trade.",
        ),
    ]

    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=10_000.0,
            position_size_pct=10.0,
            fee_rate=0.001,
            slippage_rate=0.0001,
            max_bars_in_trade=2,
        )
    )

    report = engine.run(asset="BTC/USD", candles=candles, signals=signals)

    assert_equal(report.asset, "BTC/USD", "report asset")
    assert_equal(report.trade_count, 2, "blocked signal ignored")
    assert_equal(report.win_count, 2, "both simulated trades are winners")
    assert_equal(report.loss_count, 0, "no losing trades in synthetic test")
    assert_true(report.ending_cash > report.initial_cash, "ending cash increased")
    assert_true(report.total_net_pnl > 0, "total net pnl positive")
    assert_true(report.total_return_pct > 0, "total return positive")
    assert_true(report.win_rate_pct == 100.0, "win rate is 100% in synthetic test")
    assert_true(report.profit_factor == float("inf"), "profit factor infinite with no losses")
    assert_equal(report.trades[0].direction, SignalDirection.LONG, "first trade long")
    assert_equal(report.trades[1].direction, SignalDirection.SHORT, "second trade short")

    report_dict = report.to_dict()
    assert_equal(report_dict["trade_count"], 2, "report dictionary trade count")
    assert_true("live" not in str(report_dict).lower(), "report does not mention live trading")

    try:
        engine.run(asset="", candles=candles, signals=[])
        raise AssertionError("Blank asset should have failed.")
    except BacktestError:
        print("[OK] Blank asset rejected")

    try:
        engine.run(asset="BTC/USD", candles=candles[:1], signals=[])
        raise AssertionError("One-candle backtest should have failed.")
    except BacktestError:
        print("[OK] Not enough candles rejected")

    print("Backtesting engine validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
