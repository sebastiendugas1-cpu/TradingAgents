$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== SLICE 14B DISABLED-BY-DEFAULT KRAKEN LIVE EXECUTION CLIENT SKELETON ==="

$Root = Resolve-Path "."
$ExecutionDir = Join-Path $Root "tradingagents\execution"
$ScriptsDir = Join-Path $Root "scripts"
$DocsDir = Join-Path $Root "docs"

New-Item -ItemType Directory -Force $ExecutionDir | Out-Null
New-Item -ItemType Directory -Force $ScriptsDir | Out-Null

$initPath = Join-Path $ExecutionDir "__init__.py"
if (-not (Test-Path $initPath)) {
@'
"""
Execution safety package.

Live execution modules are disabled by default and guarded by safety config.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] .\tradingagents\execution\__init__.py"
} else {
    Write-Host "[SKIPPED] .\tradingagents\execution\__init__.py already exists; preserving current package exports."
}

$clientPath = Join-Path $ExecutionDir "kraken_live_execution_client.py"
@'
"""
Disabled-by-default Kraken live execution client skeleton.

Slice 14B purpose:
- Create the structure for a future Kraken live execution client.
- Require the Slice 14A safety gate before any future executable action.
- Prove that default configuration blocks every live execution path.
- Avoid any real Kraken private execution endpoint call.

Important:
This module does NOT place live orders.
This module does NOT cancel live orders.
This module does NOT send private trading requests.
This module does NOT require trading, funding, or withdrawal permissions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Mapping

from tradingagents.execution.safety_config import LiveExecutionSafetyConfig


class LiveExecutionNotImplementedError(RuntimeError):
    """
    Raised after the safety gate if live execution is requested later.

    Slice 14B intentionally keeps this client as a blocked skeleton.
    """


@dataclass(frozen=True)
class KrakenLiveOrderRequest:
    """
    Structured request model for a future Kraken live order.

    This model is safe because it is only data. It does not call Kraken.
    """

    pair: str
    side: str
    order_type: str
    volume: Decimal
    price: Decimal | None = None
    client_reference: str = ""
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        """Validate request shape without executing anything."""

        if not self.pair.strip():
            raise ValueError("pair is required.")

        if self.side.lower() not in {"buy", "sell"}:
            raise ValueError("side must be buy or sell.")

        if not self.order_type.strip():
            raise ValueError("order_type is required.")

        if self.volume <= Decimal("0"):
            raise ValueError("volume must be greater than zero.")

        if self.price is not None and self.price <= Decimal("0"):
            raise ValueError("price must be greater than zero when provided.")


@dataclass(frozen=True)
class KrakenLiveCancelRequest:
    """
    Structured request model for a future Kraken live cancellation.

    This model is safe because it is only data. It does not call Kraken.
    """

    transaction_id: str
    client_reference: str = ""
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        """Validate request shape without executing anything."""

        if not self.transaction_id.strip():
            raise ValueError("transaction_id is required.")


@dataclass(frozen=True)
class KrakenLiveExecutionClient:
    """
    Disabled-by-default skeleton for future Kraken live execution.

    A caller must pass a LiveExecutionSafetyConfig. With the default safety config,
    every executable method is blocked before any future client operation could run.
    """

    safety_config: LiveExecutionSafetyConfig
    private_client: Any | None = None

    def submit_order(self, request: KrakenLiveOrderRequest) -> None:
        """
        Future live order submission entry point.

        In Slice 14B, this is intentionally blocked by the safety gate and then
        intentionally not implemented even if a future unsafe config is supplied.
        """

        request.validate()
        self.safety_config.assert_live_execution_allowed("kraken execution request")
        raise LiveExecutionNotImplementedError(
            "Live order submission is intentionally not implemented in Slice 14B."
        )

    def cancel_order(self, request: KrakenLiveCancelRequest) -> None:
        """
        Future live cancellation entry point.

        In Slice 14B, this is intentionally blocked by the safety gate and then
        intentionally not implemented even if a future unsafe config is supplied.
        """

        request.validate()
        self.safety_config.assert_live_execution_allowed("kraken cancellation request")
        raise LiveExecutionNotImplementedError(
            "Live order cancellation is intentionally not implemented in Slice 14B."
        )

    def safe_report(self) -> dict[str, str | bool]:
        """Return safe-to-log client status without secrets or credentials."""

        return {
            "client": "KrakenLiveExecutionClient",
            "live_execution_client_skeleton": True,
            "private_client_present": self.private_client is not None,
            "live_trading_enabled": self.safety_config.live_trading_enabled,
            "kill_switch": self.safety_config.kill_switch,
            "max_live_trade_value": str(self.safety_config.max_live_trade_value),
            "secrets_included": False,
        }
'@ | Set-Content -Path $clientPath -Encoding UTF8
Write-Host "[WRITTEN] .\tradingagents\execution\kraken_live_execution_client.py"

$testPath = Join-Path $ScriptsDir "test_kraken_live_execution_client_skeleton.py"
@'
"""
Validation script for Slice 14B.

This script confirms the Kraken live execution client skeleton is blocked by
default and does not call any real Kraken execution method.

It does not:
- place live orders
- cancel live orders
- call Kraken private trading endpoints
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

import inspect
from decimal import Decimal

from tradingagents.execution.kraken_live_execution_client import (
    KrakenLiveCancelRequest,
    KrakenLiveExecutionClient,
    KrakenLiveOrderRequest,
    LiveExecutionNotImplementedError,
)
from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


class RecordingPrivateClient:
    """Test double proving the private client is not called."""

    def __init__(self) -> None:
        self.calls: list[str] = []

    def request(self, *args, **kwargs) -> None:
        self.calls.append("request")


def expect_error(label: str, error_type: type[BaseException], func) -> None:
    try:
        func()
    except error_type as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected {error_type.__name__}")


def make_valid_order_request() -> KrakenLiveOrderRequest:
    return KrakenLiveOrderRequest(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        price=Decimal("100000"),
        client_reference="slice-14b-test",
        metadata={"source": "validation"},
    )


def make_valid_cancel_request() -> KrakenLiveCancelRequest:
    return KrakenLiveCancelRequest(
        transaction_id="TEST-TRANSACTION-ID",
        client_reference="slice-14b-test",
        metadata={"source": "validation"},
    )


def test_default_config_blocks_submit_and_cancel() -> None:
    private_client = RecordingPrivateClient()
    client = KrakenLiveExecutionClient(
        safety_config=LiveExecutionSafetyConfig.default(),
        private_client=private_client,
    )

    expect_error(
        "default config blocks submit_order",
        SafetyConfigError,
        lambda: client.submit_order(make_valid_order_request()),
    )

    expect_error(
        "default config blocks cancel_order",
        SafetyConfigError,
        lambda: client.cancel_order(make_valid_cancel_request()),
    )

    assert private_client.calls == []
    print("[OK] private client was not called with default blocked config")


def test_kill_switch_blocks_even_when_other_settings_are_live_like() -> None:
    private_client = RecordingPrivateClient()
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "true",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )
    client = KrakenLiveExecutionClient(safety_config=config, private_client=private_client)

    expect_error(
        "kill switch blocks submit_order",
        SafetyConfigError,
        lambda: client.submit_order(make_valid_order_request()),
    )

    expect_error(
        "kill switch blocks cancel_order",
        SafetyConfigError,
        lambda: client.cancel_order(make_valid_cancel_request()),
    )

    assert private_client.calls == []
    print("[OK] private client was not called while kill switch was active")


def test_even_permissive_config_does_not_implement_live_execution() -> None:
    private_client = RecordingPrivateClient()
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )
    client = KrakenLiveExecutionClient(safety_config=config, private_client=private_client)

    expect_error(
        "submit_order remains not implemented after safety gate",
        LiveExecutionNotImplementedError,
        lambda: client.submit_order(make_valid_order_request()),
    )

    expect_error(
        "cancel_order remains not implemented after safety gate",
        LiveExecutionNotImplementedError,
        lambda: client.cancel_order(make_valid_cancel_request()),
    )

    assert private_client.calls == []
    print("[OK] private client was still not called with permissive config")


def test_request_validation_happens_before_safety_gate() -> None:
    client = KrakenLiveExecutionClient(safety_config=LiveExecutionSafetyConfig.default())

    bad_order = KrakenLiveOrderRequest(
        pair="",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
    )

    bad_cancel = KrakenLiveCancelRequest(transaction_id="")

    expect_error(
        "bad order request rejected",
        ValueError,
        lambda: client.submit_order(bad_order),
    )

    expect_error(
        "bad cancel request rejected",
        ValueError,
        lambda: client.cancel_order(bad_cancel),
    )


def test_safe_report_excludes_secrets() -> None:
    client = KrakenLiveExecutionClient(safety_config=LiveExecutionSafetyConfig.default())
    report = client.safe_report()
    report_text = str(report).lower()

    assert report["client"] == "KrakenLiveExecutionClient"
    assert report["live_execution_client_skeleton"] is True
    assert report["live_trading_enabled"] is False
    assert report["kill_switch"] is True
    assert report["max_live_trade_value"] == "0"
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

    print("[OK] client report is safe to log")


def test_no_kraken_execution_endpoint_names_in_client_source() -> None:
    import tradingagents.execution.kraken_live_execution_client as module

    source = inspect.getsource(module)
    forbidden_source_terms = [
        "/0/private/AddOrder",
        "/0/private/CancelOrder",
        "AddOrder",
        "CancelOrder",
    ]

    for term in forbidden_source_terms:
        assert term not in source

    print("[OK] client source contains no Kraken execution endpoint names")


def main() -> None:
    print("Slice 14B validation: Disabled-by-Default Kraken Live Execution Client Skeleton")
    print("=" * 80)

    test_default_config_blocks_submit_and_cancel()
    test_kill_switch_blocks_even_when_other_settings_are_live_like()
    test_even_permissive_config_does_not_implement_live_execution()
    test_request_validation_happens_before_safety_gate()
    test_safe_report_excludes_secrets()
    test_no_kraken_execution_endpoint_names_in_client_source()

    print("=" * 80)
    print("[PASS] Slice 14B live execution client skeleton validation passed.")
    print("[PASS] Default safety config blocks submit and cancel paths.")
    print("[PASS] No Kraken live execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@ | Set-Content -Path $testPath -Encoding UTF8
Write-Host "[WRITTEN] .\scripts\test_kraken_live_execution_client_skeleton.py"

function Add-DocBlockIfMissing {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing required doc file: $Path"
    }

    $content = Get-Content -Path $Path -Raw

    if ($content -notlike "*$Marker*") {
        Add-Content -Path $Path -Value ""
        Add-Content -Path $Path -Value $Block
        Write-Host "[UPDATED] $($Path.Replace($Root.Path + '\', '.\'))"
    } else {
        Write-Host "[SKIPPED] $($Path.Replace($Root.Path + '\', '.\')) already contains $Marker"
    }
}

$roadmapPath = Join-Path $DocsDir "03_ROADMAP.md"
$executionControlsPath = Join-Path $DocsDir "10_EXECUTION_AND_RISK_CONTROLS.md"
$decisionLogPath = Join-Path $DocsDir "11_DECISION_LOG.md"

$roadmapBlock = @'
## Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton

Status: Implemented pending validation.

Goal:
Create a disabled-by-default Kraken live execution client skeleton that is fully blocked by the Slice 14A safety config.

Scope:
- Create structured request models for future submit and cancel paths.
- Require `LiveExecutionSafetyConfig.assert_live_execution_allowed(...)` before any future executable action.
- Keep the client intentionally not implemented after the safety gate.
- Prove that default configuration blocks submit and cancel paths.
- Prove that no private Kraken execution endpoint call exists in this slice.

Files introduced:
- `tradingagents/execution/kraken_live_execution_client.py`
- `scripts/test_kraken_live_execution_client_skeleton.py`
- `scripts/create_slice_14b_kraken_live_execution_client_skeleton.ps1`

Still forbidden:
- No successful Kraken live order submission.
- No successful Kraken live order cancellation.
- No automatic live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Validation:
- Default safety config blocks submit and cancel paths.
- Kill switch blocks submit and cancel paths even when other settings look live-like.
- Even permissive test settings do not execute because live execution is intentionally not implemented.
- Private client test double is never called.
- Safe report excludes secrets.
- Client source contains no Kraken live execution endpoint names.
'@

$executionBlock = @'
## Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton

A disabled-by-default Kraken live execution client skeleton has been introduced.

The client is implemented in:

`tradingagents/execution/kraken_live_execution_client.py`

Safety requirements:
- All future executable paths must pass through `LiveExecutionSafetyConfig.assert_live_execution_allowed(...)`.
- Default config blocks all submit/cancel paths.
- Kill switch blocks all submit/cancel paths.
- Even if a permissive test config is supplied, Slice 14B raises a not-implemented error instead of calling any private client.

Current restrictions:
- No real Kraken live execution endpoint call exists.
- No live order submission is implemented.
- No live cancellation is implemented.
- No withdrawal or funding behavior exists.
- No trading permission is required for validation.
'@

$decisionBlock = @'
## Slice 14B Decision — Create Live Execution Shape Without Enabling Live Execution

Decision:
Create the Kraken live execution client skeleton before adding any real live execution behavior.

Reason:
The project now has manual approval, risk gates, dry-run previews, and a global execution safety config. The next safe architectural step is to define where future live execution will live while proving that all paths remain blocked by default.

Chosen approach:
- Create typed request models for future submit and cancel paths.
- Require the Slice 14A safety gate before any future executable behavior.
- Keep the methods intentionally not implemented after the safety gate.
- Validate that the private client is never called.
- Validate that the source contains no Kraken live execution endpoint names.

Result:
The project gains the live execution client structure without enabling live trading.
'@

Add-DocBlockIfMissing -Path $roadmapPath -Marker "Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton" -Block $roadmapBlock
Add-DocBlockIfMissing -Path $executionControlsPath -Marker "Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton" -Block $executionBlock
Add-DocBlockIfMissing -Path $decisionLogPath -Marker "Slice 14B Decision — Create Live Execution Shape Without Enabling Live Execution" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 14B FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_live_execution_client.py", `
    ".\scripts\test_kraken_live_execution_client_skeleton.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 14B script completed."
