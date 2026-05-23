# ============================ Slice 12C-1 - Kraken Read-Only Key Setup Validator ============================
# Purpose:
# Adds a safe Kraken read-only environment validator.
#
# This slice does NOT call Kraken private APIs.
# This slice does NOT read balances.
# This slice does NOT place/cancel orders.
# This slice only checks whether local configuration is present and unsafe flags are not enabled.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_12c1_kraken_readonly_env_validator.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$KrakenPath = Join-Path $ProjectRoot "tradingagents\kraken"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $KrakenPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null
New-Item -ItemType Directory -Force -Path $DocsPath | Out-Null

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# ============================ tradingagents/kraken/env_validation.py ============================

Write-TextFile (Join-Path $KrakenPath "env_validation.py") @'
# ============================ Kraken Read-Only Environment Validation ============================
"""
Safe Kraken read-only environment validator.

This module only validates local configuration.
It does not call Kraken.
It does not read balances.
It does not read orders.
It does not place, cancel, fund, or withdraw anything.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Mapping


KRAKEN_API_KEY_ENV = "KRAKEN_API_KEY"
KRAKEN_API_SECRET_ENV = "KRAKEN_API_SECRET"

# Explicit safety flags. These are expected to be false or absent.
KRAKEN_TRADING_ENABLED_ENV = "KRAKEN_TRADING_ENABLED"
KRAKEN_WITHDRAWALS_ENABLED_ENV = "KRAKEN_WITHDRAWALS_ENABLED"
KRAKEN_FUNDING_ENABLED_ENV = "KRAKEN_FUNDING_ENABLED"

DANGEROUS_PERMISSION_WORDS = {
    "trade",
    "trading",
    "order",
    "orders",
    "cancel",
    "withdraw",
    "withdrawal",
    "funding",
    "deposit",
    "transfer",
    "margin",
    "leverage",
    "futures",
}


class KrakenReadOnlyEnvironmentError(ValueError):
    """Raised when Kraken read-only environment configuration is unsafe."""


@dataclass(frozen=True)
class KrakenReadOnlyEnvironmentReport:
    """Safe report that never exposes API key or secret values."""

    env_file: str | None
    has_api_key: bool
    has_api_secret: bool
    trading_enabled: bool
    withdrawals_enabled: bool
    funding_enabled: bool
    dangerous_permission_words_found: tuple[str, ...]
    is_ready_for_readonly_private_client: bool
    notes: tuple[str, ...]

    def to_dict(self) -> dict[str, object]:
        """Return a JSON-serializable report with no secrets."""
        return asdict(self)


def validate_kraken_readonly_environment(
    *,
    env_file: str | Path | None = None,
    environ: Mapping[str, str] | None = None,
    require_keys: bool = False,
) -> KrakenReadOnlyEnvironmentReport:
    """Validate local Kraken read-only environment settings.

    Args:
        env_file:
            Optional .env path to read. Values from environ override values from env_file.
        environ:
            Optional mapping to validate, useful for tests.
        require_keys:
            If true, raise when KRAKEN_API_KEY or KRAKEN_API_SECRET is missing.

    Returns:
        KrakenReadOnlyEnvironmentReport with presence booleans only.

    Safety:
        This function never returns the API key or secret values.
    """

    file_values = _load_env_file(Path(env_file)) if env_file else {}
    merged_values = dict(file_values)

    if environ is not None:
        merged_values.update({key: value for key, value in environ.items() if value is not None})

    api_key = _clean_value(merged_values.get(KRAKEN_API_KEY_ENV))
    api_secret = _clean_value(merged_values.get(KRAKEN_API_SECRET_ENV))

    trading_enabled = _parse_bool(merged_values.get(KRAKEN_TRADING_ENABLED_ENV))
    withdrawals_enabled = _parse_bool(merged_values.get(KRAKEN_WITHDRAWALS_ENABLED_ENV))
    funding_enabled = _parse_bool(merged_values.get(KRAKEN_FUNDING_ENABLED_ENV))

    dangerous_words = _find_dangerous_permission_words(merged_values)

    notes: list[str] = []

    if not api_key:
        notes.append("KRAKEN_API_KEY is missing.")

    if not api_secret:
        notes.append("KRAKEN_API_SECRET is missing.")

    if trading_enabled:
        notes.append("KRAKEN_TRADING_ENABLED is true. Read-only mode requires false.")

    if withdrawals_enabled:
        notes.append("KRAKEN_WITHDRAWALS_ENABLED is true. This is forbidden.")

    if funding_enabled:
        notes.append("KRAKEN_FUNDING_ENABLED is true. This is forbidden.")

    if dangerous_words:
        notes.append(
            "Dangerous permission words were found in local Kraken configuration. "
            "Only read-only permissions should be used."
        )

    has_keys = bool(api_key and api_secret)
    unsafe_flags = trading_enabled or withdrawals_enabled or funding_enabled or bool(dangerous_words)
    ready = has_keys and not unsafe_flags

    report = KrakenReadOnlyEnvironmentReport(
        env_file=str(env_file) if env_file else None,
        has_api_key=bool(api_key),
        has_api_secret=bool(api_secret),
        trading_enabled=trading_enabled,
        withdrawals_enabled=withdrawals_enabled,
        funding_enabled=funding_enabled,
        dangerous_permission_words_found=tuple(sorted(dangerous_words)),
        is_ready_for_readonly_private_client=ready,
        notes=tuple(notes),
    )

    if require_keys and not has_keys:
        raise KrakenReadOnlyEnvironmentError(
            "Kraken read-only credentials are required but KRAKEN_API_KEY or KRAKEN_API_SECRET is missing."
        )

    if unsafe_flags:
        raise KrakenReadOnlyEnvironmentError(
            "Unsafe Kraken environment settings detected. Read-only validation failed."
        )

    return report


def _load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}

    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        values[key.strip()] = _clean_value(value)

    return values


def _clean_value(value: object) -> str:
    if value is None:
        return ""

    cleaned = str(value).strip()
    cleaned = cleaned.strip('"').strip("'")
    return cleaned


def _parse_bool(value: object) -> bool:
    cleaned = _clean_value(value).lower()

    if cleaned in {"1", "true", "yes", "y", "on", "enabled"}:
        return True

    return False


def _find_dangerous_permission_words(values: Mapping[str, str]) -> set[str]:
    found: set[str] = set()

    # Scan only permission-oriented fields, not the raw API key/secret.
    permission_fields = {
        key: value
        for key, value in values.items()
        if "permission" in key.lower()
        or "scope" in key.lower()
        or "mode" in key.lower()
        or "enabled" in key.lower()
    }

    combined = " ".join(str(value).lower() for value in permission_fields.values())

    for word in DANGEROUS_PERMISSION_WORDS:
        if word in combined:
            found.add(word)

    return found
'@

# ============================ scripts/test_kraken_readonly_env_validator.py ============================

Write-TextFile (Join-Path $ScriptsPath "test_kraken_readonly_env_validator.py") @'
# ============================ Slice 12C-1 Validation - Kraken Read-Only Environment Validator ============================

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken.env_validation import (  # noqa: E402
    KrakenReadOnlyEnvironmentError,
    validate_kraken_readonly_environment,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 12C-1 Kraken read-only environment validation...")

    empty_report = validate_kraken_readonly_environment(environ={})
    assert_equal(empty_report.has_api_key, False, "empty config has no key")
    assert_equal(empty_report.has_api_secret, False, "empty config has no secret")
    assert_equal(empty_report.is_ready_for_readonly_private_client, False, "empty config is not ready")

    safe_report = validate_kraken_readonly_environment(
        environ={
            "KRAKEN_API_KEY": "dummy_key_for_validation_only",
            "KRAKEN_API_SECRET": "dummy_secret_for_validation_only",
            "KRAKEN_TRADING_ENABLED": "false",
            "KRAKEN_WITHDRAWALS_ENABLED": "false",
            "KRAKEN_FUNDING_ENABLED": "false",
        }
    )

    assert_equal(safe_report.has_api_key, True, "safe config has key")
    assert_equal(safe_report.has_api_secret, True, "safe config has secret")
    assert_equal(safe_report.trading_enabled, False, "trading disabled")
    assert_equal(safe_report.withdrawals_enabled, False, "withdrawals disabled")
    assert_equal(safe_report.funding_enabled, False, "funding disabled")
    assert_equal(safe_report.is_ready_for_readonly_private_client, True, "safe config ready for read-only client")

    safe_dict_text = str(safe_report.to_dict()).lower()
    assert_true("dummy_key" not in safe_dict_text, "report does not reveal API key")
    assert_true("dummy_secret" not in safe_dict_text, "report does not reveal API secret")

    with tempfile.TemporaryDirectory() as tmpdir:
        env_path = Path(tmpdir) / ".env"
        env_path.write_text(
            "\n".join(
                [
                    "KRAKEN_API_KEY=file_key_for_validation_only",
                    "KRAKEN_API_SECRET=file_secret_for_validation_only",
                    "KRAKEN_TRADING_ENABLED=false",
                    "KRAKEN_WITHDRAWALS_ENABLED=false",
                    "KRAKEN_FUNDING_ENABLED=false",
                ]
            ),
            encoding="utf-8",
        )

        file_report = validate_kraken_readonly_environment(env_file=env_path)
        assert_equal(file_report.has_api_key, True, ".env file key detected")
        assert_equal(file_report.has_api_secret, True, ".env file secret detected")
        assert_equal(file_report.is_ready_for_readonly_private_client, True, ".env file ready")

    try:
        validate_kraken_readonly_environment(
            environ={
                "KRAKEN_API_KEY": "dummy",
                "KRAKEN_API_SECRET": "dummy",
                "KRAKEN_TRADING_ENABLED": "true",
            }
        )
        raise AssertionError("Trading-enabled config should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] trading-enabled config rejected")

    try:
        validate_kraken_readonly_environment(
            environ={
                "KRAKEN_API_KEY": "dummy",
                "KRAKEN_API_SECRET": "dummy",
                "KRAKEN_WITHDRAWALS_ENABLED": "true",
            }
        )
        raise AssertionError("Withdrawal-enabled config should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] withdrawal-enabled config rejected")

    try:
        validate_kraken_readonly_environment(
            environ={
                "KRAKEN_API_KEY": "dummy",
                "KRAKEN_API_SECRET": "dummy",
                "KRAKEN_PERMISSION_SCOPE": "read balance trade withdraw",
            }
        )
        raise AssertionError("Dangerous permission scope should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] dangerous permission scope rejected")

    try:
        validate_kraken_readonly_environment(environ={}, require_keys=True)
        raise AssertionError("Missing required keys should have been rejected.")
    except KrakenReadOnlyEnvironmentError:
        print("[OK] require_keys rejects missing credentials")

    print("Kraken read-only environment validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# ============================ Update tradingagents/kraken/__init__.py ============================

$KrakenInitPath = Join-Path $KrakenPath "__init__.py"

if (-not (Test-Path $KrakenInitPath)) {
    Write-TextFile $KrakenInitPath @'
# ============================ Kraken Package Exports ============================
'@
}

$KrakenInit = Get-Content $KrakenInitPath -Raw

if ($KrakenInit -notmatch "env_validation") {
    Add-Content -Path $KrakenInitPath -Value @'

from tradingagents.kraken.env_validation import (
    KrakenReadOnlyEnvironmentError,
    KrakenReadOnlyEnvironmentReport,
    validate_kraken_readonly_environment,
)
'@
}

# Add names to __all__ if the file has one; otherwise create a safe __all__ block for the new names.
$KrakenInit = Get-Content $KrakenInitPath -Raw
if ($KrakenInit -notmatch "__all__") {
    Add-Content -Path $KrakenInitPath -Value @'

__all__ = [
    "KrakenReadOnlyEnvironmentError",
    "KrakenReadOnlyEnvironmentReport",
    "validate_kraken_readonly_environment",
]
'@
} elseif ($KrakenInit -notmatch "validate_kraken_readonly_environment") {
    # Import already added above, but if __all__ exists and does not include names, leave it alone to avoid breaking formatting.
    # Exports are still available as module attributes.
}

# ============================ Update docs ============================

$RoadmapPath = Join-Path $DocsPath "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $Roadmap = Get-Content $RoadmapPath -Raw
    if ($Roadmap -notmatch "Slice 12C-1") {
        Add-Content -Path $RoadmapPath -Value @'

## Slice 12C-1 — Kraken Read-Only Key Setup Guide and Environment Validator

Goal:

Validate local Kraken read-only credential configuration without calling Kraken private APIs.

Safety:

- No private Kraken requests.
- No balance access.
- No order access.
- No trading.
- No withdrawals.
- No secrets displayed in output.

Validation command:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python scripts/test_kraken_readonly_env_validator.py
```

Commit message:

```text
Add Kraken read-only environment validator
```
'@
    }
}

$KrakenPlanPath = Join-Path $DocsPath "07_KRAKEN_PLAN.md"
if (Test-Path $KrakenPlanPath) {
    $KrakenPlan = Get-Content $KrakenPlanPath -Raw
    if ($KrakenPlan -notmatch "Slice 12C-1") {
        Add-Content -Path $KrakenPlanPath -Value @'

## Slice 12C-1 — Read-Only Environment Validator

Before using a real Kraken private API key, the project must validate local configuration.

The validator must confirm:

- `KRAKEN_API_KEY` is present.
- `KRAKEN_API_SECRET` is present.
- `KRAKEN_TRADING_ENABLED` is not true.
- `KRAKEN_WITHDRAWALS_ENABLED` is not true.
- `KRAKEN_FUNDING_ENABLED` is not true.
- Dangerous permission words such as trade, withdraw, margin, leverage, futures, or funding are not present in local permission fields.

This slice does not call Kraken.

It only confirms that the local environment is ready for a future read-only private client test.
'@
    }
}

$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    $DecisionLog = Get-Content $DecisionLogPath -Raw
    if ($DecisionLog -notmatch "Kraken Read-Only Environment Validator") {
        Add-Content -Path $DecisionLogPath -Value @'

## 2026-05-22 — Slice 12C-1 Kraken Read-Only Environment Validator

Decision:

Before calling real Kraken private endpoints, the project will validate local read-only configuration.

This validator must not call Kraken and must not expose API key or secret values.

The validator blocks unsafe flags such as trading, withdrawals, and funding.
'@
    }
}

Write-Host "=== SLICE 12C-1 FILES CREATED ==="
Write-Host ""

Write-Host "=== RUNNING SLICE 12C-1 VALIDATION ==="
python .\scripts\test_kraken_readonly_env_validator.py

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "Slice 12C-1 script completed."
Write-Host ""

Get-ChildItem $KrakenPath | Select-Object Name, Length, LastWriteTime
