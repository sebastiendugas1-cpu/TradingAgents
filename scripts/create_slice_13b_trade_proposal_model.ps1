# ============================ Slice 13B - Trade Proposal Model ============================
# Purpose:
# Creates a safe manual-confirmation trade proposal model.
# This slice does NOT place orders, cancel orders, or call Kraken trading endpoints.

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$PackagePath = Join-Path $ProjectRoot "tradingagents\manual_confirmation"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $PackagePath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null
New-Item -ItemType Directory -Force -Path $DocsPath | Out-Null

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-TextFile (Join-Path $PackagePath "models.py") @'
# ============================ Manual Confirmation Trade Proposal Models ============================
"""
Safe data models for manual-confirmation trade proposals.

This module does not place orders, cancel orders, or call Kraken trading endpoints.
It only represents proposed trades and approval/rejection records.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any
from uuid import uuid4

from tradingagents.assets import normalize_asset_symbol
from tradingagents.decision import DecisionStatus, SignalDirection


class TradeProposalError(ValueError):
    """Raised when a trade proposal is invalid."""


class OrderSide(str, Enum):
    """Allowed order sides for a proposal."""

    BUY = "buy"
    SELL = "sell"


class OrderType(str, Enum):
    """Allowed proposed order types."""

    MARKET = "market"
    LIMIT = "limit"


class TradeApprovalStatus(str, Enum):
    """Manual approval states. None of these executes a real order."""

    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXPIRED = "expired"


@dataclass(frozen=True)
class TradeProposalRiskSummary:
    """Risk details that must be shown before manual approval."""

    risk_score: int
    max_trade_value: float
    estimated_trade_value: float
    max_daily_loss: float | None = None
    stop_loss_price: float | None = None
    take_profit_price: float | None = None
    notes: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        _validate_score("risk_score", self.risk_score)
        _validate_non_negative("max_trade_value", self.max_trade_value)
        _validate_non_negative("estimated_trade_value", self.estimated_trade_value)

        if self.estimated_trade_value > self.max_trade_value:
            raise TradeProposalError(
                "estimated_trade_value cannot exceed max_trade_value for a proposal."
            )

        if self.max_daily_loss is not None:
            _validate_non_negative("max_daily_loss", self.max_daily_loss)

        if self.stop_loss_price is not None:
            _validate_positive("stop_loss_price", self.stop_loss_price)

        if self.take_profit_price is not None:
            _validate_positive("take_profit_price", self.take_profit_price)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class TradeProposal:
    """A proposed trade that requires manual approval before any execution layer.

    This is NOT an order object.
    This is NOT sent to Kraken.
    """

    proposal_id: str
    asset: str
    side: OrderSide
    order_type: OrderType
    quantity: float
    estimated_price: float
    estimated_value: float
    decision_status: DecisionStatus
    direction: SignalDirection
    confidence_score: int
    risk_summary: TradeProposalRiskSummary
    status: TradeApprovalStatus = TradeApprovalStatus.PENDING
    created_at_utc: str = field(default_factory=lambda: _utc_now_iso())
    expires_at_utc: str | None = None
    reason_summary: str = ""
    source: str = "manual_confirmation_model"
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.proposal_id.strip():
            raise TradeProposalError("proposal_id cannot be blank.")

        normalized_asset = normalize_asset_symbol(self.asset).normalized
        object.__setattr__(self, "asset", normalized_asset)

        _validate_positive("quantity", self.quantity)
        _validate_positive("estimated_price", self.estimated_price)
        _validate_positive("estimated_value", self.estimated_value)
        _validate_score("confidence_score", self.confidence_score)

        if self.status != TradeApprovalStatus.PENDING:
            raise TradeProposalError("New trade proposals must start as pending.")

        if self.decision_status == DecisionStatus.BLOCKED:
            raise TradeProposalError("Blocked decisions cannot become trade proposals.")

        if self.decision_status == DecisionStatus.WATCH:
            raise TradeProposalError("Watch-only decisions cannot become trade proposals.")

        if self.decision_status not in {DecisionStatus.PAPER_TRADE, DecisionStatus.MANUAL_REVIEW}:
            raise TradeProposalError(
                "Only paper_trade or manual_review decisions can become manual-confirmation proposals."
            )

        if self.direction == SignalDirection.NEUTRAL:
            raise TradeProposalError("Neutral decisions cannot become trade proposals.")

        if self.risk_summary.estimated_trade_value != self.estimated_value:
            raise TradeProposalError(
                "risk_summary.estimated_trade_value must match proposal estimated_value."
            )

    @property
    def requires_manual_approval(self) -> bool:
        return self.status == TradeApprovalStatus.PENDING

    @property
    def is_approved(self) -> bool:
        return self.status == TradeApprovalStatus.APPROVED

    @property
    def is_rejected(self) -> bool:
        return self.status == TradeApprovalStatus.REJECTED

    def approve(self, approved_by: str, note: str = "") -> "ManualApprovalRecord":
        return ManualApprovalRecord(
            proposal_id=self.proposal_id,
            previous_status=self.status,
            new_status=TradeApprovalStatus.APPROVED,
            actor=approved_by,
            note=note,
        )

    def reject(self, rejected_by: str, note: str = "") -> "ManualApprovalRecord":
        return ManualApprovalRecord(
            proposal_id=self.proposal_id,
            previous_status=self.status,
            new_status=TradeApprovalStatus.REJECTED,
            actor=rejected_by,
            note=note,
        )

    def expire(self, actor: str = "system", note: str = "proposal expired") -> "ManualApprovalRecord":
        return ManualApprovalRecord(
            proposal_id=self.proposal_id,
            previous_status=self.status,
            new_status=TradeApprovalStatus.EXPIRED,
            actor=actor,
            note=note,
        )

    def with_status(self, status: TradeApprovalStatus) -> "TradeProposal":
        return TradeProposal(
            proposal_id=self.proposal_id,
            asset=self.asset,
            side=self.side,
            order_type=self.order_type,
            quantity=self.quantity,
            estimated_price=self.estimated_price,
            estimated_value=self.estimated_value,
            decision_status=self.decision_status,
            direction=self.direction,
            confidence_score=self.confidence_score,
            risk_summary=self.risk_summary,
            status=TradeApprovalStatus.PENDING,
            created_at_utc=self.created_at_utc,
            expires_at_utc=self.expires_at_utc,
            reason_summary=self.reason_summary,
            source=self.source,
            metadata=self.metadata,
        )._replace_status(status)

    def _replace_status(self, status: TradeApprovalStatus) -> "TradeProposal":
        object.__setattr__(self, "status", status)
        return self

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["side"] = self.side.value
        data["order_type"] = self.order_type.value
        data["decision_status"] = self.decision_status.value
        data["direction"] = self.direction.value
        data["status"] = self.status.value
        return data


@dataclass(frozen=True)
class ManualApprovalRecord:
    """Audit record for manual approval state changes."""

    proposal_id: str
    previous_status: TradeApprovalStatus
    new_status: TradeApprovalStatus
    actor: str
    note: str = ""
    timestamp_utc: str = field(default_factory=lambda: _utc_now_iso())

    def __post_init__(self) -> None:
        if not self.proposal_id.strip():
            raise TradeProposalError("approval proposal_id cannot be blank.")
        if not self.actor.strip():
            raise TradeProposalError("approval actor cannot be blank.")
        if self.previous_status != TradeApprovalStatus.PENDING:
            raise TradeProposalError("Only pending proposals can be changed by manual approval records.")
        if self.new_status not in {
            TradeApprovalStatus.APPROVED,
            TradeApprovalStatus.REJECTED,
            TradeApprovalStatus.EXPIRED,
        }:
            raise TradeProposalError("Manual approval record must approve, reject, or expire a proposal.")

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["previous_status"] = self.previous_status.value
        data["new_status"] = self.new_status.value
        return data


def build_trade_proposal_from_scorecard(
    *,
    scorecard: Any,
    side: OrderSide | str,
    order_type: OrderType | str,
    quantity: float,
    estimated_price: float,
    max_trade_value: float,
    stop_loss_price: float | None = None,
    take_profit_price: float | None = None,
    reason_summary: str | None = None,
    proposal_id: str | None = None,
) -> TradeProposal:
    """Build a trade proposal from a strategy scorecard-like object.

    The scorecard is expected to expose:
    - asset
    - action
    - direction
    - confidence_score
    - risk_score
    - reason_summary or summary
    """

    estimated_value = round(float(quantity) * float(estimated_price), 10)

    action = getattr(scorecard, "action")
    direction = getattr(scorecard, "direction")
    confidence_score = int(getattr(scorecard, "confidence_score"))
    risk_score = int(getattr(scorecard, "risk_score"))

    summary = reason_summary
    if summary is None:
        summary = getattr(scorecard, "reason_summary", None) or getattr(scorecard, "summary", "")

    risk_summary = TradeProposalRiskSummary(
        risk_score=risk_score,
        max_trade_value=float(max_trade_value),
        estimated_trade_value=estimated_value,
        stop_loss_price=stop_loss_price,
        take_profit_price=take_profit_price,
        notes=("Manual confirmation required before any execution.",),
    )

    return TradeProposal(
        proposal_id=proposal_id or f"proposal-{uuid4().hex}",
        asset=str(getattr(scorecard, "asset")),
        side=OrderSide(side),
        order_type=OrderType(order_type),
        quantity=float(quantity),
        estimated_price=float(estimated_price),
        estimated_value=estimated_value,
        decision_status=DecisionStatus(action),
        direction=SignalDirection(direction),
        confidence_score=confidence_score,
        risk_summary=risk_summary,
        reason_summary=summary,
    )


def _validate_score(field_name: str, value: int) -> None:
    if not isinstance(value, int):
        raise TradeProposalError(f"{field_name} must be an integer.")
    if value < 0 or value > 100:
        raise TradeProposalError(f"{field_name} must be between 0 and 100.")


def _validate_positive(field_name: str, value: float) -> None:
    if value <= 0:
        raise TradeProposalError(f"{field_name} must be greater than zero.")


def _validate_non_negative(field_name: str, value: float) -> None:
    if value < 0:
        raise TradeProposalError(f"{field_name} cannot be negative.")


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
'@

Write-TextFile (Join-Path $PackagePath "storage.py") @'
# ============================ Manual Confirmation Proposal Storage ============================
"""
Local JSONL storage for trade proposals and manual approval records.

