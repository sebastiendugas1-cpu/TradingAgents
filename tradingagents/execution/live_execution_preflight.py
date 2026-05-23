"""
Live execution permission preflight.

Slice 14C purpose:
- Add a safe preflight validator before any future live execution can be considered.
- Report safety configuration state without printing secrets.
- Reject dangerous environment/configuration terms related to funding or withdrawals.
- Confirm that live execution remains blocked unless every safety condition is explicit.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call Kraken private order-submission endpoints.
This module does NOT call Kraken private order-cancellation endpoints.
This module does NOT call funding, deposit, transfer, or withdrawal endpoints.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from decimal import Decimal
from typing import Mapping

from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    DANGEROUS_PERMISSION_TERMS,
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


class LiveExecutionPreflightError(SafetyConfigError):
    """Raised when live execution preflight fails safely."""


DANGEROUS_ENV_VAR_NAMES = (
    "WITHDRAW",
    "WITHDRAWAL",
    "FUNDING",
    "FUND",
    "DEPOSIT",
    "TRANSFER",
)

SECRET_ENV_NAME_FRAGMENTS = (
    "SECRET",
    "KEY",
    "TOKEN",
    "PASSWORD",
    "PASS",
)


@dataclass(frozen=True)
class LiveExecutionPreflightReport:
    """Safe-to-log live execution preflight report."""

    passed: bool
    live_trading_enabled: bool
    kill_switch: bool
    max_live_trade_value: str
    explicit_confirmation_present: bool
    explicit_confirmation_valid: bool
    blocked_reasons: tuple[str, ...]
    dangerous_environment_terms_detected: tuple[str, ...]
    secrets_included: bool = False
    execution_endpoints_called: bool = False

    def as_dict(self) -> dict[str, object]:
        """Return a safe-to-log dictionary representation."""

        return {
            "passed": self.passed,
            "live_trading_enabled": self.live_trading_enabled,
            "kill_switch": self.kill_switch,
            "max_live_trade_value": self.max_live_trade_value,
            "explicit_confirmation_present": self.explicit_confirmation_present,
            "explicit_confirmation_valid": self.explicit_confirmation_valid,
            "blocked_reasons": list(self.blocked_reasons),
            "dangerous_environment_terms_detected": list(
                self.dangerous_environment_terms_detected
            ),
            "secrets_included": self.secrets_included,
            "execution_endpoints_called": self.execution_endpoints_called,
        }


class LiveExecutionPermissionPreflight:
    """
    Preflight validator for future live execution.

    This class only checks safety state. It does not perform any trading action.
    """

    def __init__(
        self,
        config: LiveExecutionSafetyConfig | None = None,
        env: Mapping[str, str] | None = None,
    ) -> None:
        self._env = os.environ if env is None else env
        self._config = config if config is not None else LiveExecutionSafetyConfig.from_env(self._env)

    @property
    def config(self) -> LiveExecutionSafetyConfig:
        return self._config

    def run(self) -> LiveExecutionPreflightReport:
        """
        Run a safe preflight check and return a safe-to-log report.

        The report never includes raw secret values.
        """

        blocked_reasons: list[str] = []
        dangerous_terms = detect_dangerous_environment_terms(self._env)

        try:
            self._config.validate_config_only()
        except SafetyConfigError as exc:
            blocked_reasons.append(str(exc))

        if dangerous_terms:
            blocked_reasons.append(
                "Dangerous environment terms detected: " + ", ".join(dangerous_terms)
            )

        if self._config.kill_switch:
            blocked_reasons.append("KILL_SWITCH is true.")

        if not self._config.live_trading_enabled:
            blocked_reasons.append("LIVE_TRADING_ENABLED is false.")

        if self._config.max_live_trade_value <= Decimal("0"):
            blocked_reasons.append("MAX_LIVE_TRADE_VALUE is zero or negative.")

        confirmation_valid = (
            self._config.explicit_confirmation == LIVE_TRADING_CONFIRMATION_PHRASE
        )
        if not confirmation_valid:
            blocked_reasons.append("Explicit live trading confirmation is missing or invalid.")

        passed = len(blocked_reasons) == 0

        return LiveExecutionPreflightReport(
            passed=passed,
            live_trading_enabled=self._config.live_trading_enabled,
            kill_switch=self._config.kill_switch,
            max_live_trade_value=str(self._config.max_live_trade_value),
            explicit_confirmation_present=bool(self._config.explicit_confirmation),
            explicit_confirmation_valid=confirmation_valid,
            blocked_reasons=tuple(blocked_reasons),
            dangerous_environment_terms_detected=tuple(dangerous_terms),
            secrets_included=False,
            execution_endpoints_called=False,
        )

    def assert_preflight_passed(self) -> LiveExecutionPreflightReport:
        """Raise safely unless preflight passes."""

        report = self.run()
        if not report.passed:
            reasons = "; ".join(report.blocked_reasons)
            raise LiveExecutionPreflightError(f"Live execution preflight failed: {reasons}")
        return report


def detect_dangerous_environment_terms(env: Mapping[str, str]) -> tuple[str, ...]:
    """
    Detect dangerous funding/withdrawal-related environment terms.

    Secret values are never returned. Only safe variable names or redacted labels are reported.
    """

    detected: list[str] = []

    for raw_name, raw_value in env.items():
        name = str(raw_name).upper()
        value = str(raw_value).upper()

        name_has_secret_fragment = any(
            secret_fragment in name for secret_fragment in SECRET_ENV_NAME_FRAGMENTS
        )

        for term in DANGEROUS_ENV_VAR_NAMES:
            if term in name:
                detected.append(name)
                break

        if name_has_secret_fragment:
            continue

        for term in DANGEROUS_PERMISSION_TERMS:
            if term.upper() in value:
                detected.append(f"{name}=<redacted-dangerous-term>")
                break

    return tuple(sorted(set(detected)))


def build_live_execution_preflight_report(
    env: Mapping[str, str] | None = None,
) -> LiveExecutionPreflightReport:
    """Build and run a live execution permission preflight report."""

    return LiveExecutionPermissionPreflight(env=env).run()

