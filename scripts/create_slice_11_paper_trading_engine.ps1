# ============================ Slice 11 - Paper Trading Engine ============================
# Purpose:
# Creates a safe paper-trading simulation layer.
#
# This slice does NOT:
# - place live trades
# - use Kraken private API
# - read real balances
# - execute orders
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_11_paper_trading_engine.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$PaperPath = Join-Path $ProjectRoot "tradingagents\papertrading"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $PaperPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $Folder = Split-Path -Parent $Path
    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# ============================ papertrading models ============================

Write-ProjectFile (Join-Path $PaperPath "models.py") @'
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
'@

# ============================ papertrading engine ============================

Write-ProjectFile (Join-Path $PaperPath "engine.py") @'
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
'@

# ============================ papertrading init ============================

Write-ProjectFile (Join-Path $PaperPath "__init__.py") @'
# ============================ Paper Trading Package Exports ============================

from tradingagents.papertrading.engine import PaperTradingEngine, PaperTradingError
from tradingagents.papertrading.models import (
    PaperAccountSnapshot,
    PaperOrderRequest,
    PaperOrderSide,
    PaperOrderStatus,
    PaperPosition,
    PaperTrade,
    PaperTradingReport,
    side_from_direction,
)

__all__ = [
    "PaperTradingEngine",
    "PaperTradingError",
    "PaperAccountSnapshot",
    "PaperOrderRequest",
    "PaperOrderSide",
    "PaperOrderStatus",
    "PaperPosition",
    "PaperTrade",
    "PaperTradingReport",
    "side_from_direction",
]
'@

# ============================ validation script ============================

Write-ProjectFile (Join-Path $ScriptsPath "test_paper_trading_engine.py") @'
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
'@

# ============================ docs updates ============================

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $roadmap = Get-Content $RoadmapPath -Raw
    $roadmap = $roadmap -replace "## Slice 11 — Paper Trading Engine\s+Goal:\s+Simulate live trading without real money\.", "## Slice 11 — Paper Trading Engine`n`nStatus: Complete.`n`nGoal:`n`nSimulate live trading without real money using a safe paper account, fake balances, simulated fills, rejected orders, blocked orders, and P/L reporting."
    Set-Content -Path $RoadmapPath -Value $roadmap -Encoding UTF8
}

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 11 Paper Trading Engine

Decision:

Added a safe paper-trading engine.

Key points:

- Simulation only.
- No live trading.
- No Kraken private API.
- No real balances.
- Supports paper cash, positions, fills, rejected orders, blocked orders, and reports.
- Supports converting PAPER_TRADE scorecards into simulated paper trades.
'@
}

# ============================ .gitignore update ============================

$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
if (Test-Path $GitIgnorePath) {
    $gitignore = Get-Content $GitIgnorePath -Raw
} else {
    $gitignore = ""
}

if ($gitignore -notmatch "(?m)^\.paper-trading/$") {
    Add-Content -Path $GitIgnorePath -Encoding UTF8 -Value @"

# Local paper trading outputs
.paper-trading/
"@
}

# ============================ validation ============================

Write-Host "=== SLICE 11 FILES CREATED ==="
Write-Host ""

Write-Host "`n=== RUNNING SLICE 11 VALIDATION ==="
python (Join-Path $ScriptsPath "test_paper_trading_engine.py")

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 11 script completed."
Get-ChildItem $PaperPath | Select-Object Name, Length, LastWriteTime
