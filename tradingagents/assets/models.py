# ============================ Asset Models ============================
"""
Shared asset models for the TradingAgents crypto / multi-asset project.

This module is intentionally small and dependency-free. It gives the rest of the
project one common way to represent assets before we connect external data
sources such as Kraken or TradingView.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class AssetType(StrEnum):
    """Supported high-level asset categories."""

    CRYPTO = "crypto"
    TRADITIONAL = "traditional"
    UNKNOWN = "unknown"


@dataclass(frozen=True, slots=True)
class AssetIdentifier:
    """Normalized representation of a tradable or analyzable asset.

    Attributes:
        original: The exact user-provided symbol.
        normalized: The internal canonical symbol, such as BTC/USD or AAPL.
        asset_type: High-level asset category.
        base: Base asset for crypto pairs or ticker for traditional assets.
        quote: Quote currency for crypto pairs, or None for traditional assets.
        venue_prefix: Optional TradingView-style prefix such as NASDAQ or KRAKEN.
    """

    original: str
    normalized: str
    asset_type: AssetType
    base: str
    quote: str | None = None
    venue_prefix: str | None = None

    @property
    def is_crypto(self) -> bool:
        return self.asset_type == AssetType.CRYPTO

    @property
    def is_traditional(self) -> bool:
        return self.asset_type == AssetType.TRADITIONAL

    def as_dict(self) -> dict[str, str | None]:
        """Return a JSON-friendly dictionary."""

        return {
            "original": self.original,
            "normalized": self.normalized,
            "asset_type": self.asset_type.value,
            "base": self.base,
            "quote": self.quote,
            "venue_prefix": self.venue_prefix,
        }
