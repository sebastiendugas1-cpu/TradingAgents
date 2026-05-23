# ============================ Paper Trading Models ============================
"""
Safe paper-trading models.

These models represent simulated balances, orders, fills, and reports.
They do not connect to any exchange and do not place live trades.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from enum import Enum
from typing import Any
from uuid import uuid4

from tradingagents.decision.models import SignalDirection


class PaperOrderStatus(str, Enum):
    """Status for simulated paper orders."""

    FILLED = "filled"
    REJECTED = "rejected"
    BLOCKED = "blocked"


class PaperOrderSide(str, Enum):
    """Side for simulated paper orders."""

    BUY = "buy"
    SELL = "sell"


@dataclass(frozen=True)
class PaperOrderRequest:
    """A request to place a simulated paper order."""

    asset: str
    side: PaperOrderSide
    quantity: float
    price: float
    reason: str
    source: str = "manual"
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.asset.strip():
            raise ValueError("PaperOrderRequest.asset cannot be blank.")
        if self.quantity <= 0:
            raise ValueError("PaperOrderRequest.quantity must be greater than zero.")
        if self.price <= 0:
            raise ValueError("PaperOrderRequest.price must be greater than zero.")
        if not self.reason.strip():
            raise ValueError("PaperOrderRequest.reason cannot be blank.")

    @property
    def notional_value(self) -> float:
        return self.quantity * self.price


@dataclass(frozen=True)
class PaperTrade:
    """A simulated paper trade fill or rejected/blocked order."""

    order_id: str
    timestamp_utc: str
    asset: str
    side: PaperOrderSide
    quantity: float
    price: float
    fee: float
    status: PaperOrderStatus
    reason: str
    source: str = "manual"
    cash_before: float = 0.0
    cash_after: float = 0.0
    position_before: float = 0.0
    position_after: float = 0.0
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def notional_value(self) -> float:
        return self.quantity * self.price

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["side"] = self.side.value
        data["status"] = self.status.value
        return data


@dataclass
class PaperPosition:
    """Simulated position for one asset."""

    asset: str
    quantity: float = 0.0
    average_cost: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class PaperAccountSnapshot:
    """Snapshot of the simulated paper account."""

    cash_balance: float
    positions: dict[str, PaperPosition]
    realized_pnl: float
    trade_count: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "cash_balance": self.cash_balance,
            "positions": {asset: position.to_dict() for asset, position in self.positions.items()},
            "realized_pnl": self.realized_pnl,
            "trade_count": self.trade_count,
        }


@dataclass(frozen=True)
class PaperTradingReport:
    """Report for the paper trading account."""

    cash_balance: float
    realized_pnl: float
    trade_count: int
    filled_count: int
    rejected_count: int
    blocked_count: int
    positions: dict[str, PaperPosition]
    trades: list[PaperTrade]

    def to_dict(self) -> dict[str, Any]:
        return {
            "cash_balance": self.cash_balance,
            "realized_pnl": self.realized_pnl,
            "trade_count": self.trade_count,
            "filled_count": self.filled_count,
            "rejected_count": self.rejected_count,
            "blocked_count": self.blocked_count,
            "positions": {asset: position.to_dict() for asset, position in self.positions.items()},
            "trades": [trade.to_dict() for trade in self.trades],
        }


def new_paper_order_id() -> str:
    """Create a readable simulated order id."""

    return f"PAPER-{uuid4().hex[:12].upper()}"


def utc_timestamp() -> str:
    """Return an ISO UTC timestamp."""

    return datetime.now(UTC).isoformat()


def side_from_direction(direction: SignalDirection) -> PaperOrderSide:
    """Map a signal direction to a paper order side."""

    if direction == SignalDirection.LONG:
        return PaperOrderSide.BUY
    if direction == SignalDirection.SHORT:
        return PaperOrderSide.SELL
    raise ValueError(f"Cannot convert neutral direction to paper order side: {direction!r}")
