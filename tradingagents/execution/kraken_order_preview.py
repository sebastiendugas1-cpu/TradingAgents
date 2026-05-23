# ============================ Kraken Order Preview / Dry-Run Model ============================
"""
Safe Kraken-style order preview model.

This module builds a dry-run-only order payload from an approved trade proposal
that passed the risk gate. It never sends anything to Kraken.

Safety guarantees:
- No AddOrder call.
- No CancelOrder call.
- No private trading endpoint call.
- No API key or secret handling.
- No live trading language in generated dictionaries.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from enum import Enum
from typing import Any


class KrakenOrderPreviewError(ValueError):
    """Raised when a dry-run order preview cannot be created safely."""


class OrderPreviewStatus(str, Enum):
    """Safe order-preview statuses."""

    DRY_RUN_ONLY = "dry_run_only"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class KrakenOrderPreview:
    """Dry-run-only Kraken-style order preview.

    This object is not an execution object. It is not an order request. It is a
    safe local preview of what a future order payload could look like after
    separate live-trading permissions and manual execution safeguards exist.
    """

    proposal_id: str
    asset: str
    kraken_pair: str
    side: str
    order_type: str
    volume: float
    price: float | None
    estimated_notional: float
    status: OrderPreviewStatus
    dry_run_only: bool
    risk_decision: str
    reason: str
    payload: dict[str, str] = field(default_factory=dict)
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    def __post_init__(self) -> None:
        if not self.proposal_id.strip():
            raise KrakenOrderPreviewError("proposal_id cannot be blank.")
        if not self.asset.strip():
            raise KrakenOrderPreviewError("asset cannot be blank.")
        if not self.kraken_pair.strip():
            raise KrakenOrderPreviewError("kraken_pair cannot be blank.")
        if self.side not in {"buy", "sell"}:
            raise KrakenOrderPreviewError("side must be buy or sell.")
        if self.order_type not in {"market", "limit"}:
            raise KrakenOrderPreviewError("order_type must be market or limit.")
        if self.volume <= 0:
            raise KrakenOrderPreviewError("volume must be greater than zero.")
        if self.order_type == "limit" and (self.price is None or self.price <= 0):
            raise KrakenOrderPreviewError("limit previews require a positive price.")
        if self.estimated_notional <= 0:
            raise KrakenOrderPreviewError("estimated_notional must be greater than zero.")
        if not self.dry_run_only:
            raise KrakenOrderPreviewError("KrakenOrderPreview must always be dry_run_only.")

        forbidden = str(asdict(self)).lower()
        for unsafe_word in (
            "api_key",
            "api-secret",
            "api_secret",
            "withdraw",
            "funding",
            "addorder",
            "cancelorder",
            "live trading",
        ):
            if unsafe_word in forbidden:
                raise KrakenOrderPreviewError(f"Unsafe word found in order preview: {unsafe_word}")

    @property
    def is_blocked(self) -> bool:
        return self.status == OrderPreviewStatus.BLOCKED

    @property
    def is_previewable(self) -> bool:
        return self.status == OrderPreviewStatus.DRY_RUN_ONLY and self.dry_run_only

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["status"] = self.status.value
        return data


def create_kraken_order_preview(
    *,
    proposal: Any,
    risk_gate_result: Any,
    kraken_pair: str | None = None,
) -> KrakenOrderPreview:
    """Create a safe dry-run-only Kraken order preview.

    Args:
        proposal: Trade proposal-like object. This function intentionally uses
            duck typing so it can work with the Slice 13B proposal model without
            creating circular dependencies.
        risk_gate_result: Risk gate result-like object from Slice 13D.
        kraken_pair: Optional explicit Kraken pair name. If not provided, the
            asset is converted from BTC/USD to BTCUSD style.

    Returns:
        KrakenOrderPreview marked as DRY_RUN_ONLY when safe, otherwise BLOCKED.
    """

    proposal_id = _first_attr(proposal, "proposal_id", "id", default="")
    asset = _first_attr(proposal, "asset", "symbol", default="")
    side = _enum_value(_first_attr(proposal, "side", "order_side", default=""))
    order_type = _enum_value(_first_attr(proposal, "order_type", "type", default=""))
    approval_status = _enum_value(_first_attr(proposal, "approval_status", "status", default=""))
    volume = _float_first_attr(proposal, "volume", "quantity", "amount")
    price = _optional_float_first_attr(proposal, "price", "limit_price", "entry_price")
    estimated_notional = _optional_float_first_attr(
        proposal,
        "estimated_notional",
        "estimated_value",
        "estimated_cost",
        "notional_value",
    )

    if estimated_notional is None:
        estimated_notional = volume * price if price is not None else 0.0

    risk_decision = _enum_value(_first_attr(risk_gate_result, "decision", "status", default="unknown"))
    risk_passed = bool(_first_attr(risk_gate_result, "passed", "is_passed", default=False))
    risk_reason = _build_risk_reason(risk_gate_result)

    if not proposal_id:
        raise KrakenOrderPreviewError("proposal must include a proposal_id or id.")
    if not asset:
        raise KrakenOrderPreviewError("proposal must include an asset or symbol.")
    if side not in {"buy", "sell"}:
        raise KrakenOrderPreviewError("proposal side must be buy or sell.")
    if order_type not in {"market", "limit"}:
        raise KrakenOrderPreviewError("proposal order type must be market or limit.")
    if volume <= 0:
        raise KrakenOrderPreviewError("proposal volume must be greater than zero.")
    if order_type == "limit" and (price is None or price <= 0):
        raise KrakenOrderPreviewError("limit proposal requires a positive price.")

    pair = kraken_pair or _default_kraken_pair(asset)

    if approval_status != "approved":
        return _blocked_preview(
            proposal_id=proposal_id,
            asset=asset,
            kraken_pair=pair,
            side=side,
            order_type=order_type,
            volume=volume,
            price=price,
            estimated_notional=estimated_notional,
            risk_decision=risk_decision,
            reason="Proposal is not manually approved.",
        )

    if not risk_passed or risk_decision != "approved_for_dry_run":
        return _blocked_preview(
            proposal_id=proposal_id,
            asset=asset,
            kraken_pair=pair,
            side=side,
            order_type=order_type,
            volume=volume,
            price=price,
            estimated_notional=estimated_notional,
            risk_decision=risk_decision,
            reason=risk_reason or "Risk gate did not approve this proposal for dry run.",
        )

    payload = {
        "pair": pair,
        "type": side,
        "ordertype": order_type,
        "volume": _format_decimal(volume),
        "validate": "true",
        "dry_run_only": "true",
    }

    if order_type == "limit" and price is not None:
        payload["price"] = _format_decimal(price)

    return KrakenOrderPreview(
        proposal_id=proposal_id,
        asset=asset,
        kraken_pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        price=price,
        estimated_notional=estimated_notional,
        status=OrderPreviewStatus.DRY_RUN_ONLY,
        dry_run_only=True,
        risk_decision=risk_decision,
        reason="Approved proposal converted to Kraken-style dry-run preview only.",
        payload=payload,
    )


def _blocked_preview(
    *,
    proposal_id: str,
    asset: str,
    kraken_pair: str,
    side: str,
    order_type: str,
    volume: float,
    price: float | None,
    estimated_notional: float,
    risk_decision: str,
    reason: str,
) -> KrakenOrderPreview:
    return KrakenOrderPreview(
        proposal_id=proposal_id,
        asset=asset,
        kraken_pair=kraken_pair,
        side=side,
        order_type=order_type,
        volume=volume,
        price=price,
        estimated_notional=max(estimated_notional, 0.00000001),
        status=OrderPreviewStatus.BLOCKED,
        dry_run_only=True,
        risk_decision=risk_decision,
        reason=reason,
        payload={},
    )


def _enum_value(value: Any) -> str:
    raw = getattr(value, "value", value)
    return str(raw).strip().lower()


def _first_attr(obj: Any, *names: str, default: Any = None) -> Any:
    for name in names:
        if hasattr(obj, name):
            return getattr(obj, name)
    if isinstance(obj, dict):
        for name in names:
            if name in obj:
                return obj[name]
    return default


def _float_first_attr(obj: Any, *names: str) -> float:
    value = _first_attr(obj, *names, default=None)
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise KrakenOrderPreviewError(f"Expected numeric value for one of {names}. Got: {value!r}") from exc


def _optional_float_first_attr(obj: Any, *names: str) -> float | None:
    value = _first_attr(obj, *names, default=None)
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise KrakenOrderPreviewError(f"Expected numeric value for one of {names}. Got: {value!r}") from exc


def _default_kraken_pair(asset: str) -> str:
    pair = asset.strip().upper().replace("/", "")
    if not pair:
        raise KrakenOrderPreviewError("Cannot derive Kraken pair from blank asset.")
    return pair


def _format_decimal(value: float) -> str:
    text = f"{value:.12f}".rstrip("0").rstrip(".")
    return text or "0"


def _build_risk_reason(risk_gate_result: Any) -> str:
    reasons = _first_attr(risk_gate_result, "reasons", "violations", default=None)
    if reasons is None:
        return ""
    if isinstance(reasons, str):
        return reasons
    try:
        return "; ".join(str(item) for item in reasons)
    except TypeError:
        return str(reasons)
