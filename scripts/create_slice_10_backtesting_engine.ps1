# ============================ Slice 10 - Backtesting Engine ============================
# Purpose:
# Creates a safe historical simulation layer for strategy scorecards / signals.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_10_backtesting_engine.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$BacktestingPath = Join-Path $ProjectRoot "tradingagents\backtesting"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path $BacktestingPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $Folder = Split-Path $Path -Parent
    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-ProjectFile (Join-Path $BacktestingPath "__init__.py") @'
# ============================ Backtesting Package Exports ============================

from tradingagents.backtesting.engine import BacktestEngine, BacktestError
from tradingagents.backtesting.models import (
    BacktestCandle,
    BacktestConfig,
    BacktestReport,
    BacktestSignal,
    SimulatedTrade,
)

__all__ = [
    "BacktestEngine",
    "BacktestError",
    "BacktestCandle",
    "BacktestConfig",
    "BacktestReport",
    "BacktestSignal",
    "SimulatedTrade",
]
'@

Write-ProjectFile (Join-Path $BacktestingPath "models.py") @'
# ============================ Backtesting Models ============================
"""
Safe historical simulation models.

This module contains no live trading code.
It only describes historical candles, simulated signals, simulated trades,
and backtest reports.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

from tradingagents.decision import DecisionStatus, SignalDirection


@dataclass(frozen=True)
class BacktestCandle:
    """Single OHLCV candle used by the backtesting engine."""

    timestamp: int
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0

    def __post_init__(self) -> None:
        if self.timestamp <= 0:
            raise ValueError("BacktestCandle.timestamp must be positive.")
        for field_name in ("open", "high", "low", "close"):
            value = getattr(self, field_name)
            if value <= 0:
                raise ValueError(f"BacktestCandle.{field_name} must be positive.")
        if self.volume < 0:
            raise ValueError("BacktestCandle.volume cannot be negative.")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class BacktestSignal:
    """Simulated strategy signal used for historical testing.

    This is not an order. It is an input to the simulator only.
    """

    asset: str
    timestamp: int
    direction: SignalDirection
    action: DecisionStatus
    confidence_score: int
    risk_score: int
    reason: str = ""

    def __post_init__(self) -> None:
        if not self.asset.strip():
            raise ValueError("BacktestSignal.asset cannot be blank.")
        if self.timestamp <= 0:
            raise ValueError("BacktestSignal.timestamp must be positive.")
        if self.confidence_score < 0 or self.confidence_score > 100:
            raise ValueError("BacktestSignal.confidence_score must be 0-100.")
        if self.risk_score < 0 or self.risk_score > 100:
            raise ValueError("BacktestSignal.risk_score must be 0-100.")

    @property
    def is_trade_candidate(self) -> bool:
        """Only paper/manual review recommendations can be simulated."""

        return self.action in {DecisionStatus.PAPER_TRADE, DecisionStatus.MANUAL_REVIEW}


@dataclass(frozen=True)
class BacktestConfig:
    """Configuration for the safe historical simulator."""

    initial_cash: float = 10_000.0
    position_size_pct: float = 10.0
    fee_rate: float = 0.0026
    slippage_rate: float = 0.0005
    max_bars_in_trade: int = 3
    allow_short: bool = True

    def __post_init__(self) -> None:
        if self.initial_cash <= 0:
            raise ValueError("initial_cash must be positive.")
        if self.position_size_pct <= 0 or self.position_size_pct > 100:
            raise ValueError("position_size_pct must be between 0 and 100.")
        if self.fee_rate < 0:
            raise ValueError("fee_rate cannot be negative.")
        if self.slippage_rate < 0:
            raise ValueError("slippage_rate cannot be negative.")
        if self.max_bars_in_trade < 1:
            raise ValueError("max_bars_in_trade must be at least 1.")


@dataclass(frozen=True)
class SimulatedTrade:
    """One simulated historical trade."""

    asset: str
    direction: SignalDirection
    entry_time: int
    exit_time: int
    entry_price: float
    exit_price: float
    quantity: float
    gross_pnl: float
    fees: float
    net_pnl: float
    reason: str = ""

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["direction"] = self.direction.value
        return data


@dataclass(frozen=True)
class BacktestReport:
    """Summary report generated by a backtest run."""

    asset: str
    initial_cash: float
    ending_cash: float
    total_net_pnl: float
    total_return_pct: float
    max_drawdown_pct: float
    trade_count: int
    win_count: int
    loss_count: int
    win_rate_pct: float
    profit_factor: float | None
    trades: list[SimulatedTrade] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["trades"] = [trade.to_dict() for trade in self.trades]
        return data
'@

Write-ProjectFile (Join-Path $BacktestingPath "engine.py") @'
# ============================ Backtesting Engine ============================
"""
Safe historical backtesting engine.

