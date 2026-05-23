# ============================ Risk Gate Engine ============================
"""
Safe risk-gate logic for manually approved trade proposals.

This layer does not place orders.
This layer does not call Kraken trading endpoints.
This layer does not cancel orders.
This layer does not access funding or withdrawals.

Its only job is to decide whether a proposal is safe enough to move forward to a
future dry-run/order-preview step.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


class RiskGateDecision(str, Enum):
    """Risk gate outcome."""

    APPROVED_FOR_DRY_RUN = "approved_for_dry_run"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class RiskGateViolation:
    """One reason the risk gate blocked a proposal."""

    code: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return asdict(self)


@dataclass(frozen=True)
class RiskGateConfig:
    """Hard safety settings for proposal risk checks."""

    allowed_symbols: tuple[str, ...] = ("BTC/USD", "ETH/USD", "SOL/USD")
    max_trade_value: float = 100.0
    max_risk_score: int = 70
    min_confidence_score: int = 55
    require_manual_approval: bool = True
    kill_switch_enabled: bool = False
    allowed_decision_statuses: tuple[str, ...] = ("paper_trade", "manual_review")
    max_daily_loss_placeholder: float = 25.0
    max_total_exposure_placeholder: float = 500.0

    def __post_init__(self) -> None:
        if self.max_trade_value <= 0:
            raise ValueError("max_trade_value must be greater than zero.")
        if self.max_risk_score < 0 or self.max_risk_score > 100:
            raise ValueError("max_risk_score must be between 0 and 100.")
        if self.min_confidence_score < 0 or self.min_confidence_score > 100:
            raise ValueError("min_confidence_score must be between 0 and 100.")
        if self.max_daily_loss_placeholder < 0:
            raise ValueError("max_daily_loss_placeholder cannot be negative.")
        if self.max_total_exposure_placeholder < 0:
            raise ValueError("max_total_exposure_placeholder cannot be negative.")
        if not self.allowed_symbols:
            raise ValueError("allowed_symbols cannot be empty.")

    @property
    def normalized_allowed_symbols(self) -> set[str]:
        return {symbol.strip().upper() for symbol in self.allowed_symbols if symbol.strip()}


@dataclass(frozen=True)
class RiskGateResult:
    """Safe pre-execution decision produced by the risk gate."""

    decision: RiskGateDecision
    asset: str
    estimated_trade_value: float
    risk_score: int
    confidence_score: int
    violations: tuple[RiskGateViolation, ...] = field(default_factory=tuple)
    notes: tuple[str, ...] = field(default_factory=tuple)

    @property
    def passed(self) -> bool:
        return self.decision == RiskGateDecision.APPROVED_FOR_DRY_RUN

    @property
    def blocked(self) -> bool:
        return self.decision == RiskGateDecision.BLOCKED

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["decision"] = self.decision.value
        data["violations"] = [violation.to_dict() for violation in self.violations]
        return data


class RiskGateEngine:
    """Evaluate whether a trade proposal can proceed to dry-run preview."""

    def __init__(self, config: RiskGateConfig | None = None) -> None:
        self.config = config or RiskGateConfig()

    def evaluate_proposal(self, proposal: Any) -> RiskGateResult:
        """Evaluate a trade proposal using hard safety rules.

        The proposal object is intentionally duck-typed so the gate can work with
        the Slice 13B TradeProposal model and test doubles.
        """

        asset = _normalize_asset(_read_attr(proposal, "asset", ""))
        estimated_trade_value = _read_float(proposal, "estimated_value", default=0.0)
        risk_score = _extract_risk_score(proposal)
        confidence_score = _extract_confidence_score(proposal)
        approval_status = _enum_value(_read_attr(proposal, "approval_status", ""))
        decision_status = _extract_decision_status(proposal)

        violations: list[RiskGateViolation] = []
        notes: list[str] = []

        if self.config.kill_switch_enabled:
            violations.append(
                RiskGateViolation(
                    code="kill_switch_enabled",
                    message="Risk gate kill switch is enabled. No proposal may proceed.",
                )
            )

        if not asset:
            violations.append(RiskGateViolation(code="missing_asset", message="Proposal asset is missing."))
        elif asset not in self.config.normalized_allowed_symbols:
            violations.append(
                RiskGateViolation(
                    code="symbol_not_allowed",
                    message=f"Asset {asset} is not in the configured allowed symbol list.",
                )
            )

        if self.config.require_manual_approval and approval_status != "approved":
            violations.append(
                RiskGateViolation(
                    code="manual_approval_required",
                    message="Proposal must be explicitly manually approved before dry-run preview.",
                )
            )

        if estimated_trade_value <= 0:
            violations.append(
                RiskGateViolation(
                    code="invalid_trade_value",
                    message="Estimated trade value must be greater than zero.",
                )
            )
        elif estimated_trade_value > self.config.max_trade_value:
            violations.append(
                RiskGateViolation(
                    code="trade_value_too_large",
                    message=(
                        f"Estimated trade value {estimated_trade_value:.2f} exceeds "
                        f"limit {self.config.max_trade_value:.2f}."
                    ),
                )
            )

        if risk_score > self.config.max_risk_score:
            violations.append(
                RiskGateViolation(
                    code="risk_score_too_high",
                    message=f"Risk score {risk_score} exceeds limit {self.config.max_risk_score}.",
                )
            )

        if confidence_score < self.config.min_confidence_score:
            violations.append(
                RiskGateViolation(
                    code="confidence_score_too_low",
                    message=(
                        f"Confidence score {confidence_score} is below minimum "
                        f"{self.config.min_confidence_score}."
                    ),
                )
            )

        if decision_status and decision_status not in self.config.allowed_decision_statuses:
            violations.append(
                RiskGateViolation(
                    code="decision_status_not_allowed",
                    message=f"Decision status {decision_status!r} is not allowed by the risk gate.",
                )
            )

        notes.append("Daily loss and total exposure checks are placeholders until live execution accounting exists.")
        notes.append("Passing this gate allows only future dry-run/order-preview workflow, not order placement.")

        decision = RiskGateDecision.BLOCKED if violations else RiskGateDecision.APPROVED_FOR_DRY_RUN

        return RiskGateResult(
            decision=decision,
            asset=asset,
            estimated_trade_value=round(estimated_trade_value, 8),
            risk_score=risk_score,
            confidence_score=confidence_score,
            violations=tuple(violations),
            notes=tuple(notes),
        )


def _read_attr(obj: Any, name: str, default: Any = None) -> Any:
    value = getattr(obj, name, default)
    if callable(value):
        try:
            return value()
        except TypeError:
            return default
    return value


def _read_float(obj: Any, name: str, default: float = 0.0) -> float:
    value = _read_attr(obj, name, default)
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _read_int_from_obj(obj: Any, names: tuple[str, ...], default: int) -> int:
    for name in names:
        value = _read_attr(obj, name, None)
        if value is not None:
            try:
                return int(value)
            except (TypeError, ValueError):
                continue
    return default


def _extract_risk_score(proposal: Any) -> int:
    direct = _read_int_from_obj(proposal, ("risk_score",), default=-1)
    if direct >= 0:
        return direct

    risk_summary = _read_attr(proposal, "risk_summary", None)
    if risk_summary is not None:
        value = _read_int_from_obj(risk_summary, ("risk_score",), default=-1)
        if value >= 0:
            return value

    scorecard = _read_attr(proposal, "strategy_scorecard", None) or _read_attr(proposal, "scorecard", None)
    if scorecard is not None:
        value = _read_int_from_obj(scorecard, ("risk_score",), default=-1)
        if value >= 0:
            return value

    return 50


def _extract_confidence_score(proposal: Any) -> int:
    direct = _read_int_from_obj(proposal, ("confidence_score", "confidence"), default=-1)
    if direct >= 0:
        return direct

    scorecard = _read_attr(proposal, "strategy_scorecard", None) or _read_attr(proposal, "scorecard", None)
    if scorecard is not None:
        value = _read_int_from_obj(scorecard, ("confidence_score", "confidence"), default=-1)
        if value >= 0:
            return value

    return 0


def _extract_decision_status(proposal: Any) -> str:
    scorecard = _read_attr(proposal, "strategy_scorecard", None) or _read_attr(proposal, "scorecard", None)
    if scorecard is not None:
        return _enum_value(_read_attr(scorecard, "action", None) or _read_attr(scorecard, "status", ""))
    return _enum_value(_read_attr(proposal, "decision_status", ""))


def _normalize_asset(asset: Any) -> str:
    return str(asset or "").strip().upper()


def _enum_value(value: Any) -> str:
    raw = getattr(value, "value", value)
    return str(raw or "").strip().lower()
