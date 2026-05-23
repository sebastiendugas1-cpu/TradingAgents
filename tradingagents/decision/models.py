# ============================ Agent Decision Models ============================
"""
Structured decision models for the TradingAgents crypto / multi-asset project.

This module is intentionally safe:
- It does not place orders.
- It does not call Kraken private APIs.
- It does not perform live trading.
- It only represents structured analysis and recommendations.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any


class AgentRole(str, Enum):
    """Supported analysis agent roles."""

    MARKET_STRUCTURE = "market_structure"
    TECHNICAL_ANALYSIS = "technical_analysis"
    NEWS_SENTIMENT = "news_sentiment"
    RISK_MANAGER = "risk_manager"
    STRATEGY_CRITIC = "strategy_critic"
    FINAL_DECISION = "final_decision"


class SignalDirection(str, Enum):
    """Directional view produced by an agent."""

    LONG = "long"
    SHORT = "short"
    NEUTRAL = "neutral"


class DecisionStatus(str, Enum):
    """Safe decision statuses.

    There is intentionally no LIVE_TRADE status in this layer.
    """

    WATCH = "watch"
    PAPER_TRADE = "paper_trade"
    MANUAL_REVIEW = "manual_review"
    BLOCKED = "blocked"


@dataclass(frozen=True)
class AgentOpinion:
    """Structured opinion from a specialized analysis agent."""

    agent_role: AgentRole
    asset: str
    direction: SignalDirection
    confidence: int
    rationale: str
    concerns: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        _validate_score("confidence", self.confidence)
        if not self.asset.strip():
            raise ValueError("AgentOpinion.asset cannot be blank.")
        if not self.rationale.strip():
            raise ValueError("AgentOpinion.rationale cannot be blank.")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class RiskAssessment:
    """Structured risk assessment for a candidate decision."""

    asset: str
    risk_score: int
    max_position_size_pct: float
    blocked: bool
    reasons: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        _validate_score("risk_score", self.risk_score)
        if self.max_position_size_pct < 0 or self.max_position_size_pct > 100:
            raise ValueError("max_position_size_pct must be between 0 and 100.")
        if not self.asset.strip():
            raise ValueError("RiskAssessment.asset cannot be blank.")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class TradeRecommendation:
    """Final safe recommendation produced by the decision layer.

    This is not an order object. It is a recommendation only.
    """

    asset: str
    status: DecisionStatus
    direction: SignalDirection
    confidence: int
    risk_score: int
    summary: str
    reasons: list[str] = field(default_factory=list)
    agent_opinions: list[AgentOpinion] = field(default_factory=list)
    risk_assessment: RiskAssessment | None = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        _validate_score("confidence", self.confidence)
        _validate_score("risk_score", self.risk_score)
        if not self.asset.strip():
            raise ValueError("TradeRecommendation.asset cannot be blank.")
        if not self.summary.strip():
            raise ValueError("TradeRecommendation.summary cannot be blank.")

    @property
    def is_actionable(self) -> bool:
        """True for simulated or manual-review workflows, never direct live execution."""

        return self.status in {DecisionStatus.PAPER_TRADE, DecisionStatus.MANUAL_REVIEW}

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        return data


def _validate_score(name: str, value: int) -> None:
    if not isinstance(value, int):
        raise TypeError(f"{name} must be an integer.")
    if value < 0 or value > 100:
        raise ValueError(f"{name} must be between 0 and 100.")
