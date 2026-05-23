$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15E MANUAL EXECUTION COMMAND BUILDER ==="

$root = (Get-Location).Path
$executionDir = ".\tradingagents\execution"
New-Item -ItemType Directory -Force $executionDir | Out-Null

$initPath = Join-Path $executionDir "__init__.py"
if (Test-Path $initPath) {
    Write-Host "[SKIPPED] $initPath already exists; preserving current package exports."
} else {
    @'
"""
Execution package.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] $initPath"
}

$builderPath = Join-Path $executionDir "manual_execution_command_builder.py"
@'
"""
Manual execution command builder.

Slice 15E purpose:
- Connect a simulation package, audit integration, and manual execution command model.
- Produce a safe, non-executable command candidate.
- Keep the whole flow blocked from live execution by design.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT require funding, withdrawal, or trading permissions.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.execution_audit_log import (
    ExecutionAuditLogError,
    ExecutionAuditRecord,
    JsonlExecutionAuditLogWriter,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandError,
)
from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationPackageError,
    build_manual_live_order_simulation_package,
)
from tradingagents.execution.simulated_execution_audit_integration import (
    write_simulated_execution_package_audit_record,
)


class ManualExecutionCommandBuilderError(ValueError):
    """Raised when a manual execution command cannot be built safely."""


@dataclass(frozen=True)
class ManualExecutionCommandBuildResult:
    """
    Result of building a non-executable manual execution command.

    The command created here is still not executable. It is only a structured
    command candidate that links together:
    - the simulation package
    - the audit record
    - the command model
    """

    builder_id: str
    package_id: str
    audit_id: str
    command_id: str
    command_status: str
    final_status: str
    blocked: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)
    simulation_report: Mapping[str, Any] = field(default_factory=dict)
    audit_report: Mapping[str, Any] = field(default_factory=dict)
    command_report: Mapping[str, Any] = field(default_factory=dict)
    secrets_included: bool = False
    execution_endpoint_called: bool = False

    def safe_report(self) -> dict[str, Any]:
        """Return a safe-to-log build report."""

        return {
            "builder_id": self.builder_id,
            "package_id": self.package_id,
            "audit_id": self.audit_id,
            "command_id": self.command_id,
            "command_status": self.command_status,
            "final_status": self.final_status,
            "blocked": self.blocked,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "simulation_report": _safe_mapping(self.simulation_report),
            "audit_report": _safe_mapping(self.audit_report),
            "command_report": _safe_mapping(self.command_report),
            "secrets_included": False,
            "execution_endpoint_called": False,
        }


