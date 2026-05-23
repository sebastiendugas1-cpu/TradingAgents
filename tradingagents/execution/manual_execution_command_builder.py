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
This module does NOT require private account-changing permissions.
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
    ExecutionAuditLogWriter,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandError,
    ManualExecutionCommandStatus,
)
from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationError,
    ManualLiveOrderSimulationInput,
    build_manual_live_order_simulation_package,
)
from tradingagents.execution.simulated_execution_audit_integration import (
    build_and_audit_simulated_execution_package,
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

    simulation_input = ManualLiveOrderSimulationInput(
        pair=pair_value,
        side=side_value,
        order_type=order_type_value,
        volume=str(volume_value),
        limit_price=str(limit_price_value) if limit_price_value is not None else None,
        quote_currency="CAD",
        proposal_id=str((metadata or {}).get("proposal_id", "manual-command-builder")),
        approval_id=str((metadata or {}).get("approval_id", "manual-command-builder")),
        strategy_name=str((metadata or {}).get("strategy_name", "manual_execution_command_builder")),
        risk_summary=str((metadata or {}).get("risk_summary", "simulation-only command builder")),
        operator_note=str((metadata or {}).get("operator_note", "Slice 15E non-executable command build")),
    )

    simulation_package = build_manual_live_order_simulation_package(
        simulation_input,
        env=env,
    )

    audit_result = build_and_audit_simulated_execution_package(
        simulation_input,
        env=env,
        audit_file_path=path,
    )

    audit_record = _extract_audit_record(audit_result)
    audit_id = _extract_audit_id(audit_record, audit_result)

    command_status = ManualExecutionCommandStatus.BLOCKED if getattr(simulation_package, "blocked", True) else ManualExecutionCommandStatus.READY_FOR_REVIEW

    command = ManualExecutionCommand(
        command_id=f"cmd_{uuid4().hex}",
        package_id=str(getattr(simulation_package, "simulation_id", "")),
        audit_id=audit_id,
        pair=pair_value,
        side=side_value,
        order_type=order_type_value,
        volume=volume_value,
        limit_price=limit_price_value,
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
        package_id=str(getattr(simulation_package, "simulation_id", "")),
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

    audit_result = build_and_audit_simulated_execution_package(
        package=package,
        audit_file_path=Path(audit_file_path),
    )

    audit_record = _extract_audit_record(audit_result)
    audit_id = _extract_audit_id(audit_record, audit_result)

    package_id = str(getattr(package, "simulation_id", getattr(package, "package_id", "")))
    if not package_id:
        raise ManualExecutionCommandBuilderError("package_id is required.")

    pair = _require_text(str(getattr(package, "pair", "")), "pair")
    side = _normalize_side(str(getattr(package, "side", "")))
    order_type = _normalize_order_type(str(getattr(package, "order_type", "")))
    volume = _parse_positive_decimal(getattr(package, "volume", ""), "volume")
    limit_price = getattr(package, "limit_price", None)
    parsed_limit_price = _parse_limit_price(order_type, limit_price)

    command_status = ManualExecutionCommandStatus.BLOCKED if getattr(package, "blocked", True) else ManualExecutionCommandStatus.READY_FOR_REVIEW

    command = ManualExecutionCommand(
        command_id=f"cmd_{uuid4().hex}",
        package_id=package_id,
        audit_id=audit_id,
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=parsed_limit_price,
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