This writes local audit files only. It does not execute trades.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tradingagents.manual_confirmation.models import ManualApprovalRecord, TradeProposal


class TradeProposalLog:
    """Append-only local JSONL log for trade proposals and manual approval records."""

    def __init__(self, log_dir: str | Path = ".trade-proposals") -> None:
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.proposals_path = self.log_dir / "proposals.jsonl"
        self.approvals_path = self.log_dir / "approvals.jsonl"

    def append_proposal(self, proposal: TradeProposal) -> Path:
        self._append_json(self.proposals_path, proposal.to_dict())
        return self.proposals_path

    def append_approval(self, record: ManualApprovalRecord) -> Path:
        self._append_json(self.approvals_path, record.to_dict())
        return self.approvals_path

    def read_proposals(self) -> list[dict[str, Any]]:
        return self._read_jsonl(self.proposals_path)

    def read_approvals(self) -> list[dict[str, Any]]:
        return self._read_jsonl(self.approvals_path)

    @staticmethod
    def _append_json(path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, sort_keys=True) + "\n")

    @staticmethod
    def _read_jsonl(path: Path) -> list[dict[str, Any]]:
        if not path.exists():
            return []
        records: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                cleaned = line.strip()
                if cleaned:
                    records.append(json.loads(cleaned))
        return records
