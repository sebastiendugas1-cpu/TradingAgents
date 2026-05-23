# ============================ Kraken Read-Only Mock Private Client ============================
"""
Mock-only Kraken read-only private client.

Purpose:
- Provide a safe private-client interface before using real Kraken API keys.
- Support local tests for balances, open orders, and trade history.
- Prevent order placement, cancellation, funding, and withdrawal operations.

Safety:
- No network calls.
- No live trading.
- No real account access.
- No private Kraken API calls.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from decimal import Decimal
from enum import Enum
from typing import Any


class KrakenReadOnlyClientError(RuntimeError):
    """Raised when a read-only Kraken client operation is invalid."""


class KrakenReadOnlyMode(str, Enum):
    """Supported read-only client operating modes."""

    MOCK = "mock"


@dataclass(frozen=True)
class KrakenBalance:
    """Read-only balance snapshot."""

    asset: str
    total: Decimal
    available: Decimal
    hold: Decimal = Decimal("0")
    timestamp: datetime = field(default_factory=lambda: datetime.now(UTC))

    def __post_init__(self) -> None:
        if not self.asset.strip():
            raise ValueError("KrakenBalance.asset cannot be blank.")
        if self.total < 0 or self.available < 0 or self.hold < 0:
            raise ValueError("Kraken balances cannot be negative.")
        if self.available + self.hold > self.total:
            raise ValueError("available + hold cannot exceed total.")

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["total"] = str(self.total)
        data["available"] = str(self.available)
        data["hold"] = str(self.hold)
        data["timestamp"] = self.timestamp.isoformat()
        return data


@dataclass(frozen=True)
class KrakenOpenOrder:
    """Read-only open order snapshot."""

    order_id: str
    pair: str
    side: str
    order_type: str
    volume: Decimal
    price: Decimal | None
    status: str = "open"
    timestamp: datetime = field(default_factory=lambda: datetime.now(UTC))

    def __post_init__(self) -> None:
        if not self.order_id.strip():
            raise ValueError("KrakenOpenOrder.order_id cannot be blank.")
        if not self.pair.strip():
            raise ValueError("KrakenOpenOrder.pair cannot be blank.")
        if self.side not in {"buy", "sell"}:
            raise ValueError("KrakenOpenOrder.side must be buy or sell.")
        if self.volume <= 0:
            raise ValueError("KrakenOpenOrder.volume must be positive.")
        if self.price is not None and self.price <= 0:
            raise ValueError("KrakenOpenOrder.price must be positive when provided.")

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["volume"] = str(self.volume)
        data["price"] = str(self.price) if self.price is not None else None
        data["timestamp"] = self.timestamp.isoformat()
        return data


@dataclass(frozen=True)
class KrakenTradeHistoryItem:
    """Read-only historical trade snapshot."""

    trade_id: str
    order_id: str
    pair: str
    side: str
    volume: Decimal
    price: Decimal
    fee: Decimal
    timestamp: datetime = field(default_factory=lambda: datetime.now(UTC))

    def __post_init__(self) -> None:
        if not self.trade_id.strip():
            raise ValueError("KrakenTradeHistoryItem.trade_id cannot be blank.")
        if not self.order_id.strip():
            raise ValueError("KrakenTradeHistoryItem.order_id cannot be blank.")
        if not self.pair.strip():
            raise ValueError("KrakenTradeHistoryItem.pair cannot be blank.")
        if self.side not in {"buy", "sell"}:
            raise ValueError("KrakenTradeHistoryItem.side must be buy or sell.")
        if self.volume <= 0:
            raise ValueError("KrakenTradeHistoryItem.volume must be positive.")
        if self.price <= 0:
            raise ValueError("KrakenTradeHistoryItem.price must be positive.")
        if self.fee < 0:
            raise ValueError("KrakenTradeHistoryItem.fee cannot be negative.")

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["volume"] = str(self.volume)
        data["price"] = str(self.price)
        data["fee"] = str(self.fee)
        data["timestamp"] = self.timestamp.isoformat()
        return data


@dataclass
class KrakenReadOnlySnapshot:
    """Combined read-only account snapshot."""

    balances: list[KrakenBalance] = field(default_factory=list)
    open_orders: list[KrakenOpenOrder] = field(default_factory=list)
    trade_history: list[KrakenTradeHistoryItem] = field(default_factory=list)
    timestamp: datetime = field(default_factory=lambda: datetime.now(UTC))
    source: str = "mock"

    def to_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "timestamp": self.timestamp.isoformat(),
            "balances": [item.to_dict() for item in self.balances],
            "open_orders": [item.to_dict() for item in self.open_orders],
            "trade_history": [item.to_dict() for item in self.trade_history],
        }


class MockKrakenReadOnlyClient:
    """Mock-only read-only client used before real private Kraken integration."""

    mode = KrakenReadOnlyMode.MOCK

    def __init__(
        self,
        *,
        balances: list[KrakenBalance] | None = None,
        open_orders: list[KrakenOpenOrder] | None = None,
        trade_history: list[KrakenTradeHistoryItem] | None = None,
    ) -> None:
        self._balances = list(balances or [])
        self._open_orders = list(open_orders or [])
        self._trade_history = list(trade_history or [])

    def get_balances(self) -> list[KrakenBalance]:
        """Return mock balances only."""

        return list(self._balances)

    def get_open_orders(self) -> list[KrakenOpenOrder]:
        """Return mock open orders only."""

        return list(self._open_orders)

    def get_trade_history(self) -> list[KrakenTradeHistoryItem]:
        """Return mock trade history only."""

        return list(self._trade_history)

    def get_account_snapshot(self) -> KrakenReadOnlySnapshot:
        """Return a combined mock account snapshot."""

        return KrakenReadOnlySnapshot(
            balances=self.get_balances(),
            open_orders=self.get_open_orders(),
            trade_history=self.get_trade_history(),
            source=self.mode.value,
        )

    def place_order(self, *_args: Any, **_kwargs: Any) -> None:
        """Explicitly blocked: read-only client cannot place orders."""

        raise KrakenReadOnlyClientError("Read-only Kraken client cannot place orders.")

    def cancel_order(self, *_args: Any, **_kwargs: Any) -> None:
        """Explicitly blocked: read-only client cannot cancel orders."""

        raise KrakenReadOnlyClientError("Read-only Kraken client cannot cancel orders.")

    def withdraw(self, *_args: Any, **_kwargs: Any) -> None:
        """Explicitly blocked: withdrawals are forbidden."""

        raise KrakenReadOnlyClientError("Read-only Kraken client cannot withdraw funds.")

    def funding_operation(self, *_args: Any, **_kwargs: Any) -> None:
        """Explicitly blocked: funding operations are forbidden."""

        raise KrakenReadOnlyClientError("Read-only Kraken client cannot perform funding operations.")


def create_default_mock_kraken_readonly_client() -> MockKrakenReadOnlyClient:
    """Create a deterministic mock read-only client for validation and demos."""

    return MockKrakenReadOnlyClient(
        balances=[
            KrakenBalance(
                asset="USD",
                total=Decimal("10000.00"),
                available=Decimal("9500.00"),
                hold=Decimal("500.00"),
            ),
            KrakenBalance(
                asset="BTC",
                total=Decimal("0.125"),
                available=Decimal("0.100"),
                hold=Decimal("0.025"),
            ),
        ],
        open_orders=[
            KrakenOpenOrder(
                order_id="MOCK-OPEN-001",
                pair="BTC/USD",
                side="buy",
                order_type="limit",
                volume=Decimal("0.025"),
                price=Decimal("65000.00"),
            )
        ],
        trade_history=[
            KrakenTradeHistoryItem(
                trade_id="MOCK-TRADE-001",
                order_id="MOCK-CLOSED-001",
                pair="BTC/USD",
                side="buy",
                volume=Decimal("0.100"),
                price=Decimal("60000.00"),
                fee=Decimal("15.00"),
            )
        ],
    )
