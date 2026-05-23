"""
Simulated execution audit integration.

Slice 15C purpose:
- Connect the Slice 15A manual-live-order simulation package to the Slice 15B
  execution audit log.
- Build a simulation package, convert it into a safe execution audit record,
  write it to a local JSONL audit file, and read it back for verification.
- Keep all behavior simulation-only and safe to log.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT require trading, funding, or restricted account permissions.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Mapping

from tradingagents.execution.execution_audit_log import (
    DEFAULT_AUDIT_DIR,
    ExecutionAuditLogWriter,
    ExecutionAuditRecord,
    create_execution_audit_record,
)
from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationInput,
    ManualLiveOrderSimulationPackage,
    build_manual_live_order_simulation_package,
)
from tradingagents.execution.safety_config import LiveExecutionSafetyConfig


DEFAULT_SIMULATED_AUDIT_FILE = DEFAULT_AUDIT_DIR / "simulated_execution_audit.jsonl"

FORBIDDEN_REASON_TERMS = (
    "withdraw",
    "withdrawal",
    "funding",
    "deposit",
    "transfer",
)


@dataclass(frozen=True)
class SimulatedExecutionAuditIntegrationResult:
    """Result from building and auditing one simulation package."""

    package: ManualLiveOrderSimulationPackage
    audit_record: ExecutionAuditRecord
    audit_file_path: str
    records_read_back: int
    last_record: Mapping[str, Any]
    safe_to_log: bool
    secrets_included: bool
    execution_endpoint_called: bool

    def safe_report(self) -> dict[str, Any]:
        """Return a compact safe-to-log integration report."""

        return {
            "simulation_id": self.package.simulation_id,
            "package_status": self.package.status,
            "package_blocked": self.package.blocked,
            "simulation_only": self.package.simulation_only,
            "audit_id": self.audit_record.audit_id,
            "audit_file_path": self.audit_file_path,
            "records_read_back": self.records_read_back,
            "safe_to_log": self.safe_to_log,
            "secrets_included": self.secrets_included,
            "execution_endpoint_called": self.execution_endpoint_called,
        }


def build_and_audit_simulated_execution_package(
    simulation_input: ManualLiveOrderSimulationInput,
    *,
    config: LiveExecutionSafetyConfig | None = None,
    env: Mapping[str, str] | None = None,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
    audit_file_path: str | Path | None = None,
) -> SimulatedExecutionAuditIntegrationResult:
    """
    Build a Slice 15A simulation package and write a Slice 15B audit record.

    The resulting audit record is local-only and JSONL-based.
    """

    package = build_manual_live_order_simulation_package(
        simulation_input,
        config=config,
        env=env,
        risk_gate_ready=risk_gate_ready,
        manual_approval_ready=manual_approval_ready,
    )

    record = simulation_package_to_audit_record(
        package,
        risk_gate_ready=risk_gate_ready,
        manual_approval_ready=manual_approval_ready,
    )

    writer = ExecutionAuditLogWriter(audit_file_path or DEFAULT_SIMULATED_AUDIT_FILE)
    written_path = writer.append_record(record)
    records = writer.read_records()
    last_record = records[-1] if records else {}

    return SimulatedExecutionAuditIntegrationResult(
        package=package,
        audit_record=record,
        audit_file_path=str(written_path),
        records_read_back=len(records),
        last_record=last_record,
        safe_to_log=True,
        secrets_included=False,
        execution_endpoint_called=False,
    )


def simulation_package_to_audit_record(
    package: ManualLiveOrderSimulationPackage,
    *,
    risk_gate_ready: bool = False,
    manual_approval_ready: bool = False,
) -> ExecutionAuditRecord:
    """Convert a simulation package into a safe execution audit record."""

    order_intent = dict(package.order_intent)
    readiness_component = find_component_status(package, "manual_live_execution_readiness")
    preview_component = find_component_status(package, "kraken_dry_run_order_preview")

    risk_status = "ready" if risk_gate_ready else "blocked"
    manual_status = "ready" if manual_approval_ready else "blocked"

    return create_execution_audit_record(
        package_id=package.simulation_id,
        mode="simulation",
        pair=order_intent.get("pair", ""),
        side=order_intent.get("side", ""),
        order_type=order_intent.get("order_type", ""),
        volume=order_intent.get("volume", ""),
        limit_price=order_intent.get("limit_price", ""),
        readiness_status=readiness_component.get("status", "blocked"),
        risk_status=risk_status,
        manual_approval_status=manual_status,
        dry_run_preview_status=preview_component.get("status", "unknown"),
        final_status=package.status,
        reasons=sanitize_reasons_for_audit(package.blocked_reasons),
        metadata={
            "source": "slice_15c_simulated_execution_audit_integration",
            "simulation_only": package.simulation_only,
            "package_blocked": package.blocked,
            "safe_to_log": package.safe_to_log,
            "component_count": len(package.components),
            "execution_endpoint_called": package.execution_endpoint_called,
        },
    )


def find_component_status(
    package: ManualLiveOrderSimulationPackage,
    component_name: str,
) -> dict[str, Any]:
    """Find one component status by name and return a dictionary."""

    for component in package.components:
        if component.name == component_name:
            return asdict(component)

    return {
        "name": component_name,
        "status": "missing",
        "blocked": True,
        "reasons": (f"Component missing: {component_name}",),
    }


def sanitize_reasons_for_audit(reasons: tuple[str, ...] | list[str]) -> tuple[str, ...]:
    """
    Remove restricted account-permission terms from audit reasons.

    The detailed simulation/readiness package can contain the original blocked reason,
    but the generic audit log intentionally avoids storing restricted-action wording.
    """

    safe_reasons: list[str] = []
    for reason in reasons:
        text = str(reason)
        lowered = text.lower()
        if any(term in lowered for term in FORBIDDEN_REASON_TERMS):
            safe_reasons.append("Restricted account-permission term detected and redacted from audit reason.")
        else:
            safe_reasons.append(text)

    return tuple(dict.fromkeys(safe_reasons))


def assert_integration_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that an integration report contains no obvious sensitive content."""

    report_text = str(report).lower()
    forbidden_terms = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "secret=",
        "token=",
    )

    for term in forbidden_terms:
        if term in report_text:
            raise AssertionError(f"Unsafe integration report contains: {term}")
