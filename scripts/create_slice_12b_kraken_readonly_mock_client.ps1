# ============================ Slice 12B - Kraken Read-Only Mock Private Client ============================
# Purpose:
# Creates a mock-only Kraken read-only private client foundation.
#
# This slice does NOT call Kraken.
# This slice does NOT require real Kraken API keys.
# This slice does NOT place orders.
# This slice does NOT read real balances or orders.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_12b_kraken_readonly_mock_client.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$KrakenPath = Join-Path $ProjectRoot "tradingagents\kraken"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path $KrakenPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $FullPath = Join-Path $ProjectRoot $Path
    $Folder = Split-Path -Parent $FullPath

    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    }

    Set-Content -Path $FullPath -Value $Content -Encoding UTF8
}

Write-ProjectFile "tradingagents\kraken\private_readonly.py" @'
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
'@

Write-ProjectFile "tradingagents\kraken\__init__.py" @'
# ============================ Kraken Package Exports ============================

from tradingagents.kraken.config import KrakenReadOnlyConfig, KrakenReadOnlyConfigError
from tradingagents.kraken.private_readonly import (
    KrakenBalance,
    KrakenOpenOrder,
    KrakenReadOnlyClientError,
    KrakenReadOnlyMode,
    KrakenReadOnlySnapshot,
    KrakenTradeHistoryItem,
    MockKrakenReadOnlyClient,
    create_default_mock_kraken_readonly_client,
)

__all__ = [
    "KrakenReadOnlyConfig",
    "KrakenReadOnlyConfigError",
    "KrakenBalance",
    "KrakenOpenOrder",
    "KrakenReadOnlyClientError",
    "KrakenReadOnlyMode",
    "KrakenReadOnlySnapshot",
    "KrakenTradeHistoryItem",
    "MockKrakenReadOnlyClient",
    "create_default_mock_kraken_readonly_client",
]
'@

Write-ProjectFile "scripts\test_kraken_readonly_mock_client.py" @'
# ============================ Slice 12B Validation - Kraken Read-Only Mock Client ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken import (  # noqa: E402
    KrakenReadOnlyClientError,
    KrakenReadOnlyMode,
    create_default_mock_kraken_readonly_client,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def assert_raises_readonly_error(callback, label: str) -> None:
    try:
        callback()
    except KrakenReadOnlyClientError:
        print(f"[OK] {label}")
        return

    raise AssertionError(f"{label}: expected KrakenReadOnlyClientError")


def main() -> int:
    print("Running Slice 12B Kraken read-only mock client validation...")

    client = create_default_mock_kraken_readonly_client()

    assert_equal(client.mode, KrakenReadOnlyMode.MOCK, "client mode is mock")

    balances = client.get_balances()
    open_orders = client.get_open_orders()
    trade_history = client.get_trade_history()

    assert_equal(len(balances), 2, "mock balance count")
    assert_equal(len(open_orders), 1, "mock open order count")
    assert_equal(len(trade_history), 1, "mock trade history count")

    assert_equal(balances[0].asset, "USD", "first balance asset")
    assert_true(balances[0].available > 0, "USD available balance positive")

    assert_equal(open_orders[0].pair, "BTC/USD", "mock open order pair")
    assert_equal(open_orders[0].side, "buy", "mock open order side")

    snapshot = client.get_account_snapshot()
    snapshot_dict = snapshot.to_dict()

    assert_equal(snapshot.source, "mock", "snapshot source")
    assert_equal(len(snapshot.balances), 2, "snapshot balance count")
    assert_equal(len(snapshot.open_orders), 1, "snapshot open order count")
    assert_equal(len(snapshot.trade_history), 1, "snapshot trade history count")
    assert_true("secret" not in str(snapshot_dict).lower(), "snapshot does not reveal secrets")
    assert_true("api_key" not in str(snapshot_dict).lower(), "snapshot does not reveal API key")

    assert_raises_readonly_error(lambda: client.place_order(), "place_order blocked")
    assert_raises_readonly_error(lambda: client.cancel_order(), "cancel_order blocked")
    assert_raises_readonly_error(lambda: client.withdraw(), "withdraw blocked")
    assert_raises_readonly_error(lambda: client.funding_operation(), "funding operation blocked")

    print("Kraken read-only mock client validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# Update docs with append-only notes to avoid fragile regex replacements.
$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $RoadmapText = Get-Content $RoadmapPath -Raw
    if ($RoadmapText -notmatch "Slice 12B — Kraken Read-Only Mock Private Client") {
        Add-Content -Path $RoadmapPath -Encoding UTF8 -Value @'

## Slice 12B — Kraken Read-Only Mock Private Client

Goal:

Create a mock-only read-only Kraken private client interface before using real Kraken API keys.

Safety:

- No real Kraken private API calls.
- No real account access.
- No trading.
- No withdrawals.
- No funding actions.
- All execution-like methods must be explicitly blocked.

Validation:

- Mock balances can be read.
- Mock open orders can be read.
- Mock trade history can be read.
- Combined snapshot can be generated.
- `place_order`, `cancel_order`, `withdraw`, and funding actions are blocked.
'@
    }
}

$KrakenPlanPath = Join-Path $DocsPath "07_KRAKEN_PLAN.md"
if (Test-Path $KrakenPlanPath) {
    $KrakenPlanText = Get-Content $KrakenPlanPath -Raw
    if ($KrakenPlanText -notmatch "Slice 12B Mock-Only Rule") {
        Add-Content -Path $KrakenPlanPath -Encoding UTF8 -Value @'

## Slice 12B Mock-Only Rule

Before real private Kraken API calls are implemented, the project uses a mock-only read-only private client.

This mock client proves the interface for:

- Balances.
- Open orders.
- Trade history.
- Account snapshot.

It also proves that dangerous operations are blocked:

- Placing orders.
- Canceling orders.
- Withdrawals.
- Funding operations.

No real Kraken keys are required for Slice 12B.
'@
    }
}

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    $DecisionLogText = Get-Content $DecisionLogPath -Raw
    if ($DecisionLogText -notmatch "Slice 12B") {
        Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 12B Kraken Read-Only Mock Client

Decision:

The first Kraken private-client implementation will be mock-only.

Reason:

This allows the project to define and test the account-data interface before any real Kraken API keys are used.

Safety rules:

- No private Kraken API calls.
- No real balance reads.
- No order placement.
- No order cancellation.
- No withdrawals.
- No funding operations.
'@
    }
}

Write-Host "=== SLICE 12B FILES CREATED ==="
Get-ChildItem $KrakenPath | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 12B VALIDATION ==="
python .\scripts\test_kraken_readonly_mock_client.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 12B script completed."
