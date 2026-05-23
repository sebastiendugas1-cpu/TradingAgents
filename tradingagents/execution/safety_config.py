"""
Live execution safety configuration.

Slice 14A purpose:
- Define a global safety configuration for any future live execution layer.
- Keep live trading disabled by default.
- Keep the kill switch enabled by default.
- Reject unsafe or ambiguous execution settings.
- Provide a safe-to-log report that never exposes secrets.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call Kraken private trading endpoints.
This module does NOT require trading, funding, or withdrawal permissions.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Mapping


DEFAULT_LIVE_TRADING_ENABLED = False
DEFAULT_KILL_SWITCH = True
DEFAULT_MAX_LIVE_TRADE_VALUE = Decimal("0")

LIVE_TRADING_CONFIRMATION_PHRASE = "I_UNDERSTAND_LIVE_TRADING_RISK"

ENV_LIVE_TRADING_ENABLED = "LIVE_TRADING_ENABLED"
ENV_KILL_SWITCH = "KILL_SWITCH"
ENV_MAX_LIVE_TRADE_VALUE = "MAX_LIVE_TRADE_VALUE"
ENV_LIVE_TRADING_CONFIRMATION = "LIVE_TRADING_CONFIRMATION"


DANGEROUS_PERMISSION_TERMS = (
    "withdraw",
    "withdrawal",
    "funding",
    "fund",
    "deposit",
    "transfer",
)

DANGEROUS_EXECUTION_TERMS = (
    "addorder",
    "cancelorder",
    "place order",
    "submit order",
    "execute order",
    "live order",
    "market buy",
    "market sell",
    "limit buy",
    "limit sell",
    "withdraw",
    "withdrawal",
    "funding",
    "deposit",
    "transfer",
)


class SafetyConfigError(ValueError):
    """Raised when the live execution safety configuration is unsafe."""


@dataclass(frozen=True)
class LiveExecutionSafetyConfig:
    """
    Safety configuration for future live execution.

    Defaults are intentionally restrictive:
    - live trading disabled
    - kill switch enabled
    - max live trade value set to zero
    """

    live_trading_enabled: bool = DEFAULT_LIVE_TRADING_ENABLED
    kill_switch: bool = DEFAULT_KILL_SWITCH
    max_live_trade_value: Decimal = DEFAULT_MAX_LIVE_TRADE_VALUE
    explicit_confirmation: str = ""

    @classmethod
    def default(cls) -> "LiveExecutionSafetyConfig":
        """Return the safest possible default configuration."""
        return cls()

    @classmethod
    def from_env(
        cls,
        env: Mapping[str, str] | None = None,
    ) -> "LiveExecutionSafetyConfig":
        """
        Build config from environment variables.

        Missing values fall back to safe defaults.
        No secrets are read or printed here.
        """

        source = os.environ if env is None else env

        live_trading_enabled = parse_bool(
            source.get(ENV_LIVE_TRADING_ENABLED),
            default=DEFAULT_LIVE_TRADING_ENABLED,
            name=ENV_LIVE_TRADING_ENABLED,
        )

        kill_switch = parse_bool(
            source.get(ENV_KILL_SWITCH),
            default=DEFAULT_KILL_SWITCH,
            name=ENV_KILL_SWITCH,
        )

        max_live_trade_value = parse_non_negative_decimal(
            source.get(ENV_MAX_LIVE_TRADE_VALUE),
            default=DEFAULT_MAX_LIVE_TRADE_VALUE,
            name=ENV_MAX_LIVE_TRADE_VALUE,
        )

        explicit_confirmation = source.get(ENV_LIVE_TRADING_CONFIRMATION, "").strip()

        return cls(
            live_trading_enabled=live_trading_enabled,
            kill_switch=kill_switch,
            max_live_trade_value=max_live_trade_value,
            explicit_confirmation=explicit_confirmation,
        )

    def validate_config_only(self) -> None:
        """
        Validate the configuration itself.

        This does not authorize live trading.
        It only rejects malformed or impossible safety settings.
        """

        if self.max_live_trade_value < Decimal("0"):
            raise SafetyConfigError("MAX_LIVE_TRADE_VALUE cannot be negative.")

        if self.live_trading_enabled and self.max_live_trade_value <= Decimal("0"):
            raise SafetyConfigError(
                "LIVE_TRADING_ENABLED cannot be true while MAX_LIVE_TRADE_VALUE is zero."
            )

        if self.explicit_confirmation:
            validate_no_dangerous_permission_terms(self.explicit_confirmation)

    def assert_live_execution_allowed(self, executable_action: str) -> None:
        """
        Gate future live execution.

        This method is intentionally strict. In Slice 14A, all default settings
        block live execution.

        Future execution code must call this before any live action.
        """

        action_text = (executable_action or "").strip()

        if not action_text:
            raise SafetyConfigError("Executable action is missing.")

        validate_no_dangerous_executable_terms(action_text)

        if self.kill_switch:
            raise SafetyConfigError("Live execution blocked: KILL_SWITCH is true.")

        if not self.live_trading_enabled:
            raise SafetyConfigError(
                "Live execution blocked: LIVE_TRADING_ENABLED is false."
            )

        if self.max_live_trade_value <= Decimal("0"):
            raise SafetyConfigError(
                "Live execution blocked: MAX_LIVE_TRADE_VALUE must be greater than zero."
            )

        if self.explicit_confirmation != LIVE_TRADING_CONFIRMATION_PHRASE:
            raise SafetyConfigError(
                "Live execution blocked: explicit confirmation phrase is missing or invalid."
            )

    def safe_report(self) -> dict[str, str | bool]:
        """
        Return a safe-to-log report.

        This report intentionally excludes secrets and does not include raw env values.
        """

        return {
            "live_trading_enabled": self.live_trading_enabled,
            "kill_switch": self.kill_switch,
            "max_live_trade_value": str(self.max_live_trade_value),
            "explicit_confirmation_present": bool(self.explicit_confirmation),
            "live_execution_allowed_by_default": False,
            "secrets_included": False,
        }


def parse_bool(value: str | None, *, default: bool, name: str) -> bool:
    """Parse a strict boolean environment value."""

    if value is None or value.strip() == "":
        return default

    normalized = value.strip().lower()

    if normalized in {"true", "1", "yes", "y", "on"}:
        return True

    if normalized in {"false", "0", "no", "n", "off"}:
        return False

    raise SafetyConfigError(
        f"{name} must be a strict boolean value: true/false, 1/0, yes/no, on/off."
    )


def parse_non_negative_decimal(
    value: str | None,
    *,
    default: Decimal,
    name: str,
) -> Decimal:
    """Parse a non-negative decimal environment value."""

    if value is None or value.strip() == "":
        return default

    try:
        parsed = Decimal(value.strip())
    except InvalidOperation as exc:
        raise SafetyConfigError(f"{name} must be a valid decimal number.") from exc

    if parsed < Decimal("0"):
        raise SafetyConfigError(f"{name} cannot be negative.")

    return parsed


def validate_no_dangerous_permission_terms(text: str) -> None:
    """Reject dangerous permission words in confirmation/config text."""

    normalized = text.lower()

    for term in DANGEROUS_PERMISSION_TERMS:
        if term in normalized:
            raise SafetyConfigError(
                f"Dangerous permission term rejected in safety config: {term}"
            )


def validate_no_dangerous_executable_terms(text: str) -> None:
    """
    Reject execution-language terms in action descriptions.

    Slice 14A does not permit order placement, cancellation, funding, or withdrawal
    language in executable actions.
    """

    normalized = text.lower()

    for term in DANGEROUS_EXECUTION_TERMS:
        if term in normalized:
            raise SafetyConfigError(
                f"Dangerous executable action term rejected: {term}"
            )
