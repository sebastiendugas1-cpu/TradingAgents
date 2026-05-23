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
