$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15D MANUAL EXECUTION COMMAND MODEL ==="

$root = (Get-Location).Path
$executionDir = Join-Path $root "tradingagents\execution"
$scriptsDir = Join-Path $root "scripts"
$docsDir = Join-Path $root "docs"

New-Item -ItemType Directory -Force $executionDir | Out-Null
New-Item -ItemType Directory -Force $scriptsDir | Out-Null

$initPath = Join-Path $executionDir "__init__.py"
if (Test-Path $initPath) {
    Write-Host "[SKIPPED] .\tradingagents\execution\__init__.py already exists; preserving current package exports."
} else {
@'
"""
Execution safety package.

Execution modules are built slice-by-slice and remain disabled by default.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] .\tradingagents\execution\__init__.py"
}

$modulePath = Join-Path $executionDir "manual_execution_command.py"
@'
"""
Manual execution command model.

Slice 15D purpose:
- Define a non-executable command object for a future manually approved live action.
- Link the command to a simulation package and an audit record.
- Validate command fields before any future execution layer can consume them.
- Provide safe-to-log reports.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT require trading permissions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from enum import StrEnum
from typing import Any, Mapping


class ManualExecutionCommandError(ValueError):
    """Raised when a manual execution command is invalid or non-executable."""


class ManualExecutionCommandStatus(StrEnum):
    """Lifecycle states for a non-executable manual execution command."""

    DRAFT = "draft"
    BLOCKED = "blocked"
    READY_FOR_REVIEW = "ready_for_review"
    APPROVED_FOR_FUTURE_EXECUTION = "approved_for_future_execution"


VALID_SIDES = {"buy", "sell"}
VALID_ORDER_TYPES = {"market", "limit"}

SENSITIVE_MARKERS = (
    "api_key",
    "api secret",
    "api_secret",
    "kraken_api_key",
    "kraken_api_secret",
    "password",
    "private key",
    "token",
)

FORBIDDEN_COMMAND_TERMS = (
    "withdraw",
    "withdrawal",
    "deposit",
    "transfer",
    "funding",
)


@dataclass(frozen=True)
class ManualExecutionCommand:
    """
    Non-executable command model for future manual execution.

    This object is deliberately only a command record. It cannot execute anything.
    """

    command_id: str
    package_id: str
    audit_id: str
    pair: str
    side: str
    order_type: str
    volume: Decimal
    limit_price: Decimal | None = None
    status: ManualExecutionCommandStatus = ManualExecutionCommandStatus.DRAFT
    reasons: tuple[str, ...] = field(default_factory=tuple)
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        object.__setattr__(self, "side", self.side.lower().strip())
        object.__setattr__(self, "order_type", self.order_type.lower().strip())
        object.__setattr__(self, "pair", self.pair.strip())
        object.__setattr__(self, "command_id", self.command_id.strip())
        object.__setattr__(self, "package_id", self.package_id.strip())
        object.__setattr__(self, "audit_id", self.audit_id.strip())
        object.__setattr__(self, "metadata", sanitize_for_command(self.metadata))
        self.validate()

    @property
    def is_reviewable(self) -> bool:
        """Return whether the command is ready for human review."""

        return self.status in {
            ManualExecutionCommandStatus.READY_FOR_REVIEW,
            ManualExecutionCommandStatus.APPROVED_FOR_FUTURE_EXECUTION,
        }

    @property
    def is_blocked(self) -> bool:
        """Return whether the command is currently blocked."""

        return self.status == ManualExecutionCommandStatus.BLOCKED or bool(self.reasons)

    def validate(self) -> None:
        """Validate command fields without executing anything."""

        if not self.command_id:
            raise ManualExecutionCommandError("command_id is required.")

        if not self.package_id:
            raise ManualExecutionCommandError("package_id is required.")

        if not self.audit_id:
            raise ManualExecutionCommandError("audit_id is required.")

        if not self.pair:
            raise ManualExecutionCommandError("pair is required.")

        if self.side not in VALID_SIDES:
            raise ManualExecutionCommandError("side must be buy or sell.")

        if self.order_type not in VALID_ORDER_TYPES:
            raise ManualExecutionCommandError("order_type must be market or limit.")

        if self.volume <= Decimal("0"):
            raise ManualExecutionCommandError("volume must be greater than zero.")

        if self.order_type == "limit" and self.limit_price is None:
            raise ManualExecutionCommandError("limit_price is required for limit commands.")

        if self.limit_price is not None and self.limit_price <= Decimal("0"):
            raise ManualExecutionCommandError("limit_price must be greater than zero.")

        validate_no_forbidden_command_terms(
            [
                self.command_id,
                self.package_id,
                self.audit_id,
                self.pair,
                self.side,
                self.order_type,
                *self.reasons,
            ]
        )

    def assert_not_executable(self) -> None:
        """Always block execution in Slice 15D."""

        raise ManualExecutionCommandError(
            "Slice 15D command objects are non-executable by design."
        )

    def to_dict(self) -> dict[str, Any]:
        """Return a safe dictionary representation."""

        payload = {
            "command_id": self.command_id,
            "package_id": self.package_id,
            "audit_id": self.audit_id,
            "pair": self.pair,
            "side": self.side,
            "order_type": self.order_type,
            "volume": str(self.volume),
            "limit_price": None if self.limit_price is None else str(self.limit_price),
            "status": self.status.value,
            "reviewable": self.is_reviewable,
            "blocked": self.is_blocked,
            "reasons": list(self.reasons),
            "metadata": sanitize_for_command(self.metadata),
            "credentials_included": False,
            "execution_enabled": False,
        }

        validate_no_sensitive_markers(str(payload))
        return payload

    def safe_report(self) -> dict[str, Any]:
        """Return a compact safe-to-log report."""

        report = {
            "command_id": self.command_id,
            "package_id": self.package_id,
            "audit_id": self.audit_id,
            "pair": self.pair,
            "side": self.side,
            "order_type": self.order_type,
            "status": self.status.value,
            "reviewable": self.is_reviewable,
            "blocked": self.is_blocked,
            "reason_count": len(self.reasons),
            "credentials_included": False,
            "execution_enabled": False,
        }

        validate_no_sensitive_markers(str(report))
        return report


def build_manual_execution_command(
    *,
    command_id: str,
    package_id: str,
    audit_id: str,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    status: str | ManualExecutionCommandStatus = ManualExecutionCommandStatus.DRAFT,
    reasons: tuple[str, ...] | list[str] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> ManualExecutionCommand:
    """Build and validate a non-executable manual execution command."""

    parsed_volume = parse_decimal(volume, name="volume")
    parsed_limit_price = (
        None if limit_price is None else parse_decimal(limit_price, name="limit_price")
    )
    parsed_status = parse_status(status)

    return ManualExecutionCommand(
        command_id=command_id,
        package_id=package_id,
        audit_id=audit_id,
        pair=pair,
        side=side,
        order_type=order_type,
        volume=parsed_volume,
        limit_price=parsed_limit_price,
        status=parsed_status,
        reasons=tuple(reasons or ()),
        metadata=metadata or {},
    )


def parse_decimal(value: str | Decimal, *, name: str) -> Decimal:
    """Parse a positive Decimal-compatible value."""

    if isinstance(value, Decimal):
        return value

    try:
        return Decimal(str(value).strip())
    except (InvalidOperation, ValueError) as exc:
        raise ManualExecutionCommandError(f"{name} must be a valid decimal.") from exc


def parse_status(
    value: str | ManualExecutionCommandStatus,
) -> ManualExecutionCommandStatus:
    """Parse a command status."""

    if isinstance(value, ManualExecutionCommandStatus):
        return value

    try:
        return ManualExecutionCommandStatus(str(value).strip().lower())
    except ValueError as exc:
        allowed = ", ".join(item.value for item in ManualExecutionCommandStatus)
        raise ManualExecutionCommandError(
            f"status must be one of: {allowed}."
        ) from exc


def sanitize_for_command(value: Any) -> Any:
    """Redact sensitive-looking values from metadata."""

    if isinstance(value, Mapping):
        sanitized: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if contains_sensitive_marker(key_text):
                sanitized[key_text] = "[REDACTED]"
            else:
                sanitized[key_text] = sanitize_for_command(item)
        return sanitized

    if isinstance(value, list):
        return [sanitize_for_command(item) for item in value]

    if isinstance(value, tuple):
        return tuple(sanitize_for_command(item) for item in value)

    text = str(value)
    if contains_sensitive_marker(text):
        return "[REDACTED]"

    return value


def validate_no_forbidden_command_terms(values: list[str]) -> None:
    """Reject forbidden operational terms from command fields."""

    for value in values:
        lowered = str(value).lower()
        for term in FORBIDDEN_COMMAND_TERMS:
            if term in lowered:
                raise ManualExecutionCommandError(
                    f"Forbidden command term rejected: {term}"
                )


def validate_no_sensitive_markers(text: str) -> None:
    """Reject non-redacted sensitive-looking text."""

    lowered = text.lower()
    for marker in SENSITIVE_MARKERS:
        if marker in lowered and "[redacted]" not in lowered:
            raise ManualExecutionCommandError(
                f"Sensitive-looking value rejected from command report: {marker}"
            )


def contains_sensitive_marker(text: str) -> bool:
    """Return whether text contains a sensitive-looking marker."""

    lowered = text.lower()
    return any(marker in lowered for marker in SENSITIVE_MARKERS)
'@ | Set-Content -Path $modulePath -Encoding UTF8
Write-Host "[WRITTEN] .\tradingagents\execution\manual_execution_command.py"

$testPath = Join-Path $scriptsDir "test_manual_execution_command_model.py"
@'
"""
Validation script for Slice 15D.

This test confirms the manual execution command model is valid, safe to log,
and non-executable by design.
"""

from __future__ import annotations

from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommandError,
    ManualExecutionCommandStatus,
    build_manual_execution_command,
)


def expect_command_error(label: str, func) -> None:
    try:
        func()
    except ManualExecutionCommandError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualExecutionCommandError")


def make_valid_command(**overrides):
    data = {
        "command_id": "cmd_slice_15d_001",
        "package_id": "pkg_slice_15a_001",
        "audit_id": "audit_slice_15b_001",
        "pair": "XBT/CAD",
        "side": "buy",
        "order_type": "limit",
        "volume": "0.000085168",
        "limit_price": "100000",
        "status": ManualExecutionCommandStatus.READY_FOR_REVIEW,
        "reasons": (),
        "metadata": {"source": "slice_15d_test"},
    }
    data.update(overrides)
    return build_manual_execution_command(**data)


def test_valid_command_safe_report() -> None:
    command = make_valid_command()

    assert command.command_id == "cmd_slice_15d_001"
    assert command.package_id == "pkg_slice_15a_001"
    assert command.audit_id == "audit_slice_15b_001"
    assert command.pair == "XBT/CAD"
    assert command.side == "buy"
    assert command.order_type == "limit"
    assert command.is_reviewable is True
    assert command.is_blocked is False

    report = command.safe_report()

    assert report["command_id"] == command.command_id
    assert report["package_id"] == command.package_id
    assert report["audit_id"] == command.audit_id
    assert report["credentials_included"] is False
    assert report["execution_enabled"] is False

    print("[OK] valid command safe report passed")


def test_command_is_non_executable() -> None:
    command = make_valid_command(
        status=ManualExecutionCommandStatus.APPROVED_FOR_FUTURE_EXECUTION
    )

    expect_command_error(
        "approved-for-future command remains non-executable",
        command.assert_not_executable,
    )


def test_blocked_command_state() -> None:
    command = make_valid_command(
        status=ManualExecutionCommandStatus.BLOCKED,
        reasons=("Readiness report is blocked.",),
    )

    assert command.is_blocked is True
    report = command.safe_report()
    assert report["blocked"] is True
    assert report["reason_count"] == 1

    print("[OK] blocked command state passed")


def test_invalid_commands_are_rejected() -> None:
    expect_command_error(
        "missing command_id rejected",
        lambda: make_valid_command(command_id=""),
    )
    expect_command_error(
        "missing package_id rejected",
        lambda: make_valid_command(package_id=""),
    )
    expect_command_error(
        "missing audit_id rejected",
        lambda: make_valid_command(audit_id=""),
    )
    expect_command_error(
        "missing pair rejected",
        lambda: make_valid_command(pair=""),
    )
    expect_command_error(
        "invalid side rejected",
        lambda: make_valid_command(side="hold"),
    )
    expect_command_error(
        "invalid order type rejected",
        lambda: make_valid_command(order_type="stop"),
    )
    expect_command_error(
        "zero volume rejected",
        lambda: make_valid_command(volume="0"),
    )
    expect_command_error(
        "missing limit price rejected",
        lambda: make_valid_command(order_type="limit", limit_price=None),
    )
    expect_command_error(
        "negative limit price rejected",
        lambda: make_valid_command(limit_price="-1"),
    )
    expect_command_error(
        "invalid status rejected",
        lambda: make_valid_command(status="live_now"),
    )


def test_sensitive_metadata_is_redacted() -> None:
    command = make_valid_command(
        metadata={
            "source": "slice_15d_test",
            "api_key": "abc123",
            "nested": {"token": "very-sensitive-value"},
        }
    )

    payload = command.to_dict()

    assert payload["metadata"]["api_key"] == "[REDACTED]"
    assert payload["metadata"]["nested"]["token"] == "[REDACTED]"
    assert payload["credentials_included"] is False
    assert payload["execution_enabled"] is False

    print("[OK] sensitive metadata is redacted")


def test_forbidden_command_terms_are_rejected() -> None:
    expect_command_error(
        "forbidden command term rejected",
        lambda: make_valid_command(reasons=("withdraw behavior is not allowed",)),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    from pathlib import Path

    source = Path(
        "tradingagents/execution/manual_execution_command.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdrawfunds",
        "depositmethods",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] command source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15D validation: Manual Execution Command Model")
    print("=" * 80)

    test_valid_command_safe_report()
    test_command_is_non_executable()
    test_blocked_command_state()
    test_invalid_commands_are_rejected()
    test_sensitive_metadata_is_redacted()
    test_forbidden_command_terms_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15D manual execution command model validation passed.")
    print("[PASS] Commands are safe to log and non-executable by design.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@ | Set-Content -Path $testPath -Encoding UTF8
Write-Host "[WRITTEN] .\scripts\test_manual_execution_command_model.py"

function Add-BlockIfMissing {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Force $Path | Out-Null
    }

    $existing = Get-Content $Path -Raw
    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`n$Block" -Encoding UTF8
        Write-Host "[UPDATED] .\$($Path.Substring($root.Length + 1))"
    } else {
        Write-Host "[SKIPPED] .\$($Path.Substring($root.Length + 1)) already contains $Marker"
    }
}

$roadmapPath = Join-Path $docsDir "03_ROADMAP.md"
$controlsPath = Join-Path $docsDir "10_EXECUTION_AND_RISK_CONTROLS.md"
$decisionPath = Join-Path $docsDir "11_DECISION_LOG.md"

$roadmapBlock = @'
## Slice 15D — Manual Execution Command Model

Status: Implemented pending validation.

Goal:
Create a formal non-executable command object for a future manually approved live execution path.

Scope:
- Adds a manual execution command model.
- Links command records to simulation package IDs.
- Links command records to execution audit IDs.
- Validates pair, side, order type, volume, limit price, status, and reason text.
- Provides safe-to-log command reports.
- Keeps commands non-executable by design.

Still forbidden:
- No Kraken AddOrder call.
- No Kraken CancelOrder call.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/manual_execution_command.py`
- `scripts/test_manual_execution_command_model.py`
- `scripts/create_slice_15d_manual_execution_command_model.ps1`

Validation:
- Confirms valid command creation.
- Confirms command reports are safe to log.
- Confirms commands cannot execute.
- Confirms blocked command state.
- Confirms invalid command fields are rejected.
- Confirms sensitive-looking metadata is redacted.
- Confirms no private execution endpoint call was introduced.
'@

$controlsBlock = @'
## Slice 15D — Manual Execution Command Model

Slice 15D adds a non-executable command model for future manual live execution.

The command model links together:
- a command ID
- a simulation package ID
- an execution audit record ID
- pair
- side
- order type
- volume
- limit price
- command status
- reasons
- safe metadata

Command statuses:
- `draft`
- `blocked`
- `ready_for_review`
- `approved_for_future_execution`

Important safety behavior:
- A command object cannot execute anything.
- Even an `approved_for_future_execution` command remains non-executable in this slice.
- Reports are safe to log.
- Sensitive-looking metadata is redacted.
- Funding, withdrawal, and transfer terms are rejected from command reason text.

This slice does not add private execution endpoint calls and does not require trading permissions.
'@

$decisionBlock = @'
## Slice 15D Decision — Manual Execution Requires a Formal Command Model

Decision:
Before adding any future live execution path, the project must have a formal manual execution command model.

Reason:
The project now has simulation packages and execution audit logs. A future live path should not directly consume raw order dictionaries. It should consume a validated command object that is linked to a simulation package and audit record.

Result:
Slice 15D introduces a non-executable command model with strict validation and safe reporting.

Safety outcome:
- The command model cannot place orders.
- The command model cannot cancel orders.
- The command model does not call private execution endpoints.
- The command model does not require trading, funding, or withdrawal permissions.
'@

Add-BlockIfMissing -Path $roadmapPath -Marker "Slice 15D — Manual Execution Command Model" -Block $roadmapBlock
Add-BlockIfMissing -Path $controlsPath -Marker "Slice 15D — Manual Execution Command Model" -Block $controlsBlock
Add-BlockIfMissing -Path $decisionPath -Marker "Slice 15D Decision — Manual Execution Requires a Formal Command Model" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15D FILES ==="
Get-Item $modulePath, $testPath, $roadmapPath, $controlsPath, $decisionPath | Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15D script completed."