'@

Write-TextFile (Join-Path $PackagePath "__init__.py") @'
# ============================ Manual Confirmation Package Exports ============================

from tradingagents.manual_confirmation.models import (
    ManualApprovalRecord,
    OrderSide,
    OrderType,
    TradeApprovalStatus,
    TradeProposal,
    TradeProposalError,
    TradeProposalRiskSummary,
    build_trade_proposal_from_scorecard,
)
from tradingagents.manual_confirmation.storage import TradeProposalLog

__all__ = [
    "ManualApprovalRecord",
    "OrderSide",
    "OrderType",
    "TradeApprovalStatus",
    "TradeProposal",
    "TradeProposalError",
    "TradeProposalRiskSummary",
    "TradeProposalLog",
    "build_trade_proposal_from_scorecard",
]
'@

Write-TextFile (Join-Path $ScriptsPath "test_trade_proposal_model.py") @'
# ============================ Slice 13B Validation - Trade Proposal Model ============================

from __future__ import annotations

import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import DecisionStatus, SignalDirection  # noqa: E402
from tradingagents.manual_confirmation import (  # noqa: E402
    OrderSide,
    OrderType,
    TradeApprovalStatus,
    TradeProposalError,
    TradeProposalLog,
    TradeProposalRiskSummary,
    build_trade_proposal_from_scorecard,
)