def build_manual_execution_command_from_order_intent(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal,
    limit_price: str | Decimal | None = None,
    audit_file_path: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> ManualExecutionCommandBuildResult:
    """
    Build a non-executable manual execution command from an order intent.

    This function performs the safe workflow:
    1. Build a simulation-only package.
    2. Write a safe local audit record.
    3. Create a non-executable manual command linked to package_id and audit_id.
    """

    pair_value = _require_text(pair, "pair")
    side_value = _normalize_side(side)
    order_type_value = _normalize_order_type(order_type)
    volume_value = _parse_positive_decimal(volume, "volume")
    limit_price_value = _parse_limit_price(order_type_value, limit_price)

    path = Path(audit_file_path) if audit_file_path is not None else Path("reports") / "execution_audit.jsonl"

    simulation_package = build_manual_live_order_simulation_package(
        pair=pair_value,
        side=side_value,
        order_type=order_type_value,
        volume=str(volume_value),
        limit_price=str(limit_price_value) if limit_price_value is not None else None,
        env=env,
        metadata=dict(metadata or {}),
    )

    audit_result = write_simulated_execution_package_audit_record(
        package=simulation_package,
        audit_file_path=path,
    )

    audit_record = _extract_audit_record(audit_result)
    audit_id = _extract_audit_id(audit_record, audit_result)

    command_status = "blocked" if getattr(simulation_package, "blocked", True) else "ready_for_review"

    command = ManualExecutionCommand(
        command_id=f"cmd_{uuid4().hex}",
        package_id=str(getattr(simulation_package, "package_id", "")),
        audit_id=audit_id,
        pair=pair_value,
        side=side_value,
        order_type=order_type_value,
        volume=str(volume_value),
        limit_price=str(limit_price_value) if limit_price_value is not None else None,
        status=command_status,
        metadata={
            "source": "slice_15e_manual_execution_command_builder",
            "simulation_only": True,
            "live_execution_enabled": False,
        },
    )

    command.validate()

    simulation_report = _call_safe_report(simulation_package)
    audit_report = _call_safe_report(audit_record)
    command_report = command.safe_report()

    reasons = tuple(_extract_reasons(simulation_package))
    final_status = "simulation_command_blocked_from_live_execution"

    return ManualExecutionCommandBuildResult(
        builder_id=f"builder_{uuid4().hex}",
        package_id=str(getattr(simulation_package, "package_id", "")),
        audit_id=audit_id,
        command_id=command.command_id,
        command_status=command.status,
        final_status=final_status,
        blocked=True,
        reasons=reasons or ("Manual execution command builder is simulation-only in Slice 15E.",),
        simulation_report=simulation_report,
        audit_report=audit_report,
        command_report=command_report,
        secrets_included=False,
        execution_endpoint_called=False,
    )


def build_manual_execution_command_from_simulation_package(
    *,
    package: Any,
    audit_file_path: str | Path,
) -> ManualExecutionCommandBuildResult:
    """
    Build a non-executable command from an existing simulation package.

    This is useful when the simulation package was created elsewhere.
    """

    audit_result = write_simulated_execution_package_audit_record(
        package=package,
        audit_file_path=Path(audit_file_path),
    )

    audit_record = _extract_audit_record(audit_result)
    audit_id = _extract_audit_id(audit_record, audit_result)

    package_id = str(getattr(package, "package_id", ""))
    if not package_id:
        raise ManualExecutionCommandBuilderError("package_id is required.")

    pair = _require_text(str(getattr(package, "pair", "")), "pair")
    side = _normalize_side(str(getattr(package, "side", "")))
    order_type = _normalize_order_type(str(getattr(package, "order_type", "")))
    volume = _parse_positive_decimal(getattr(package, "volume", ""), "volume")
    limit_price = getattr(package, "limit_price", None)
    parsed_limit_price = _parse_limit_price(order_type, limit_price)

    command_status = "blocked" if getattr(package, "blocked", True) else "ready_for_review"

    command = ManualExecutionCommand(
        command_id=f"cmd_{uuid4().hex}",
        package_id=package_id,
        audit_id=audit_id,
        pair=pair,
        side=side,
        order_type=order_type,
        volume=str(volume),
        limit_price=str(parsed_limit_price) if parsed_limit_price is not None else None,
        status=command_status,
        metadata={
            "source": "slice_15e_existing_simulation_package",
            "simulation_only": True,
            "live_execution_enabled": False,
        },
    )

    command.validate()

    return ManualExecutionCommandBuildResult(
        builder_id=f"builder_{uuid4().hex}",
        package_id=package_id,
        audit_id=audit_id,
        command_id=command.command_id,
        command_status=command.status,
        final_status="simulation_command_blocked_from_live_execution",
        blocked=True,
        reasons=tuple(_extract_reasons(package)) or ("Manual execution command builder is simulation-only in Slice 15E.",),
        simulation_report=_call_safe_report(package),
        audit_report=_call_safe_report(audit_record),
        command_report=command.safe_report(),
        secrets_included=False,
        execution_endpoint_called=False,
    )


def assert_builder_result_cannot_execute(result: ManualExecutionCommandBuildResult) -> None:
    """Always block execution from Slice 15E build results."""

    raise ManualExecutionCommandBuilderError(
        "Slice 15E command builder creates non-executable command candidates only."
    )


def _extract_audit_record(audit_result: Any) -> Any:
    if isinstance(audit_result, ExecutionAuditRecord):
        return audit_result

    for attr in ("audit_record", "record", "execution_audit_record"):
        if hasattr(audit_result, attr):
            return getattr(audit_result, attr)

    if isinstance(audit_result, Mapping):
        for key in ("audit_record", "record", "execution_audit_record"):
            if key in audit_result:
                return audit_result[key]

    return audit_result


def _extract_audit_id(audit_record: Any, audit_result: Any) -> str:
    for source in (audit_record, audit_result):
        if hasattr(source, "audit_id"):
            value = str(getattr(source, "audit_id", "")).strip()
            if value:
                return value

        if isinstance(source, Mapping):
            value = str(source.get("audit_id", "")).strip()
            if value:
                return value

    raise ManualExecutionCommandBuilderError("audit_id is required.")


def _extract_reasons(package: Any) -> list[str]:
    reasons = getattr(package, "reasons", None)

    if reasons is None and isinstance(package, Mapping):
        reasons = package.get("reasons")

    if reasons is None:
        return []

    return [str(reason) for reason in reasons]


def _call_safe_report(value: Any) -> dict[str, Any]:
    if hasattr(value, "safe_report"):
        report = value.safe_report()
        if isinstance(report, Mapping):
            return dict(report)

    if hasattr(value, "to_dict"):
        report = value.to_dict()
        if isinstance(report, Mapping):
            return _safe_mapping(report)

    if isinstance(value, Mapping):
        return _safe_mapping(value)

    return {"type": type(value).__name__, "secrets_included": False}


def _safe_mapping(value: Mapping[str, Any]) -> dict[str, Any]:
    return {
        str(key): _safe_value(item)
        for key, item in value.items()
        if "secret" not in str(key).lower()
        and "token" not in str(key).lower()
        and "password" not in str(key).lower()
        and "api_key" not in str(key).lower()
    }


def _safe_value(value: Any) -> Any:
    if isinstance(value, Mapping):
        return _safe_mapping(value)

    if isinstance(value, (list, tuple)):
        return [_safe_value(item) for item in value]

    text = str(value)
    lowered = text.lower()
    if any(marker in lowered for marker in ("api_key", "api secret", "api_secret", "password", "private key", "token")):
        return "[REDACTED]"

    return value


def _require_text(value: str, field_name: str) -> str:
    text = str(value or "").strip()
    if not text:
        raise ManualExecutionCommandBuilderError(f"{field_name} is required.")
    return text


def _normalize_side(value: str) -> str:
    side = _require_text(value, "side").lower()
    if side not in {"buy", "sell"}:
        raise ManualExecutionCommandBuilderError("side must be buy or sell.")
    return side


def _normalize_order_type(value: str) -> str:
    order_type = _require_text(value, "order_type").lower()
    if order_type not in {"market", "limit"}:
        raise ManualExecutionCommandBuilderError("order_type must be market or limit.")
    return order_type


def _parse_positive_decimal(value: str | Decimal, field_name: str) -> Decimal:
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ManualExecutionCommandBuilderError(f"{field_name} must be a valid decimal number.") from exc

    if parsed <= Decimal("0"):
        raise ManualExecutionCommandBuilderError(f"{field_name} must be greater than zero.")

    return parsed


def _parse_limit_price(order_type: str, value: str | Decimal | None) -> Decimal | None:
    if order_type == "market":
        return None

    if value is None or str(value).strip() == "":
        raise ManualExecutionCommandBuilderError("limit_price is required for limit commands.")

    return _parse_positive_decimal(value, "limit_price")
'@ | Set-Content -Path $builderPath -Encoding UTF8
Write-Host "[WRITTEN] $builderPath"

$testPath = ".\scripts\test_manual_execution_command_builder.py"
@'
"""
Validation script for Slice 15E.

This script validates that the manual execution command builder connects:
- simulation package
- audit log
- command model

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require funding, withdrawal, or trading permissions
"""

from __future__ import annotations

import inspect
import tempfile
from pathlib import Path

from tradingagents.execution.manual_execution_command_builder import (
    ManualExecutionCommandBuilderError,
    assert_builder_result_cannot_execute,
    build_manual_execution_command_from_order_intent,
)


def expect_builder_error(label: str, func) -> None:
    try:
        func()
    except ManualExecutionCommandBuilderError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualExecutionCommandBuilderError")


def test_builder_creates_blocked_command_and_audit_record() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        result = build_manual_execution_command_from_order_intent(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_15e_test"},
        )

        assert result.package_id
        assert result.audit_id
        assert result.command_id
        assert result.blocked is True
        assert result.final_status == "simulation_command_blocked_from_live_execution"
        assert result.command_status in {"blocked", "ready_for_review"}
        assert result.secrets_included is False
        assert result.execution_endpoint_called is False
        assert audit_path.exists()

        report = result.safe_report()
        assert report["package_id"] == result.package_id
        assert report["audit_id"] == result.audit_id
        assert report["command_id"] == result.command_id
        assert report["blocked"] is True
        assert report["secrets_included"] is False
        assert report["execution_endpoint_called"] is False

    print("[OK] builder creates blocked command linked to audit record")


def test_permissive_env_still_builds_non_executable_command() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        result = build_manual_execution_command_from_order_intent(
            pair="ETH/CAD",
            side="sell",
            order_type="market",
            volume="0.01",
            audit_file_path=audit_path,
            env={
                "LIVE_TRADING_ENABLED": "true",
                "KILL_SWITCH": "false",
                "MAX_LIVE_TRADE_VALUE": "25",
                "LIVE_TRADING_CONFIRMATION": "I_UNDERSTAND_LIVE_TRADING_RISK",
            },
        )

        assert result.blocked is True
        assert result.final_status == "simulation_command_blocked_from_live_execution"

        expect_builder_error(
            "builder result remains non-executable",
            lambda: assert_builder_result_cannot_execute(result),
        )

    print("[OK] permissive env still creates non-executable command")


def test_invalid_inputs_are_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        expect_builder_error(
            "missing pair rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="",
                side="buy",
                order_type="limit",
                volume="0.1",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "invalid side rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="hold",
                order_type="limit",
                volume="0.1",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "invalid order type rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="buy",
                order_type="stop",
                volume="0.1",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "zero volume rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="buy",
                order_type="limit",
                volume="0",
                limit_price="10",
                audit_file_path=audit_path,
            ),
        )

        expect_builder_error(
            "missing limit price rejected",
            lambda: build_manual_execution_command_from_order_intent(
                pair="BTC/CAD",
                side="buy",
                order_type="limit",
                volume="0.1",
                limit_price=None,
                audit_file_path=audit_path,
            ),
        )


