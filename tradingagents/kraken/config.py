# ============================ Kraken Read-Only Config Validator ============================
"""
Safe Kraken read-only configuration validator.

This module is intentionally conservative.

It does NOT:
- call Kraken private APIs
- place orders
- cancel orders
- withdraw funds
- reveal secrets

It only validates whether the local configuration is safe enough for a future
read-only account integration slice.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
import os
from typing import Mapping


class KrakenConfigError(ValueError):
    """Raised when Kraken configuration is missing or unsafe."""


@dataclass(frozen=True)
class KrakenReadOnlyConfig:
    """Validated Kraken read-only configuration status.

    The actual API key/secret values are never exposed by this object.
    """

    enabled: bool
    has_api_key: bool
    has_api_secret: bool
    trading_enabled: bool
    withdrawals_enabled: bool
    funding_enabled: bool
    allowed_permissions: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def is_read_only_safe(self) -> bool:
        """True only when the config has keys and no unsafe permission flags."""

        return (
            self.enabled
            and self.has_api_key
            and self.has_api_secret
            and not self.trading_enabled
            and not self.withdrawals_enabled
            and not self.funding_enabled
        )

    def to_dict(self) -> dict[str, object]:
        """Return a safe dictionary with no secret values."""

        return asdict(self)


def load_kraken_readonly_config(env: Mapping[str, str] | None = None) -> KrakenReadOnlyConfig:
    """Load and validate Kraken read-only config from environment values.

    Expected variables:

    - KRAKEN_API_KEY
    - KRAKEN_API_SECRET
    - KRAKEN_TRADING_ENABLED
    - KRAKEN_WITHDRAWALS_ENABLED
    - KRAKEN_FUNDING_ENABLED
    - KRAKEN_ALLOWED_PERMISSIONS

    This does not require real keys for tests. It only checks presence and safety flags.
    """

    values = env if env is not None else os.environ

    api_key = _clean(values.get("KRAKEN_API_KEY"))
    api_secret = _clean(values.get("KRAKEN_API_SECRET"))

    trading_enabled = _is_truthy(values.get("KRAKEN_TRADING_ENABLED"))
    withdrawals_enabled = _is_truthy(values.get("KRAKEN_WITHDRAWALS_ENABLED"))
    funding_enabled = _is_truthy(values.get("KRAKEN_FUNDING_ENABLED"))

    permissions = _parse_permissions(values.get("KRAKEN_ALLOWED_PERMISSIONS", ""))

    enabled = bool(api_key or api_secret or permissions)

    warnings: list[str] = []

    if enabled and not api_key:
        warnings.append("KRAKEN_API_KEY is missing.")

    if enabled and not api_secret:
        warnings.append("KRAKEN_API_SECRET is missing.")

    if not permissions:
        warnings.append("KRAKEN_ALLOWED_PERMISSIONS is empty. Expected read-only permissions only.")

    config = KrakenReadOnlyConfig(
        enabled=enabled,
        has_api_key=bool(api_key),
        has_api_secret=bool(api_secret),
        trading_enabled=trading_enabled,
        withdrawals_enabled=withdrawals_enabled,
        funding_enabled=funding_enabled,
        allowed_permissions=permissions,
        warnings=tuple(warnings),
    )

    validate_kraken_readonly_config(config)
    return config


def validate_kraken_readonly_config(config: KrakenReadOnlyConfig) -> None:
    """Validate that Kraken config does not request unsafe permissions."""

    if config.trading_enabled:
        raise KrakenConfigError("Unsafe Kraken config: trading is enabled. Slice 12A allows read-only only.")

    if config.withdrawals_enabled:
        raise KrakenConfigError("Unsafe Kraken config: withdrawals are enabled. Withdrawal permission is never allowed.")

    if config.funding_enabled:
        raise KrakenConfigError("Unsafe Kraken config: funding is enabled. Slice 12A allows read-only only.")

    forbidden_permissions = {
        "trade",
        "trading",
        "place_order",
        "place_orders",
        "cancel_order",
        "cancel_orders",
        "withdraw",
        "withdrawal",
        "withdrawals",
        "deposit",
        "funding",
        "transfer",
        "margin",
        "futures",
    }

    matched_forbidden = sorted(set(config.allowed_permissions).intersection(forbidden_permissions))

    if matched_forbidden:
        raise KrakenConfigError(
            "Unsafe Kraken permissions detected: " + ", ".join(matched_forbidden)
        )


def _clean(value: str | None) -> str:
    if value is None:
        return ""
    return str(value).strip().strip('"').strip("'")


def _is_truthy(value: str | None) -> bool:
    normalized = _clean(value).lower()
    return normalized in {"1", "true", "yes", "y", "on", "enabled"}


def _parse_permissions(value: str | None) -> tuple[str, ...]:
    cleaned = _clean(value).lower()

    if not cleaned:
        return tuple()

    parts = [
        part.strip().replace(" ", "_")
        for chunk in cleaned.split(";")
        for part in chunk.split(",")
    ]

    return tuple(part for part in parts if part)