class FakeScorecard:
    asset = "btc-usd"
    action = DecisionStatus.PAPER_TRADE
    direction = SignalDirection.LONG
    confidence_score = 82
    risk_score = 35
    reason_summary = "Synthetic scorecard approved for paper/manual workflow."


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 13B trade proposal model validation...")

    proposal = build_trade_proposal_from_scorecard(
        scorecard=FakeScorecard(),
        side=OrderSide.BUY,
        order_type=OrderType.LIMIT,
        quantity=0.001,
        estimated_price=75000.0,
        max_trade_value=100.0,
        stop_loss_price=72000.0,
        take_profit_price=79000.0,
        proposal_id="proposal-test-001",
    )

    assert_equal(proposal.asset, "BTC/USD", "asset normalized")
    assert_equal(proposal.side, OrderSide.BUY, "proposal side")
    assert_equal(proposal.order_type, OrderType.LIMIT, "proposal order type")
    assert_equal(proposal.status, TradeApprovalStatus.PENDING, "new proposal starts pending")
    assert_equal(proposal.decision_status, DecisionStatus.PAPER_TRADE, "proposal decision status")
    assert_true(proposal.requires_manual_approval, "proposal requires manual approval")
    assert_equal(proposal.estimated_value, 75.0, "estimated value calculated")
    assert_equal(proposal.risk_summary.risk_score, 35, "risk score attached")

    approval = proposal.approve(approved_by="operator", note="test approval only")
    assert_equal(approval.previous_status, TradeApprovalStatus.PENDING, "approval previous status")
    assert_equal(approval.new_status, TradeApprovalStatus.APPROVED, "approval new status")

    rejection = proposal.reject(rejected_by="operator", note="test rejection only")
    assert_equal(rejection.new_status, TradeApprovalStatus.REJECTED, "rejection status")

    log_dir = PROJECT_ROOT / ".trade-proposals" / "slice-13b-test"
    if log_dir.exists():
        shutil.rmtree(log_dir)

    log = TradeProposalLog(log_dir)
    log.append_proposal(proposal)
    log.append_approval(approval)

    assert_equal(len(log.read_proposals()), 1, "proposal log count")
    assert_equal(len(log.read_approvals()), 1, "approval log count")

    proposal_dict = proposal.to_dict()
    assert_equal(proposal_dict["status"], "pending", "proposal dict status")
    assert_true("live_trade" not in str(proposal_dict).lower(), "proposal does not mention live trading")
    assert_true("api" not in str(proposal_dict).lower(), "proposal does not mention API keys")

    try:
        TradeProposalRiskSummary(risk_score=20, max_trade_value=10.0, estimated_trade_value=11.0)
        raise AssertionError("Oversized proposal risk summary should fail.")
    except TradeProposalError:
        print("[OK] oversized risk summary rejected")

    blocked_scorecard = FakeScorecard()
    blocked_scorecard.action = DecisionStatus.BLOCKED

    try:
        build_trade_proposal_from_scorecard(
            scorecard=blocked_scorecard,
            side=OrderSide.BUY,
            order_type=OrderType.MARKET,
            quantity=0.001,
            estimated_price=75000.0,
            max_trade_value=100.0,
        )
        raise AssertionError("Blocked scorecard should not create proposal.")
    except TradeProposalError:
        print("[OK] blocked scorecard rejected")

    print("Trade proposal model validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# Update .gitignore for local proposal logs.
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
if (Test-Path $GitIgnorePath) {
    $GitIgnoreText = Get-Content $GitIgnorePath -Raw
} else {
    $GitIgnoreText = ""
}
if ($GitIgnoreText -notmatch "(?m)^\.trade-proposals/$") {
    Add-Content -Path $GitIgnorePath -Value "`n# Local manual-confirmation proposal logs`n.trade-proposals/"
}

# Update docs.
$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $RoadmapText = Get-Content $RoadmapPath -Raw
    if ($RoadmapText -notmatch "Slice 13B — Trade Proposal Model") {
        Add-Content -Path $RoadmapPath -Value @'

## Slice 13B — Trade Proposal Model

Goal:

Create safe trade proposal models for manual-confirmation workflows.

Rules:

- No order placement.
- No Kraken trading endpoint calls.
- No order cancellation.
- Every proposal starts pending.
- Blocked or watch-only decisions cannot become proposals.
- Every proposal must include risk summary and manual approval state.

Commit message:

```text
Add trade proposal model
```
'@
    }
}

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    $DecisionLogText = Get-Content $DecisionLogPath -Raw
    if ($DecisionLogText -notmatch "Slice 13B") {
        Add-Content -Path $DecisionLogPath -Value @'

## 2026-05-22 — Slice 13B Trade Proposal Model

Decision:

Add a manual-confirmation trade proposal model that can represent proposed trades, risk summaries, and approval records without executing anything.

Rules:

- A trade proposal is not an order.
- A trade proposal cannot call Kraken.
- A trade proposal cannot execute live trades.
- Blocked or watch-only decisions cannot become proposals.
- Manual approval records are audit records only.
'@
    }
}

Write-Host "=== SLICE 13B FILES CREATED ==="
Get-ChildItem $PackagePath | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 13B VALIDATION ==="
python .\scripts\test_trade_proposal_model.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 13B script completed."