def test_sensitive_values_are_not_exposed_in_safe_report() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "execution_audit.jsonl"

        result = build_manual_execution_command_from_order_intent(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={
                "api_key": "SHOULD_NOT_APPEAR",
                "nested": {"token": "SHOULD_NOT_APPEAR"},
            },
        )

        report_text = str(result.safe_report()).lower()
        assert "should_not_appear" not in report_text
        assert "api_key" not in report_text
        assert "token" not in report_text
        assert "password" not in report_text

    print("[OK] sensitive values are not exposed in builder safe report")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    import tradingagents.execution.manual_execution_command_builder as module

    source = inspect.getsource(module).lower()
    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdraw",
        "withdrawal",
        "funding",
        "deposit",
        "tradebalance",
        "ledgers",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] builder source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15E validation: Manual Execution Command Builder")
    print("=" * 80)

    test_builder_creates_blocked_command_and_audit_record()
    test_permissive_env_still_builds_non_executable_command()
    test_invalid_inputs_are_rejected()
    test_sensitive_values_are_not_exposed_in_safe_report()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15E manual execution command builder validation passed.")
    print("[PASS] Builder connects simulation package, audit record, and command model safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@ | Set-Content -Path $testPath -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

function Add-DocBlockIfMissing {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing documentation file: $Path"
    }

    $content = Get-Content $Path -Raw
    if ($content -notlike "*$Marker*") {
        Add-Content -Path $Path -Value $Block
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

Add-DocBlockIfMissing `
    -Path ".\docs\03_ROADMAP.md" `
    -Marker "Slice 15E — Manual Execution Command Builder" `
    -Block @'

## Slice 15E — Manual Execution Command Builder

Status: Implemented pending validation.

Goal:
Connect the simulation package, audit log, and manual execution command model into one safe builder.

Scope:
- Build a simulation-only package.
- Write/read a safe local audit record.
- Build a non-executable manual execution command linked to package ID and audit ID.
- Produce a safe-to-log build report.
- Keep commands blocked from live execution.

Still forbidden:
- No Kraken live order submission.
- No Kraken live order cancellation.
- No live trading.
- No funding.
- No withdrawals.
- No trading permission requirement.
'@

Add-DocBlockIfMissing `
    -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" `
    -Marker "Slice 15E — Manual Execution Command Builder" `
    -Block @'

## Slice 15E — Manual Execution Command Builder

The manual execution command builder connects the safe simulation and audit layers with the command model.

The builder:
- Creates a simulation package.
- Writes a local JSONL audit record.
- Creates a manual command candidate linked to the simulation package and audit record.
- Produces a safe-to-log report.
- Remains non-executable by design.

This slice does not introduce live exchange execution.
'@

Add-DocBlockIfMissing `
    -Path ".\docs\11_DECISION_LOG.md" `
    -Marker "Slice 15E Decision — Command Builder Must Remain Non-Executable" `
    -Block @'

## Slice 15E Decision — Command Builder Must Remain Non-Executable

Decision:
The manual execution command builder may connect simulation, audit, and command records, but it must not execute anything.

Reason:
Before live execution can exist, the system needs a complete auditable command candidate flow.

Result:
Slice 15E produces safe command candidates only. Commands remain blocked from live execution.
'@

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15E FILES ==="
Get-Item `
    ".\tradingagents\execution\manual_execution_command_builder.py", `
    ".\scripts\test_manual_execution_command_builder.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15E script completed."
