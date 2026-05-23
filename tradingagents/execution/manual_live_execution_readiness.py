"""
Manual live execution readiness report.

Slice 14D purpose:
- Combine the existing safety layers into one safe-to-log readiness report.
- Report whether future manual live execution is blocked or theoretically ready.
- Keep default behavior blocked.
- Avoid printing secrets.
- Avoid calling Kraken execution endpoints.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT call funding, transfer, or account-moving endpoints.
This module does NOT require trading permissions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping

from tradingagents.execution.kraken_live_execution_client import (
    KrakenLiveExecutionClient,
)
from tradingagents.execution.live_execution_preflight import (
    LiveExecutionPermissionPreflight,
    LiveExecutionPreflightReport,
)
from tradingagents.execution.safety_config import (
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


class ManualLiveExecutionReadinessError(ValueError):
    """Raised when readiness data is unsafe or malformed."""


@dataclass(frozen=True)
class ReadinessComponentStatus:
    """Safe status for one readiness component."""

    name: str
    status: str
    blocked: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)

    def safe_report(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "blocked": self.blocked,
            "reasons": list(self.reasons),
        }


@dataclass(frozen=True)
class ManualLiveExecutionReadinessReport:
    """Safe-to-log combined readiness report."""

    live_execution_blocked: bool
    theoretically_ready: bool
    components: tuple[ReadinessComponentStatus, ...]
    secrets_included: bool = False
    execution_endpoint_called: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "live_execution_blocked": self.live_execution_blocked,
            "theoretically_ready": self.theoretically_ready,
            "components": [component.safe_report() for component in self.components],
            "secrets_included": self.secrets_included,
            "execution_endpoint_called": self.execution_endpoint_called,
        }


def build_manual_live_execution_readiness_report(
    *,
    config: LiveExecutionSafetyConfig | None = None,
    env: Mapping[str, str] | None = None,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
) -> ManualLiveExecutionReadinessReport:
    """
    Build a safe readiness report for future manual live execution.

    Defaults are intentionally blocked:
    - safety config defaults to kill switch on and live trading disabled
    - risk gate readiness defaults to false
    - manual approval readiness defaults to false

    This function does not call any Kraken endpoint.
    """

    safety_config = config if config is not None else LiveExecutionSafetyConfig.from_env(env)

    preflight = LiveExecutionPermissionPreflight(config=safety_config, env=env)
    preflight_result = preflight.run()

    client = KrakenLiveExecutionClient(safety_config=safety_config)

    components = (
        _component_from_safety_config(safety_config),
        _component_from_preflight(preflight_result),
        _component_from_client(client),
        _component_from_boolean(
            name="risk_gate",
            ready=risk_gate_ready,
            blocked_reason="Risk gate has not been marked ready for live execution.",
        ),
        _component_from_boolean(
            name="manual_approval",
            ready=manual_approval_ready,
            blocked_reason="Manual approval workflow has not been marked ready for live execution.",
        ),
    )

    live_execution_blocked = any(component.blocked for component in components)
    theoretically_ready = not live_execution_blocked

    report = ManualLiveExecutionReadinessReport(
        live_execution_blocked=live_execution_blocked,
        theoretically_ready=theoretically_ready,
        components=components,
        secrets_included=False,
        execution_endpoint_called=False,
    )

    validate_readiness_report_is_safe(report)

    return report


def assert_manual_live_execution_ready(
    *,
    config: LiveExecutionSafetyConfig | None = None,
    env: Mapping[str, str] | None = None,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
) -> ManualLiveExecutionReadinessReport:
    """
    Build readiness report and raise if live execution remains blocked.

    In default project state, this must raise safely.
    """

    report = build_manual_live_execution_readiness_report(
        config=config,
        env=env,
        risk_gate_ready=risk_gate_ready,
        manual_approval_ready=manual_approval_ready,
    )

    if report.live_execution_blocked:
        reasons = []
        for component in report.components:
            reasons.extend(component.reasons)

        joined = "; ".join(reasons) if reasons else "Readiness report is blocked."
        raise ManualLiveExecutionReadinessError(
            f"Manual live execution readiness failed: {joined}"
        )

    return report


def _component_from_safety_config(
    config: LiveExecutionSafetyConfig,
) -> ReadinessComponentStatus:
    reasons: list[str] = []

    try:
        config.validate_config_only()
    except SafetyConfigError as exc:
        reasons.append(str(exc))

    if config.kill_switch:
        reasons.append("KILL_SWITCH is true.")

    if not config.live_trading_enabled:
        reasons.append("LIVE_TRADING_ENABLED is false.")

    if config.max_live_trade_value <= 0:
        reasons.append("MAX_LIVE_TRADE_VALUE is zero or negative.")

    if not config.explicit_confirmation:
        reasons.append("Explicit live trading confirmation is missing.")

    return ReadinessComponentStatus(
        name="safety_config",
        status="blocked" if reasons else "ready",
        blocked=bool(reasons),
        reasons=tuple(reasons),
    )


def _component_from_preflight(
    result: LiveExecutionPreflightReport,
) -> ReadinessComponentStatus:
    reasons = list(result.blocked_reasons)

    if result.dangerous_environment_terms_detected:
        detected_terms = ", ".join(result.dangerous_environment_terms_detected)
        normalized_reason = (
            "Dangerous environment/configuration term detected: "
            f"{detected_terms}"
        )

        reasons = [
            reason
            for reason in reasons
            if not reason.startswith("Dangerous environment terms detected:")
        ]
        reasons.insert(0, normalized_reason)

    return ReadinessComponentStatus(
        name="live_execution_preflight",
        status="ready" if result.passed else "blocked",
        blocked=not result.passed,
        reasons=tuple(reasons),
    )

def _component_from_client(
    client: KrakenLiveExecutionClient,
) -> ReadinessComponentStatus:
    report = client.safe_report()

    reasons: list[str] = []

    if report.get("live_execution_client_skeleton") is not True:
        reasons.append("Live execution client skeleton marker is missing.")

    if report.get("private_client_present") is not False:
        reasons.append("Private execution client is present before live execution is enabled.")

    if report.get("secrets_included") is not False:
        reasons.append("Client report included secrets.")

    return ReadinessComponentStatus(
        name="kraken_live_execution_client",
        status="blocked_by_design" if not reasons else "unsafe",
        blocked=True,
        reasons=tuple(reasons or ("Client is disabled by design in Slice 14D.",)),
    )


def _component_from_boolean(
    *,
    name: str,
    ready: bool,
    blocked_reason: str,
) -> ReadinessComponentStatus:
    return ReadinessComponentStatus(
        name=name,
        status="ready" if ready else "blocked",
        blocked=not ready,
        reasons=tuple() if ready else (blocked_reason,),
    )


def validate_readiness_report_is_safe(
    report: ManualLiveExecutionReadinessReport,
) -> None:
    """Validate that a readiness report is safe to log."""

    report_text = str(report.safe_report()).lower()

    forbidden_terms = (
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "token",
        "private key",
        "secret=",
    )

    for term in forbidden_terms:
        if term in report_text:
            raise ManualLiveExecutionReadinessError(
                f"Readiness report contains forbidden secret-related term: {term}"
            )

    if report.secrets_included:
        raise ManualLiveExecutionReadinessError("Readiness report includes secrets.")

    if report.execution_endpoint_called:
        raise ManualLiveExecutionReadinessError(
            "Readiness report says an execution endpoint was called."
        )







