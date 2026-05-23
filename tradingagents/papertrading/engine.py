# ============================ Paper Trading Engine ============================
"""
Safe paper-trading simulation engine.

This engine simulates orders against a fake cash balance and fake positions.
It never connects to Kraken and never places live orders.
"""

from __future__ import annotations

from dataclasses import replace

from tradingagents.decision.models import DecisionStatus, SignalDirection
from tradingagents.decision.scoring import StrategyScorecard
from tradingagents.papertrading.models import (
    PaperAccountSnapshot,
    PaperOrderRequest,
    PaperOrderSide,
    PaperOrderStatus,
    PaperPosition,
    PaperTrade,
    PaperTradingReport,
    new_paper_order_id,
    side_from_direction,
    utc_timestamp,
)


class PaperTradingError(ValueError):
    """Raised when a paper-trading action is invalid."""


class PaperTradingEngine:
    """In-memory paper-trading account.

    The account tracks:
    - simulated cash
    - simulated positions
    - simulated fills/rejections/blocks
    - realized P/L from sells

    It is intentionally simple and safe for early development.
    """

    def __init__(
        self,
        *,
        starting_cash: float = 10_000.0,
        fee_rate: float = 0.0026,
        max_order_notional: float = 1_000.0,
        allow_short_selling: bool = False,
    ) -> None:
        if starting_cash <= 0:
            raise PaperTradingError("starting_cash must be greater than zero.")
        if fee_rate < 0:
            raise PaperTradingError("fee_rate cannot be negative.")
        if max_order_notional <= 0:
            raise PaperTradingError("max_order_notional must be greater than zero.")

        self.cash_balance = float(starting_cash)
        self.fee_rate = float(fee_rate)
        self.max_order_notional = float(max_order_notional)
        self.allow_short_selling = bool(allow_short_selling)
        self.positions: dict[str, PaperPosition] = {}
        self.trades: list[PaperTrade] = []
        self.realized_pnl = 0.0

    def snapshot(self) -> PaperAccountSnapshot:
        """Return a simulated account snapshot."""

        return PaperAccountSnapshot(
            cash_balance=round(self.cash_balance, 8),
            positions={asset: replace(position) for asset, position in self.positions.items()},
            realized_pnl=round(self.realized_pnl, 8),
            trade_count=len(self.trades),
        )

    def place_order(self, request: PaperOrderRequest) -> PaperTrade:
        """Place a simulated paper order."""

        asset = request.asset.strip().upper()
        quantity = float(request.quantity)
        price = float(request.price)
        notional = quantity * price
        fee = round(notional * self.fee_rate, 8)

        if notional > self.max_order_notional:
            return self._record_non_fill(
                request=request,
                status=PaperOrderStatus.BLOCKED,
                reason=f"Order notional {notional:.2f} exceeds max_order_notional {self.max_order_notional:.2f}.",
            )

        if request.side == PaperOrderSide.BUY:
            return self._buy(request=request, fee=fee)

        if request.side == PaperOrderSide.SELL:
            return self._sell(request=request, fee=fee)

        raise PaperTradingError(f"Unsupported paper order side: {request.side!r}")

    def place_from_scorecard(
        self,
        scorecard: StrategyScorecard,
        *,
        quantity: float,
        price: float,
        source: str = "strategy_scorecard",
    ) -> PaperTrade:
        """Place a simulated order from a StrategyScorecard.

        Only PAPER_TRADE recommendations are accepted.
        MANUAL_REVIEW, WATCH, and BLOCKED are logged as blocked.
        """

        if scorecard.action != DecisionStatus.PAPER_TRADE:
            side = PaperOrderSide.BUY if scorecard.direction != SignalDirection.SHORT else PaperOrderSide.SELL
            return self._record_non_fill(
                request=PaperOrderRequest(
                    asset=scorecard.asset,
                    side=side,
                    quantity=quantity,
                    price=price,
                    reason=f"Scorecard action is not paper_trade: {scorecard.action.value}",
                    source=source,
                    metadata={"scorecard": scorecard.to_dict()},
                ),
                status=PaperOrderStatus.BLOCKED,
                reason=f"Scorecard action is not paper_trade: {scorecard.action.value}",
            )

        side = side_from_direction(scorecard.direction)

        return self.place_order(
            PaperOrderRequest(
                asset=scorecard.asset,
                side=side,
                quantity=quantity,
                price=price,
                reason=scorecard.reason_summary,
                source=source,
                metadata={"scorecard": scorecard.to_dict()},
            )
        )

    def report(self) -> PaperTradingReport:
        """Return a full paper-trading report."""

        filled_count = sum(1 for trade in self.trades if trade.status == PaperOrderStatus.FILLED)
        rejected_count = sum(1 for trade in self.trades if trade.status == PaperOrderStatus.REJECTED)
        blocked_count = sum(1 for trade in self.trades if trade.status == PaperOrderStatus.BLOCKED)

        return PaperTradingReport(
            cash_balance=round(self.cash_balance, 8),
            realized_pnl=round(self.realized_pnl, 8),
            trade_count=len(self.trades),
            filled_count=filled_count,
            rejected_count=rejected_count,
            blocked_count=blocked_count,
            positions={asset: replace(position) for asset, position in self.positions.items()},
            trades=list(self.trades),
        )

    def _buy(self, request: PaperOrderRequest, fee: float) -> PaperTrade:
        asset = request.asset.strip().upper()
        quantity = float(request.quantity)
        price = float(request.price)
        notional = quantity * price
        total_cost = notional + fee
        cash_before = self.cash_balance
        position_before = self.positions.get(asset, PaperPosition(asset=asset)).quantity

        if total_cost > self.cash_balance:
            return self._record_non_fill(
                request=request,
                status=PaperOrderStatus.REJECTED,
                reason=f"Insufficient paper cash. Required {total_cost:.2f}, available {self.cash_balance:.2f}.",
            )

        position = self.positions.get(asset, PaperPosition(asset=asset))

        new_quantity = position.quantity + quantity
        if new_quantity <= 0:
            new_average_cost = 0.0
        else:
            previous_cost = position.quantity * position.average_cost
            new_average_cost = (previous_cost + notional + fee) / new_quantity

        self.cash_balance -= total_cost
        self.positions[asset] = PaperPosition(
            asset=asset,
            quantity=round(new_quantity, 12),
            average_cost=round(new_average_cost, 8),
        )

        return self._record_trade(
            request=request,
            fee=fee,
            status=PaperOrderStatus.FILLED,
            reason=request.reason,
            cash_before=cash_before,
            cash_after=self.cash_balance,
            position_before=position_before,
            position_after=self.positions[asset].quantity,
        )

    def _sell(self, request: PaperOrderRequest, fee: float) -> PaperTrade:
        asset = request.asset.strip().upper()
        quantity = float(request.quantity)
        price = float(request.price)
        notional = quantity * price
        cash_before = self.cash_balance
        position = self.positions.get(asset, PaperPosition(asset=asset))
        position_before = position.quantity

        if not self.allow_short_selling and quantity > position.quantity:
            return self._record_non_fill(
                request=request,
                status=PaperOrderStatus.REJECTED,
                reason=f"Insufficient paper position. Tried to sell {quantity}, available {position.quantity}.",
            )

        proceeds = notional - fee
        self.cash_balance += proceeds

        new_quantity = position.quantity - quantity
        realized = (price - position.average_cost) * quantity - fee
        self.realized_pnl += realized

        if new_quantity <= 0:
            self.positions.pop(asset, None)
            position_after = 0.0
        else:
            self.positions[asset] = PaperPosition(
                asset=asset,
                quantity=round(new_quantity, 12),
                average_cost=position.average_cost,
            )
            position_after = self.positions[asset].quantity

        return self._record_trade(
            request=request,
            fee=fee,
            status=PaperOrderStatus.FILLED,
            reason=request.reason,
            cash_before=cash_before,
            cash_after=self.cash_balance,
            position_before=position_before,
            position_after=position_after,
        )

    def _record_non_fill(
        self,
        *,
        request: PaperOrderRequest,
        status: PaperOrderStatus,
        reason: str,
    ) -> PaperTrade:
        asset = request.asset.strip().upper()
        position = self.positions.get(asset, PaperPosition(asset=asset))

        return self._record_trade(
            request=request,
            fee=0.0,
            status=status,
            reason=reason,
            cash_before=self.cash_balance,
            cash_after=self.cash_balance,
            position_before=position.quantity,
            position_after=position.quantity,
        )

    def _record_trade(
        self,
        *,
        request: PaperOrderRequest,
        fee: float,
        status: PaperOrderStatus,
        reason: str,
        cash_before: float,
        cash_after: float,
        position_before: float,
        position_after: float,
    ) -> PaperTrade:
        trade = PaperTrade(
            order_id=new_paper_order_id(),
            timestamp_utc=utc_timestamp(),
            asset=request.asset.strip().upper(),
            side=request.side,
            quantity=float(request.quantity),
            price=float(request.price),
            fee=round(fee, 8),
            status=status,
            reason=reason,
            source=request.source,
            cash_before=round(cash_before, 8),
            cash_after=round(cash_after, 8),
            position_before=round(position_before, 12),
            position_after=round(position_after, 12),
            metadata=request.metadata,
        )

        self.trades.append(trade)
        return trade
