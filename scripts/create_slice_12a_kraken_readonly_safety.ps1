# ============================ Slice 12A - Kraken Read-Only Safety Plan + Config Validator ============================
# Purpose:
# Creates a safe Kraken read-only configuration validator.
#
# This slice does NOT call Kraken private APIs.
# This slice does NOT place orders.
# This slice does NOT require real Kraken keys.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_12a_kraken_readonly_safety.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$DocsPath = Join-Path $ProjectRoot "docs"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$KrakenPath = Join-Path $ProjectRoot "tradingagents\kraken"

Set-Location $ProjectRoot

New-Item -ItemType Directory -Force -Path $DocsPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null
New-Item -ItemType Directory -Force -Path $KrakenPath | Out-Null

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-TextFile (Join-Path $KrakenPath "__init__.py") @'
# ============================ Kraken Package Exports ============================

from tradingagents.kraken.config import (
    KrakenConfigError,
    KrakenReadOnlyConfig,
    load_kraken_readonly_config,
    validate_kraken_readonly_config,
)

__all__ = [
    "KrakenConfigError",
    "KrakenReadOnlyConfig",
    "load_kraken_readonly_config",
    "validate_kraken_readonly_config",
]
'@

Write-TextFile (Join-Path $KrakenPath "config.py") @'
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
'@

