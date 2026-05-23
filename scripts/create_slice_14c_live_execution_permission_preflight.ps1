$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 14C LIVE EXECUTION PERMISSION PREFLIGHT ==="

$ExecutionDir = ".\tradingagents\execution"
$ScriptsDir = ".\scripts"
$DocsDir = ".\docs"

New-Item -ItemType Directory -Force $ExecutionDir | Out-Null
New-Item -ItemType Directory -Force $ScriptsDir | Out-Null
New-Item -ItemType Directory -Force $DocsDir | Out-Null

$initPath = Join-Path $ExecutionDir "__init__.py"
if (-not (Test-Path $initPath)) {
@'
"""
Execution safety package.

This package contains disabled-by-default execution safety components.
No live trading execution is enabled by default.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] $initPath"
} else {
    Write-Host "[SKIPPED] $initPath already exists; preserving current package exports."
}

$preflightPath = Join-Path $ExecutionDir "live_execution_preflight.py"
@'
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
This module does NOT call Kraken AddOrder.
This module does NOT call Kraken CancelOrder.
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
'@ | Set-Content -Path $preflightPath -Encoding UTF8
Write-Host "[WRITTEN] $preflightPath"

$testPath = Join-Path $ScriptsDir "test_live_execution_permission_preflight.py"
@'
"""
Validation script for Slice 14C.

This script confirms that live execution permission preflight remains safe.

It does not:
- place orders
- cancel orders
- call Kraken AddOrder
- call Kraken CancelOrder
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

import inspect
from decimal import Decimal

from tradingagents.execution.live_execution_preflight import (
    LiveExecutionPermissionPreflight,
    LiveExecutionPreflightError,
    build_live_execution_preflight_report,
    detect_dangerous_environment_terms,
)
from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
)
import tradingagents.execution.live_execution_preflight as preflight_module


FORBIDDEN_SECRET_VALUES = (
    "super-secret-key",
    "super-secret-token",
    "super-secret-password",
)

FORBIDDEN_ENDPOINT_TERMS = (
    "AddOrder",
    "CancelOrder",
    "/0/private/AddOrder",
    "/0/private/CancelOrder",
    "Withdraw",
    "/0/private/Withdraw",
)


def expect_preflight_error(label: str, func) -> None:
    try:
        func()
    except LiveExecutionPreflightError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected LiveExecutionPreflightError")


def test_default_preflight_blocks_live_execution() -> None:
    report = build_live_execution_preflight_report({})

    assert report.passed is False
    assert report.live_trading_enabled is False
    assert report.kill_switch is True
    assert report.max_live_trade_value == "0"
    assert report.explicit_confirmation_present is False
    assert report.explicit_confirmation_valid is False
    assert report.secrets_included is False
    assert report.execution_endpoints_called is False
    assert any("KILL_SWITCH" in reason for reason in report.blocked_reasons)
    assert any("LIVE_TRADING_ENABLED" in reason for reason in report.blocked_reasons)

    print("[OK] default preflight blocks live execution")


def test_preflight_assert_raises_by_default() -> None:
    preflight = LiveExecutionPermissionPreflight(env={})

    expect_preflight_error(
        "default preflight assert blocks live execution",
        preflight.assert_preflight_passed,
    )


def test_permissive_config_can_only_pass_preflight_without_calling_endpoints() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "true",
        ENV_KILL_SWITCH: "false",
        ENV_MAX_LIVE_TRADE_VALUE: "10",
        ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is True
    assert report.live_trading_enabled is True
    assert report.kill_switch is False
    assert report.max_live_trade_value == "10"
    assert report.explicit_confirmation_present is True
    assert report.explicit_confirmation_valid is True
    assert report.blocked_reasons == tuple()
    assert report.execution_endpoints_called is False

    print("[OK] permissive config only passes preflight; no endpoint is called")


def test_kill_switch_blocks_even_with_other_settings_enabled() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "true",
        ENV_KILL_SWITCH: "true",
        ENV_MAX_LIVE_TRADE_VALUE: "10",
        ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is False
    assert any("KILL_SWITCH" in reason for reason in report.blocked_reasons)

    print("[OK] kill switch blocks preflight")


