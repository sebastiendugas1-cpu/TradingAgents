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
