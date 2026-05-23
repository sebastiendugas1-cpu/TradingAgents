$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15C SIMULATED EXECUTION AUDIT INTEGRATION ==="

$executionDir = ".\tradingagents\execution"
$scriptsDir = ".\scripts"
$docsDir = ".\docs"

New-Item -ItemType Directory -Force $executionDir | Out-Null
New-Item -ItemType Directory -Force $scriptsDir | Out-Null
New-Item -ItemType Directory -Force $docsDir | Out-Null

$initPath = Join-Path $executionDir "__init__.py"
if (Test-Path $initPath) {
    Write-Host "[SKIPPED] $initPath already exists; preserving current package exports."
} else {
@'
"""
Execution safety package.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] $initPath"
}

$integrationPath = Join-Path $executionDir "simulated_execution_audit_integration.py"
@'
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
'@ | Set-Content -Path $integrationPath -Encoding UTF8
Write-Host "[WRITTEN] $integrationPath"

$testPath = Join-Path $scriptsDir "test_simulated_execution_audit_integration.py"
@'
"""
Validation script for Slice 15C.

This validates integration between:
- Slice 15A manual live order simulation package
- Slice 15B execution audit log

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require trading API permissions
- require funding or restricted account permissions
- print sensitive values
"""

from __future__ import annotations

from tempfile import TemporaryDirectory
from pathlib import Path

from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationInput,
    build_permissive_test_config,
)
from tradingagents.execution.simulated_execution_audit_integration import (
    assert_integration_report_is_safe,
    build_and_audit_simulated_execution_package,
    sanitize_reasons_for_audit,
)


def sample_limit_input() -> ManualLiveOrderSimulationInput:
    return ManualLiveOrderSimulationInput(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume="0.000085168",
        limit_price="100000",
        quote_currency="CAD",
        proposal_id="proposal-15c-test-001",
        approval_id="approval-15c-test-001",
        strategy_name="slice-15c-audit-integration",
        risk_summary="test risk summary",
        operator_note="simulation audit integration only",
    )


def test_default_simulation_package_is_written_to_audit_log() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_audit.jsonl"
        result = build_and_audit_simulated_execution_package(
            sample_limit_input(),
            audit_file_path=audit_file,
        )

        assert result.package.blocked is True
        assert result.package.simulation_only is True
        assert result.audit_record.package_id == result.package.simulation_id
        assert result.audit_record.mode == "simulation"
        assert result.audit_record.pair == "BTC/CAD"
        assert result.audit_record.side == "buy"
        assert result.audit_record.order_type == "limit"
        assert result.audit_record.volume == "0.000085168"
        assert result.audit_record.final_status == "blocked_simulation_only"
        assert result.records_read_back == 1
        assert result.last_record["audit_id"] == result.audit_record.audit_id
        assert result.last_record["package_id"] == result.package.simulation_id
        assert result.last_record["metadata"]["source"] == "slice_15c_simulated_execution_audit_integration"
        assert result.last_record["metadata"]["simulation_only"] is True
        assert result.last_record["secrets_included"] is False
        assert result.execution_endpoint_called is False

        assert_integration_report_is_safe(result.safe_report())

    print("[OK] default simulation package is written to audit log")


def test_permissive_config_still_audits_simulation_only() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_permissive.jsonl"
        result = build_and_audit_simulated_execution_package(
            sample_limit_input(),
            config=build_permissive_test_config(),
            risk_gate_ready=True,
            manual_approval_ready=True,
            audit_file_path=audit_file,
        )

        assert result.package.blocked is True
        assert result.package.simulation_only is True
        assert result.audit_record.risk_status == "ready"
        assert result.audit_record.manual_approval_status == "ready"
        assert result.audit_record.final_status == "blocked_simulation_only"
        assert result.records_read_back == 1
        assert result.execution_endpoint_called is False

    print("[OK] permissive config still audits simulation-only package")


def test_dangerous_environment_is_redacted_in_audit_reasons() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_dangerous_env.jsonl"
        result = build_and_audit_simulated_execution_package(
            sample_limit_input(),
            env={"KRAKEN_WITHDRAW_PERMISSION": "true"},
            audit_file_path=audit_file,
        )

        reason_text = " ".join(result.audit_record.reasons).lower()
        assert "withdraw" not in reason_text
        assert "restricted account-permission term detected" in reason_text
        assert result.package.blocked is True
        assert result.records_read_back == 1

    print("[OK] dangerous environment reason is redacted for audit log")


def test_bad_order_input_is_not_written_as_valid_audit_record() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_bad_input.jsonl"
        bad_input = ManualLiveOrderSimulationInput(
            pair="",
            side="hold",
            order_type="limit",
            volume="0",
            limit_price="",
        )

        try:
            build_and_audit_simulated_execution_package(
                bad_input,
                audit_file_path=audit_file,
            )
        except Exception as exc:  # noqa: BLE001 - validation may fail in either layer
            assert "pair" in str(exc).lower() or "side" in str(exc).lower()
            print(f"[OK] invalid order input cannot become valid audit record: blocked safely ({exc})")
            return

        raise AssertionError("Invalid order input unexpectedly became an audit record")


def test_sanitize_reasons_for_audit_removes_restricted_terms() -> None:
    safe = sanitize_reasons_for_audit(
        (
            "normal blocked reason",
            "restricted permission mentioned in reason",
            "account transfer behavior was blocked",
        )
    )

    joined = " ".join(safe).lower()
    assert "normal blocked reason" in joined
    assert "transfer" not in joined
    assert "restricted account-permission term detected" in joined

    print("[OK] audit reason sanitizer removes restricted terms")


def test_integration_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/simulated_execution_audit_integration.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdrawfunds",
        "depositmethods",
        "wallettransfer",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] integration source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15C validation: Simulated Execution Package Audit Integration")
    print("=" * 80)

    test_default_simulation_package_is_written_to_audit_log()
    test_permissive_config_still_audits_simulation_only()
    test_dangerous_environment_is_redacted_in_audit_reasons()
    test_bad_order_input_is_not_written_as_valid_audit_record()
    test_sanitize_reasons_for_audit_removes_restricted_terms()
    test_integration_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15C simulated execution audit integration validation passed.")
    print("[PASS] Simulation packages are converted into safe local audit records.")
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

    $existing = ""
    if (Test-Path $Path) {
        $existing = Get-Content -Path $Path -Raw
    }

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value ""
        Add-Content -Path $Path -Value $Block
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @'
## Slice 15C — Simulated Execution Package Audit Integration

Status: Implemented pending validation.

Goal:
Connect the Slice 15A manual live order simulation package to the Slice 15B execution audit log.

Scope:
- Builds a manual live order simulation package.
- Converts the package into a safe execution audit record.
- Writes the record to a local JSONL audit file.
- Reads the record back for validation.
- Redacts restricted account-permission terms from audit reasons.
- Does not place or cancel live orders.
- Does not call private execution endpoints.
- Does not require trading, funding, or withdrawal permissions.

Files introduced:
- `tradingagents/execution/simulated_execution_audit_integration.py`
- `scripts/test_simulated_execution_audit_integration.py`

Validation:
- Confirms default simulation package is written to audit log.
- Confirms permissive config still audits simulation-only behavior.
- Confirms dangerous environment terms are redacted in audit reasons.
- Confirms invalid order input cannot become a valid audit record.
- Confirms no secrets are printed.
- Confirms no private execution endpoint names are introduced.
'@

$controlsBlock = @'
## Slice 15C — Simulated Execution Package Audit Integration

Slice 15C connects the simulation package to local audit logging.

The integration performs this safe flow:

`manual order simulation package -> execution audit record -> local JSONL audit file -> read-back validation`

Current restrictions:
- No live order placement.
- No live order cancellation.
- No private execution endpoint calls.
- No funding behavior.
- No withdrawal behavior.
- No trading API permission requirement.

Audit records are local-only and written to ignored output locations unless a test supplies a temporary path.
'@

$decisionBlock = @'
## Slice 15C Decision — Simulated Execution Must Be Auditable Before Live Execution

Decision:
Before any future live execution path is added, the project must prove that simulated manual execution packages can be converted into durable audit records.

Reason:
A future live order path must have an audit trail before it can be considered safe. The audit system needs to capture the decision package, readiness state, risk state, manual approval state, dry-run preview state, and final blocked/ready status.

Result:
Slice 15C integrates the manual live order simulation package with the execution audit log while still blocking all live execution behavior.

This slice intentionally does not add private execution endpoint calls, funding behavior, withdrawal behavior, or automatic live order functionality.
'@

Add-DocBlockIfMissing -Path ".\docs\03_ROADMAP.md" -Marker "Slice 15C — Simulated Execution Package Audit Integration" -Block $roadmapBlock
Add-DocBlockIfMissing -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 15C — Simulated Execution Package Audit Integration" -Block $controlsBlock
Add-DocBlockIfMissing -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 15C Decision" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15C FILES ==="
Get-Item $integrationPath, $testPath, ".\docs\03_ROADMAP.md", ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15C script completed."