def test_zero_trade_value_blocks_preflight() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "false",
        ENV_KILL_SWITCH: "true",
        ENV_MAX_LIVE_TRADE_VALUE: "0",
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is False
    assert any("MAX_LIVE_TRADE_VALUE" in reason for reason in report.blocked_reasons)

    print("[OK] zero max live trade value blocks preflight")


def test_missing_confirmation_blocks_preflight() -> None:
    env = {
        ENV_LIVE_TRADING_ENABLED: "true",
        ENV_KILL_SWITCH: "false",
        ENV_MAX_LIVE_TRADE_VALUE: "10",
    }

    report = build_live_execution_preflight_report(env)

    assert report.passed is False
    assert any("confirmation" in reason.lower() for reason in report.blocked_reasons)

    print("[OK] missing explicit confirmation blocks preflight")


def test_dangerous_environment_terms_are_detected_without_secret_leakage() -> None:
    env = {
        "KRAKEN_API_KEY": "super-secret-key",
        "KRAKEN_API_SECRET": "super-secret-token",
        "ENABLE_WITHDRAWALS": "false",
        "SOME_SAFE_SETTING": "please do not withdraw anything",
        "NORMAL_SETTING": "hello",
    }

    detected = detect_dangerous_environment_terms(env)
    detected_text = str(detected)

    assert "ENABLE_WITHDRAWALS" in detected
    assert "SOME_SAFE_SETTING=<redacted-dangerous-term>" in detected

    for secret in FORBIDDEN_SECRET_VALUES:
        assert secret not in detected_text

    report = build_live_execution_preflight_report(env)
    report_text = str(report.as_dict())

    assert report.passed is False
    assert report.secrets_included is False
    assert "ENABLE_WITHDRAWALS" in report.dangerous_environment_terms_detected

    for secret in FORBIDDEN_SECRET_VALUES:
        assert secret not in report_text

    print("[OK] dangerous environment terms detected without leaking secrets")


def test_report_is_safe_to_log() -> None:
    env = {
        "KRAKEN_API_KEY": "super-secret-key",
        "KRAKEN_API_SECRET": "super-secret-token",
        "ACCESS_TOKEN": "super-secret-token",
        ENV_LIVE_TRADING_ENABLED: "false",
        ENV_KILL_SWITCH: "true",
        ENV_MAX_LIVE_TRADE_VALUE: "0",
    }

    report = build_live_execution_preflight_report(env)
    report_dict = report.as_dict()
    report_text = str(report_dict)

    assert report_dict["secrets_included"] is False
    assert report_dict["execution_endpoints_called"] is False

    for secret in FORBIDDEN_SECRET_VALUES:
        assert secret not in report_text

    print("[OK] preflight report is safe to log")


def test_config_can_be_supplied_directly() -> None:
    config = LiveExecutionSafetyConfig(
        live_trading_enabled=False,
        kill_switch=True,
        max_live_trade_value=Decimal("0"),
        explicit_confirmation="",
    )

    report = LiveExecutionPermissionPreflight(config=config, env={}).run()

    assert report.passed is False
    assert report.live_trading_enabled is False
    assert report.kill_switch is True
    assert report.max_live_trade_value == "0"

    print("[OK] preflight accepts directly supplied config")


def test_preflight_source_contains_no_kraken_execution_endpoint_names() -> None:
    source = inspect.getsource(preflight_module)

    for term in FORBIDDEN_ENDPOINT_TERMS:
        assert term not in source

    print("[OK] preflight source contains no Kraken execution endpoint names")


