$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ==="
}

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

function Add-SectionIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$Section
    )

    if (-not (Test-Path $Path)) {
        throw "Required documentation file missing: $Path"
    }

    $existing = Get-Content -Path $Path -Raw

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`r`n$Section" -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    }
    else {
        Write-Host "[SKIPPED] $Path already contains marker: $Marker"
    }
}

$ProjectRoot = (Get-Location).Path

Write-Section "SLICE 14A LIVE EXECUTION SAFETY CONFIG"

if (-not (Test-Path ".\tradingagents")) {
    throw "This script must be run from the TradingAgents project root."
}

if (-not (Test-Path ".\docs")) {
    throw "docs folder not found. Run this script from D:\Trading\TradingAgents."
}

if (-not (Test-Path ".\scripts")) {
    throw "scripts folder not found. Run this script from D:\Trading\TradingAgents."
}

New-Item -ItemType Directory -Force -Path ".\tradingagents\execution" | Out-Null

$ExecutionInitPath = ".\tradingagents\execution\__init__.py"

if (-not (Test-Path $ExecutionInitPath)) {
    $ExecutionInitContent = @'
"""
Execution safety package.

Slice 14A introduces safety configuration only.
No live trading execution is implemented here.
"""
'@
    Write-TextFile -Path $ExecutionInitPath -Content $ExecutionInitContent
    Write-Host "[CREATED] $ExecutionInitPath"
}
else {
    Write-Host "[SKIPPED] $ExecutionInitPath already exists; preserving current package exports."
}

$SafetyConfigContent = @'
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
'@

Write-TextFile -Path ".\tradingagents\execution\safety_config.py" -Content $SafetyConfigContent
Write-Host "[WRITTEN] .\tradingagents\execution\safety_config.py"