Write-TextFile (Join-Path $ScriptsPath "test_kraken_readonly_config.py") @'
# ============================ Slice 12A Validation - Kraken Read-Only Config ============================

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken import (  # noqa: E402
    KrakenConfigError,
    load_kraken_readonly_config,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def assert_raises(expected_error, fn, label: str) -> None:
    try:
        fn()
    except expected_error:
        print(f"[OK] {label}")
        return

    raise AssertionError(f"{label}: expected {expected_error.__name__}")


def main() -> int:
    print("Running Slice 12A Kraken read-only config validation...")

    empty_config = load_kraken_readonly_config({})
    assert_equal(empty_config.enabled, False, "empty config disabled")
    assert_equal(empty_config.has_api_key, False, "empty config has no key")
    assert_equal(empty_config.is_read_only_safe, False, "empty config is not active safe config")

    safe_env = {
        "KRAKEN_API_KEY": "fake-key-for-validation-only",
        "KRAKEN_API_SECRET": "fake-secret-for-validation-only",
        "KRAKEN_TRADING_ENABLED": "false",
        "KRAKEN_WITHDRAWALS_ENABLED": "false",
        "KRAKEN_FUNDING_ENABLED": "false",
        "KRAKEN_ALLOWED_PERMISSIONS": "balances, open_orders, trade_history",
    }

    safe_config = load_kraken_readonly_config(safe_env)
    assert_equal(safe_config.enabled, True, "safe config enabled")
    assert_equal(safe_config.has_api_key, True, "safe config has key")
    assert_equal(safe_config.has_api_secret, True, "safe config has secret")
    assert_equal(safe_config.trading_enabled, False, "trading disabled")
    assert_equal(safe_config.withdrawals_enabled, False, "withdrawals disabled")
    assert_equal(safe_config.funding_enabled, False, "funding disabled")
    assert_true(safe_config.is_read_only_safe, "safe config is read-only safe")

    safe_dict = safe_config.to_dict()
    assert_true("fake-key" not in str(safe_dict), "safe dict does not reveal key")
    assert_true("fake-secret" not in str(safe_dict), "safe dict does not reveal secret")

    assert_raises(
        KrakenConfigError,
        lambda: load_kraken_readonly_config(
            {
                **safe_env,
                "KRAKEN_TRADING_ENABLED": "true",
            }
        ),
        "trading flag rejected",
    )

    assert_raises(
        KrakenConfigError,
        lambda: load_kraken_readonly_config(
            {
                **safe_env,
                "KRAKEN_WITHDRAWALS_ENABLED": "true",
            }
        ),
        "withdrawal flag rejected",
    )

    assert_raises(
        KrakenConfigError,
        lambda: load_kraken_readonly_config(
            {
                **safe_env,
                "KRAKEN_ALLOWED_PERMISSIONS": "balances, trade, withdrawals",
            }
        ),
        "dangerous permission names rejected",
    )

    print("Kraken read-only config validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# Update Kraken plan doc with a stronger Slice 12A section.
Write-TextFile (Join-Path $DocsPath "07_KRAKEN_PLAN.md") @'
# Kraken Integration Plan

## Purpose

Kraken is the primary crypto exchange target for market data and eventual execution.

## Current Kraken Status

Current status:

```text
Public market data exists.
Private account access is not enabled.
Live trading is not enabled.
No Kraken private API calls are allowed yet.
```

## Integration Phases

### Phase 1 — Public Market Data

Status: complete.

No API key required.

Implemented features:

- Fetch supported asset pairs.
- Fetch ticker prices.
- Fetch OHLCV candles.
- Validate symbols.
- Normalize Kraken pairs into internal format.

### Phase 2A — Read-Only Safety Plan and Config Validator

Status: current slice.

No Kraken private API calls.

This phase creates:

- Read-only configuration validator.
- Permission safety checklist.
- Secret-safe status reporting.
- Hard blocking for trading, funding, and withdrawals.

### Phase 2B — Read-Only Private Access

API key required, but read-only permissions only.

Allowed:

- Read balances.
- Read open orders.
- Read trade history.

Forbidden:

- Place orders.
- Cancel orders.
- Withdraw funds.
- Funding actions.
- Margin/futures actions.

### Phase 3 — Manual-Confirmation Trading

API key may include trading permission only after previous phases are validated.

Rules:

- System proposes order.
- User confirms manually.
- Order is logged.
- Risk limits are checked before placement.

### Phase 4 — Restricted Automation

Only after paper trading and manual-confirmation trading are stable.

Required controls:

- Max trade size.
- Max daily loss.
- Max exposure.
- Kill switch.
- Cooldown rules.
- Audit logs.

## Required Kraken API Key Rules

- Never use withdrawal permission.
- Never use funding permission in this project phase.
- Never commit API keys.
- Store secrets in `.env`.
- Start read-only.
- Add trading permission only when explicitly approved in a later slice.

## `.env` Planning

Future read-only variables:

```text
KRAKEN_API_KEY=
KRAKEN_API_SECRET=
KRAKEN_TRADING_ENABLED=false
KRAKEN_WITHDRAWALS_ENABLED=false
KRAKEN_FUNDING_ENABLED=false
KRAKEN_ALLOWED_PERMISSIONS=balances,open_orders,trade_history
```

## Slice 12A Validation Rule

The config validator must reject:

- trading enabled
- withdrawals enabled
- funding enabled
- dangerous permission names
- any attempt to expose API key or secret values in output
'@

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 12A Kraken Read-Only Safety Config

Decision:

Before using real Kraken private API keys, the project will first add a read-only configuration validator.

Key points:

- Slice 12A does not call Kraken private APIs.
- Slice 12A does not require real Kraken keys.
- Trading, funding, and withdrawal flags are rejected.
- Dangerous permission names are rejected.
- Secret values must never be printed.
- Real Kraken private account access will be a later slice.
'@
}

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $RoadmapText = Get-Content $RoadmapPath -Raw
    $RoadmapText = $RoadmapText.Replace(
        "## Slice 12 — Kraken Read-Only Account Integration",
        "## Slice 12A — Kraken Read-Only Safety Plan and Config Validator"
    )
    $RoadmapText = $RoadmapText.Replace(
        "Goal:`r`n`r`nRead real account data with no trading permission.",
        "Goal:`r`n`r`nCreate a safety plan and local config validator before using real Kraken private API keys.`r`n`r`nNo private API calls yet. No trading."
    )
    Set-Content -Path $RoadmapPath -Value $RoadmapText -Encoding UTF8
}

Write-Host "=== SLICE 12A FILES CREATED ==="
Write-Host ""

Write-Host "`n=== RUNNING SLICE 12A VALIDATION ==="
python .\scripts\test_kraken_readonly_config.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 12A script completed."
Get-ChildItem $KrakenPath | Select-Object Name, Length, LastWriteTime