def main() -> None:
    print("Slice 14C validation: Live Execution Permission Preflight")
    print("=" * 80)

    test_default_preflight_blocks_live_execution()
    test_preflight_assert_raises_by_default()
    test_permissive_config_can_only_pass_preflight_without_calling_endpoints()
    test_kill_switch_blocks_even_with_other_settings_enabled()
    test_zero_trade_value_blocks_preflight()
    test_missing_confirmation_blocks_preflight()
    test_dangerous_environment_terms_are_detected_without_secret_leakage()
    test_report_is_safe_to_log()
    test_config_can_be_supplied_directly()
    test_preflight_source_contains_no_kraken_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 14C live execution permission preflight validation passed.")
    print("[PASS] Preflight remains safe to log and does not expose secrets.")
    print("[PASS] No Kraken execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@ | Set-Content -Path $testPath -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

$roadmapPath = Join-Path $DocsDir "03_ROADMAP.md"
$roadmapBlock = @'

## Slice 14C — Live Execution Permission Preflight

Status: Implemented pending validation.

Goal:
Add a preflight validator that checks whether the environment and safety configuration are acceptable before any future live execution path can be considered.

Scope:
- Safety preflight only.
- Safe-to-log reporting only.
- No Kraken AddOrder call.
- No Kraken CancelOrder call.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/live_execution_preflight.py`
- `scripts/test_live_execution_permission_preflight.py`
- `scripts/create_slice_14c_live_execution_permission_preflight.ps1`

Validation confirms:
- Default preflight blocks live execution.
- Kill switch blocks preflight.
- Zero max live trade value blocks preflight.
- Missing explicit confirmation blocks preflight.
- Dangerous funding/withdrawal environment terms are detected.
- Secret values are not printed in the report.
- No Kraken execution endpoint call is introduced.
'@
if (Test-Path $roadmapPath) {
    $roadmapContent = Get-Content -Path $roadmapPath -Raw
    if ($roadmapContent -notlike "*Slice 14C — Live Execution Permission Preflight*") {
        Add-Content -Path $roadmapPath -Value $roadmapBlock
        Write-Host "[UPDATED] $roadmapPath"
    } else {
        Write-Host "[SKIPPED] $roadmapPath already contains Slice 14C block."
    }
}

$controlsPath = Join-Path $DocsDir "10_EXECUTION_AND_RISK_CONTROLS.md"
$controlsBlock = @'

## Slice 14C — Live Execution Permission Preflight

A live execution permission preflight layer has been introduced.

The preflight layer reports:
- Whether live trading is enabled.
- Whether the kill switch is active.
- The maximum configured live trade value.
- Whether explicit confirmation is present and valid.
- Whether dangerous funding/withdrawal environment terms were detected.

The preflight report is safe to log:
- It does not expose API keys.
- It does not expose API secrets.
- It does not expose token or password values.
- It records whether execution endpoints were called, which remains false in this slice.

Current restrictions remain unchanged:
- No Kraken AddOrder call exists in this slice.
- No Kraken CancelOrder call exists in this slice.
- No withdrawal code exists in this slice.
- No funding code exists in this slice.
- No trading permission is required for this slice.
'@
if (Test-Path $controlsPath) {
    $controlsContent = Get-Content -Path $controlsPath -Raw
    if ($controlsContent -notlike "*Slice 14C — Live Execution Permission Preflight*") {
        Add-Content -Path $controlsPath -Value $controlsBlock
        Write-Host "[UPDATED] $controlsPath"
    } else {
        Write-Host "[SKIPPED] $controlsPath already contains Slice 14C block."
    }
}

$decisionPath = Join-Path $DocsDir "11_DECISION_LOG.md"
$decisionBlock = @'

## Slice 14C Decision — Add Preflight Before Any Future Live Execution

Decision:
Before any future manually triggered live execution path can be developed, the project must include a dedicated preflight validator.

Reason:
The project now has a kill switch, disabled-by-default live execution config, and a blocked Kraken live execution client skeleton. A separate preflight layer gives the project a safe status report before any future execution path can even be considered.

Chosen behavior:
- Preflight fails by default.
- Kill switch blocks preflight.
- Disabled live trading blocks preflight.
- Zero max live trade value blocks preflight.
- Missing explicit confirmation blocks preflight.
- Dangerous funding/withdrawal environment terms are reported safely.
- Secret values are never included in the report.

This slice intentionally does not introduce Kraken AddOrder, Kraken CancelOrder, funding, withdrawal, or automatic live order functionality.
'@
if (Test-Path $decisionPath) {
    $decisionContent = Get-Content -Path $decisionPath -Raw
    if ($decisionContent -notlike "*Slice 14C Decision — Add Preflight Before Any Future Live Execution*") {
        Add-Content -Path $decisionPath -Value $decisionBlock
        Write-Host "[UPDATED] $decisionPath"
    } else {
        Write-Host "[SKIPPED] $decisionPath already contains Slice 14C block."
    }
}

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 14C FILES ==="
Get-Item $preflightPath, $testPath, $roadmapPath, $controlsPath, $decisionPath | Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 14C script completed."