This engine simulates trades from historical candles and structured signals.
It does not connect to exchanges.
It does not place orders.
It does not read private Kraken data.
"""

from __future__ import annotations

from math import isfinite

from tradingagents.backtesting.models import (
    BacktestCandle,
    BacktestConfig,
    BacktestReport,
    BacktestSignal,
    SimulatedTrade,
)
from tradingagents.decision import DecisionStatus, SignalDirection


class BacktestError(ValueError):
    """Raised when the backtest input is invalid."""


class BacktestEngine:
    """Small deterministic historical simulator for strategy validation."""

    def __init__(self, config: BacktestConfig | None = None) -> None:
        self.config = config or BacktestConfig()

    def run(
        self,
        *,
        asset: str,
        candles: list[BacktestCandle],
        signals: list[BacktestSignal],
    ) -> BacktestReport:
        """Run a safe historical simulation.

        Rules:
        - Signals are matched to candle timestamps.
        - Trade entries use the next candle open.
        - Trade exits use max_bars_in_trade or the final available candle.
        - Only PAPER_TRADE and MANUAL_REVIEW actions are simulated.
        - BLOCKED and WATCH signals do not open trades.
        """

        normalized_asset = asset.strip().upper()
        if not normalized_asset:
            raise BacktestError("asset cannot be blank.")

        candles_sorted = sorted(candles, key=lambda candle: candle.timestamp)
        signals_sorted = sorted(signals, key=lambda signal: signal.timestamp)

        if len(candles_sorted) < 2:
            raise BacktestError("At least two candles are required for a backtest.")

        for candle in candles_sorted:
            self._validate_candle(candle)

        for signal in signals_sorted:
            if signal.asset.upper() != normalized_asset:
                raise BacktestError(
                    f"Signal asset mismatch. Expected {normalized_asset}, got {signal.asset}."
                )

        candle_index_by_time = {
            candle.timestamp: index for index, candle in enumerate(candles_sorted)
        }

        cash = self.config.initial_cash
        peak_cash = cash
        max_drawdown_pct = 0.0
        trades: list[SimulatedTrade] = []
        occupied_until_index = -1

        for signal in signals_sorted:
            if not signal.is_trade_candidate:
                continue

            if signal.direction == SignalDirection.NEUTRAL:
                continue

            if signal.direction == SignalDirection.SHORT and not self.config.allow_short:
                continue

            signal_index = candle_index_by_time.get(signal.timestamp)

            if signal_index is None:
                continue

            entry_index = signal_index + 1

            if entry_index >= len(candles_sorted):
                continue

            if entry_index <= occupied_until_index:
                continue

            exit_index = min(
                entry_index + self.config.max_bars_in_trade,
                len(candles_sorted) - 1,
            )

            trade = self._simulate_trade(
                asset=normalized_asset,
                signal=signal,
                entry_candle=candles_sorted[entry_index],
                exit_candle=candles_sorted[exit_index],
                cash=cash,
            )

            cash += trade.net_pnl
            trades.append(trade)
            occupied_until_index = exit_index

            if cash > peak_cash:
                peak_cash = cash

            drawdown_pct = 0.0
            if peak_cash > 0:
                drawdown_pct = ((peak_cash - cash) / peak_cash) * 100.0

            max_drawdown_pct = max(max_drawdown_pct, drawdown_pct)

        return self._build_report(
            asset=normalized_asset,
            initial_cash=self.config.initial_cash,
            ending_cash=cash,
            max_drawdown_pct=max_drawdown_pct,
            trades=trades,
        )

    def _simulate_trade(
        self,
        *,
        asset: str,
        signal: BacktestSignal,
        entry_candle: BacktestCandle,
        exit_candle: BacktestCandle,
        cash: float,
    ) -> SimulatedTrade:
        position_value = cash * (self.config.position_size_pct / 100.0)

        if signal.direction == SignalDirection.LONG:
            entry_price = entry_candle.open * (1.0 + self.config.slippage_rate)
            exit_price = exit_candle.close * (1.0 - self.config.slippage_rate)
            quantity = position_value / entry_price
            gross_pnl = (exit_price - entry_price) * quantity
        elif signal.direction == SignalDirection.SHORT:
            entry_price = entry_candle.open * (1.0 - self.config.slippage_rate)
            exit_price = exit_candle.close * (1.0 + self.config.slippage_rate)
            quantity = position_value / entry_price
            gross_pnl = (entry_price - exit_price) * quantity
        else:
            raise BacktestError("Neutral signals cannot be simulated as trades.")

        fees = (entry_price * quantity * self.config.fee_rate) + (
            exit_price * quantity * self.config.fee_rate
        )

        net_pnl = gross_pnl - fees

        return SimulatedTrade(
            asset=asset,
            direction=signal.direction,
            entry_time=entry_candle.timestamp,
            exit_time=exit_candle.timestamp,
            entry_price=entry_price,
            exit_price=exit_price,
            quantity=quantity,
            gross_pnl=gross_pnl,
            fees=fees,
            net_pnl=net_pnl,
            reason=signal.reason,
        )

    @staticmethod
    def _validate_candle(candle: BacktestCandle) -> None:
        values = [candle.open, candle.high, candle.low, candle.close, candle.volume]

        if not all(isfinite(value) for value in values):
            raise BacktestError(f"Candle contains a non-finite value: {candle}")

        if candle.high < max(candle.open, candle.close):
            raise BacktestError(f"Candle high is inconsistent: {candle}")

        if candle.low > min(candle.open, candle.close):
            raise BacktestError(f"Candle low is inconsistent: {candle}")

    @staticmethod
    def _build_report(
        *,
        asset: str,
        initial_cash: float,
        ending_cash: float,
        max_drawdown_pct: float,
        trades: list[SimulatedTrade],
    ) -> BacktestReport:
        total_net_pnl = ending_cash - initial_cash
        total_return_pct = (total_net_pnl / initial_cash) * 100.0

        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]

        gross_profit = sum(trade.net_pnl for trade in wins)
        gross_loss = abs(sum(trade.net_pnl for trade in losses))

        profit_factor = None
        if gross_loss > 0:
            profit_factor = gross_profit / gross_loss
        elif gross_profit > 0:
            profit_factor = float("inf")

        trade_count = len(trades)
        win_rate_pct = (len(wins) / trade_count) * 100.0 if trade_count else 0.0

        return BacktestReport(
            asset=asset,
            initial_cash=initial_cash,
            ending_cash=ending_cash,
            total_net_pnl=total_net_pnl,
            total_return_pct=total_return_pct,
            max_drawdown_pct=max_drawdown_pct,
            trade_count=trade_count,
            win_count=len(wins),
            loss_count=len(losses),
            win_rate_pct=win_rate_pct,
            profit_factor=profit_factor,
            trades=trades,
        )
'@

Write-ProjectFile (Join-Path $ScriptsPath "test_backtesting_engine.py") @'
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
'@

$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
$GitIgnoreText = ""
if (Test-Path $GitIgnorePath) {
    $GitIgnoreText = Get-Content $GitIgnorePath -Raw
}

if ($GitIgnoreText -notmatch "(?m)^\.backtests/$") {
    Add-Content -Path $GitIgnorePath -Value "`n# Local generated backtest outputs`n.backtests/"
}

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $RoadmapText = Get-Content $RoadmapPath -Raw
    $RoadmapText = $RoadmapText.Replace(
        "## Slice 10 — Backtesting Engine`r`n`r`nGoal:`r`n`r`nEvaluate strategies against historical data.",
        "## Slice 10 — Backtesting Engine`r`n`r`nStatus: Complete.`r`n`r`nGoal:`r`n`r`nEvaluate strategies against historical data."
    )
    $RoadmapText = $RoadmapText.Replace(
        "## Slice 10 — Backtesting Engine`n`nGoal:`n`nEvaluate strategies against historical data.",
        "## Slice 10 — Backtesting Engine`n`nStatus: Complete.`n`nGoal:`n`nEvaluate strategies against historical data."
    )
    Set-Content -Path $RoadmapPath -Value $RoadmapText -Encoding UTF8
}

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    Add-Content -Path $DecisionLogPath -Value @'

## 2026-05-22 — Slice 10 Backtesting Engine

Decision:

A safe historical backtesting layer was added.

Key points:

- The backtesting engine simulates historical trades only.
- It does not place orders.
- It does not call Kraken private APIs.
- It supports long and short simulations.
- It uses candle data and structured simulated signals.
- Outputs include simulated trades, P/L, win rate, drawdown, and profit factor.
'@
}

Write-Host "=== SLICE 10 FILES CREATED ==="
Get-ChildItem $BacktestingPath | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 10 VALIDATION ==="
python .\scripts\test_backtesting_engine.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 10 script completed."