$ValidationScriptContent = @'
"""
Validation script for Slice 14A.

This script confirms that live execution safety config is restrictive by default.

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

from decimal import Decimal

from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


def expect_safety_error(label: str, func) -> None:
    try:
        func()
    except SafetyConfigError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected SafetyConfigError")


def test_default_config_is_safe() -> None:
    config = LiveExecutionSafetyConfig.default()

    assert config.live_trading_enabled is False
    assert config.kill_switch is True
    assert config.max_live_trade_value == Decimal("0")
    assert config.explicit_confirmation == ""

    config.validate_config_only()

    expect_safety_error(
        "default config blocks future live execution",
        lambda: config.assert_live_execution_allowed("safe dry run preview only"),
    )


def test_env_defaults_are_safe_when_missing() -> None:
    config = LiveExecutionSafetyConfig.from_env({})

    assert config.live_trading_enabled is False
    assert config.kill_switch is True
    assert config.max_live_trade_value == Decimal("0")
    assert config.explicit_confirmation == ""

    config.validate_config_only()


def test_unsafe_enabled_with_zero_value_is_rejected() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "0",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )

    expect_safety_error(
        "live enabled with zero max value is rejected",
        config.validate_config_only,
    )


def test_missing_confirmation_blocks_live_execution() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
        }
    )

    config.validate_config_only()

    expect_safety_error(
        "missing explicit confirmation blocks live execution",
        lambda: config.assert_live_execution_allowed("safe dry run preview only"),
    )


def test_kill_switch_blocks_even_with_other_live_settings() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "true",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )

    config.validate_config_only()

    expect_safety_error(
        "kill switch blocks live execution",
        lambda: config.assert_live_execution_allowed("safe dry run preview only"),
    )


def test_dangerous_permission_terms_are_rejected() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_CONFIRMATION: "please enable withdrawal permission",
        }
    )

    expect_safety_error(
        "dangerous permission terms are rejected",
        config.validate_config_only,
    )


def test_dangerous_executable_action_terms_are_rejected() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )

    config.validate_config_only()

    dangerous_actions = [
        "AddOrder",
        "CancelOrder",
        "place order",
        "submit order",
        "execute order",
        "market buy",
        "market sell",
        "withdraw",
        "funding",
        "deposit",
        "transfer",
    ]

    for action in dangerous_actions:
        expect_safety_error(
            f"dangerous executable action term rejected: {action}",
            lambda action=action: config.assert_live_execution_allowed(action),
        )


def test_invalid_env_values_are_rejected() -> None:
    expect_safety_error(
        "invalid boolean rejected",
        lambda: LiveExecutionSafetyConfig.from_env(
            {
                ENV_LIVE_TRADING_ENABLED: "maybe",
            }
        ),
    )

    expect_safety_error(
        "negative max live trade value rejected",
        lambda: LiveExecutionSafetyConfig.from_env(
            {
                ENV_MAX_LIVE_TRADE_VALUE: "-1",
            }
        ),
    )

    expect_safety_error(
        "non-numeric max live trade value rejected",
        lambda: LiveExecutionSafetyConfig.from_env(
            {
                ENV_MAX_LIVE_TRADE_VALUE: "abc",
            }
        ),
    )


def test_safe_report_excludes_secrets() -> None:
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "false",
            ENV_KILL_SWITCH: "true",
            ENV_MAX_LIVE_TRADE_VALUE: "0",
        }
    )

    report = config.safe_report()
    report_text = str(report).lower()

    assert report["live_trading_enabled"] is False
    assert report["kill_switch"] is True
    assert report["max_live_trade_value"] == "0"
    assert report["explicit_confirmation_present"] is False
    assert report["live_execution_allowed_by_default"] is False
    assert report["secrets_included"] is False

    forbidden_report_terms = [
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "token",
    ]

    for term in forbidden_report_terms:
        assert term not in report_text

    print("[OK] config report is safe to log")


def main() -> None:
    print("Slice 14A validation: Live Trading Kill Switch and Execution Safety Config")
    print("=" * 80)

    test_default_config_is_safe()
    test_env_defaults_are_safe_when_missing()
    test_unsafe_enabled_with_zero_value_is_rejected()
    test_missing_confirmation_blocks_live_execution()
    test_kill_switch_blocks_even_with_other_live_settings()
    test_dangerous_permission_terms_are_rejected()
    test_dangerous_executable_action_terms_are_rejected()
    test_invalid_env_values_are_rejected()
    test_safe_report_excludes_secrets()

    print("=" * 80)
    print("[PASS] Slice 14A safety config validation passed.")
    print("[PASS] No live order placement or cancellation code was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Write-TextFile -Path ".\scripts\test_live_execution_safety_config.py" -Content $ValidationScriptContent
Write-Host "[WRITTEN] .\scripts\test_live_execution_safety_config.py"

$RoadmapSection = @'
## Slice 14A — Live Trading Kill Switch and Execution Safety Config

Status: Implemented pending validation.

Goal:
Create a global execution safety configuration that blocks all future live execution unless explicitly enabled.

Default safety state:
- `LIVE_TRADING_ENABLED=false`
- `KILL_SWITCH=true`
- `MAX_LIVE_TRADE_VALUE=0`

Scope:
- Configuration only.
- Validation only.
- No Kraken AddOrder call.
- No Kraken CancelOrder call.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/safety_config.py`
- `scripts/test_live_execution_safety_config.py`

Validation:
- Confirms live trading is disabled by default.
- Confirms kill switch is enabled by default.
- Confirms max live trade value is zero by default.
- Rejects unsafe settings.
- Rejects dangerous permission terms.
- Rejects dangerous executable action terms.
- Confirms safe reports do not expose secrets.
'@

$ExecutionControlsSection = @'
## Slice 14A — Global Live Execution Safety Config

A global live execution safety config has been introduced.

Default behavior is intentionally restrictive:
- Live trading is disabled.
- Kill switch is enabled.
- Maximum live trade value is zero.

The config is implemented in:

`tradingagents/execution/safety_config.py`

Future live execution code must call the safety gate before any executable action is allowed.

Current restrictions:
- No live trading code exists in this slice.
- No Kraken AddOrder call exists in this slice.
- No Kraken CancelOrder call exists in this slice.
- No withdrawal code exists in this slice.
- No funding code exists in this slice.
- No trading permission is required for this slice.

The safety config provides a safe report that excludes secrets and raw credential values.
'@

$DecisionLogSection = @'
## Slice 14A Decision — Live Execution Must Be Blocked by Default

Decision:
Before adding any future live execution layer, the project must first include a global safety config.

Reason:
The project already supports read-only Kraken access, paper trading, backtesting, TradingView webhook triggers, manual approval, risk gates, and dry-run previews. The next safety requirement is a hard global execution gate before any live trading function can exist.

Chosen defaults:
- `LIVE_TRADING_ENABLED=false`
- `KILL_SWITCH=true`
- `MAX_LIVE_TRADE_VALUE=0`

Result:
Future live execution must be explicitly enabled, must pass a kill-switch check, must have a positive max trade value, and must include explicit confirmation.

This slice intentionally does not introduce Kraken AddOrder, Kraken CancelOrder, funding, withdrawal, or automatic live order functionality.
'@

Add-SectionIfMissing -Path ".\docs\03_ROADMAP.md" -Marker "Slice 14A — Live Trading Kill Switch and Execution Safety Config" -Section $RoadmapSection
Add-SectionIfMissing -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 14A — Global Live Execution Safety Config" -Section $ExecutionControlsSection
Add-SectionIfMissing -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 14A Decision — Live Execution Must Be Blocked by Default" -Section $DecisionLogSection

Write-Section "CURRENT BRANCH"
git branch --show-current

Write-Section "GIT STATUS"
git status --short

Write-Section "SLICE 14A FILES"
Get-Item `
    ".\tradingagents\execution\safety_config.py", `
    ".\scripts\test_live_execution_safety_config.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 14A script completed."
