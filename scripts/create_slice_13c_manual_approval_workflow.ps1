# ============================ Slice 13C - Manual Approval Workflow ============================
# Purpose:
# Creates a safe local manual-approval workflow for trade proposals.
#
# Safety:
# - No Kraken order placement
# - No Kraken canceling
# - No live trading
# - No funding
# - No withdrawals
# - Local approval/rejection records only

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$WorkflowDir = Join-Path $ProjectRoot "tradingagents\manual_confirmation"
$ScriptsDir = Join-Path $ProjectRoot "scripts"
$DocsDir = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $WorkflowDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# ============================ workflow.py ============================

Write-TextFile (Join-Path $WorkflowDir "workflow.py") @'
# ============================ Manual Approval Workflow ============================
"""
Manual approval workflow for trade proposals.

This module is deliberately local and safe:
- It records approval/rejection decisions.
- It validates explicit confirmation text.
- It never places Kraken orders.
- It never cancels Kraken orders.
- It never calls private exchange APIs.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import UTC, datetime
import json
from pathlib import Path
from typing import Any
from uuid import uuid4

from tradingagents.manual_confirmation.models import TradeApprovalStatus


class ManualApprovalWorkflowError(ValueError):
    """Raised when a manual approval workflow action is invalid."""


@dataclass(frozen=True)
class ManualApprovalWorkflowRecord:
    """Local audit record for one manual approval or rejection decision."""

    record_id: str
    proposal_id: str
    previous_status: TradeApprovalStatus
    new_status: TradeApprovalStatus
    decision: str
    approved_by: str
    confirmation_text: str
    notes: str
    timestamp_utc: str

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["previous_status"] = self.previous_status.value
        data["new_status"] = self.new_status.value
        return data


class ManualApprovalWorkflow:
    """Safe local workflow for approving or rejecting trade proposals."""

    def __init__(self, *, log_dir: str | Path = ".manual-confirmation/approvals") -> None:
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)

    def approve(
        self,
        proposal: Any,
        *,
        approved_by: str,
        confirmation_text: str,
        notes: str = "",
    ) -> ManualApprovalWorkflowRecord:
        """Approve a proposal after exact manual confirmation.

        Required confirmation text:

            APPROVE <proposal_id>
        """

        return self._record_decision(
            proposal,
            new_status=TradeApprovalStatus.APPROVED,
            decision="approve",
            approved_by=approved_by,
            confirmation_text=confirmation_text,
            notes=notes,
            required_prefix="APPROVE",
        )

    def reject(
        self,
        proposal: Any,
        *,
        rejected_by: str,
        confirmation_text: str,
        notes: str = "",
    ) -> ManualApprovalWorkflowRecord:
        """Reject a proposal after exact manual confirmation.

        Required confirmation text:

            REJECT <proposal_id>
        """

        return self._record_decision(
            proposal,
            new_status=TradeApprovalStatus.REJECTED,
            decision="reject",
            approved_by=rejected_by,
            confirmation_text=confirmation_text,
            notes=notes,
            required_prefix="REJECT",
        )

    def list_records(self) -> list[ManualApprovalWorkflowRecord]:
        """Load all local approval workflow records from disk."""

        records: list[ManualApprovalWorkflowRecord] = []

        for path in sorted(self.log_dir.glob("*.json")):
            data = json.loads(path.read_text(encoding="utf-8"))
            records.append(
                ManualApprovalWorkflowRecord(
                    record_id=str(data["record_id"]),
                    proposal_id=str(data["proposal_id"]),
                    previous_status=TradeApprovalStatus(data["previous_status"]),
                    new_status=TradeApprovalStatus(data["new_status"]),
                    decision=str(data["decision"]),
                    approved_by=str(data["approved_by"]),
                    confirmation_text=str(data["confirmation_text"]),
                    notes=str(data.get("notes", "")),
                    timestamp_utc=str(data["timestamp_utc"]),
                )
            )

        return records

    def _record_decision(
        self,
        proposal: Any,
        *,
        new_status: TradeApprovalStatus,
        decision: str,
        approved_by: str,
        confirmation_text: str,
        notes: str,
        required_prefix: str,
    ) -> ManualApprovalWorkflowRecord:
        proposal_id = _proposal_id(proposal)
        previous_status = _proposal_status(proposal)

        if previous_status != TradeApprovalStatus.PENDING:
            raise ManualApprovalWorkflowError(
                f"Only pending proposals can be approved/rejected. Current status: {previous_status.value}"
            )

        if not approved_by.strip():
            raise ManualApprovalWorkflowError("approved_by/rejected_by cannot be blank.")

        expected_confirmation = f"{required_prefix} {proposal_id}"
        if confirmation_text.strip() != expected_confirmation:
            raise ManualApprovalWorkflowError(
                f"Confirmation text must exactly match: {expected_confirmation!r}"
            )

        record = ManualApprovalWorkflowRecord(
            record_id=str(uuid4()),
            proposal_id=proposal_id,
            previous_status=previous_status,
            new_status=new_status,
            decision=decision,
            approved_by=approved_by.strip(),
            confirmation_text=confirmation_text.strip(),
            notes=notes.strip(),
            timestamp_utc=datetime.now(UTC).isoformat(),
        )

        self._write_record(record)
        return record

    def _write_record(self, record: ManualApprovalWorkflowRecord) -> Path:
        path = self.log_dir / f"{record.timestamp_utc.replace(':', '-')}_{record.record_id}.json"
        path.write_text(json.dumps(record.to_dict(), indent=2, sort_keys=True), encoding="utf-8")
        return path


def _proposal_id(proposal: Any) -> str:
    for attr_name in ("proposal_id", "id"):
        value = getattr(proposal, attr_name, None)
        if value:
            return str(value)

    if isinstance(proposal, dict):
        for key in ("proposal_id", "id"):
            value = proposal.get(key)
            if value:
                return str(value)

    raise ManualApprovalWorkflowError("Proposal must expose proposal_id or id.")


def _proposal_status(proposal: Any) -> TradeApprovalStatus:
    for attr_name in ("approval_status", "status"):
        value = getattr(proposal, attr_name, None)
        if value is not None:
            return _coerce_status(value)

    if isinstance(proposal, dict):
        for key in ("approval_status", "status"):
            value = proposal.get(key)
            if value is not None:
                return _coerce_status(value)

    raise ManualApprovalWorkflowError("Proposal must expose approval_status or status.")


def _coerce_status(value: Any) -> TradeApprovalStatus:
    if isinstance(value, TradeApprovalStatus):
        return value

    try:
        return TradeApprovalStatus(str(value))
    except ValueError as exc:
        raise ManualApprovalWorkflowError(f"Unsupported proposal status: {value!r}") from exc
'@

# ============================ update __init__.py ============================

$InitPath = Join-Path $WorkflowDir "__init__.py"
$ExistingInit = ""
if (Test-Path $InitPath) {
    $ExistingInit = Get-Content $InitPath -Raw
}

if ($ExistingInit -notmatch "ManualApprovalWorkflow") {
    Add-Content -Path $InitPath -Encoding UTF8 -Value @'

from tradingagents.manual_confirmation.workflow import (
    ManualApprovalWorkflow,
    ManualApprovalWorkflowError,
    ManualApprovalWorkflowRecord,
)
'@
}

$ExistingInit = Get-Content $InitPath -Raw
if ($ExistingInit -notmatch '"ManualApprovalWorkflow"') {
    Add-Content -Path $InitPath -Encoding UTF8 -Value @'

try:
    __all__
except NameError:
    __all__ = []

__all__ += [
    "ManualApprovalWorkflow",
    "ManualApprovalWorkflowError",
    "ManualApprovalWorkflowRecord",
]
'@
}

# ============================ validation test ============================

Write-TextFile (Join-Path $ScriptsDir "test_manual_approval_workflow.py") @'
# ============================ Slice 13C Validation - Manual Approval Workflow ============================

from __future__ import annotations

from dataclasses import dataclass
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.manual_confirmation import (  # noqa: E402
    ManualApprovalWorkflow,
    ManualApprovalWorkflowError,
    TradeApprovalStatus,
)


@dataclass(frozen=True)
class FakeProposal:
    proposal_id: str
    approval_status: TradeApprovalStatus
    asset: str = "BTC/USD"


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 13C manual approval workflow validation...")

    test_log_dir = PROJECT_ROOT / ".manual-confirmation-test" / "approvals"
    if test_log_dir.exists():
        shutil.rmtree(test_log_dir.parent)

    workflow = ManualApprovalWorkflow(log_dir=test_log_dir)

    pending = FakeProposal(
        proposal_id="proposal-btc-001",
        approval_status=TradeApprovalStatus.PENDING,
    )

    approval = workflow.approve(
        pending,
        approved_by="operator",
        confirmation_text="APPROVE proposal-btc-001",
        notes="Approved for workflow validation only.",
    )

    assert_equal(approval.previous_status, TradeApprovalStatus.PENDING, "approval previous status")
    assert_equal(approval.new_status, TradeApprovalStatus.APPROVED, "approval new status")
    assert_equal(approval.decision, "approve", "approval decision")
    assert_true(test_log_dir.exists(), "approval log folder exists")

    rejection = workflow.reject(
        pending,
        rejected_by="operator",
        confirmation_text="REJECT proposal-btc-001",
        notes="Rejected for workflow validation only.",
    )

    assert_equal(rejection.previous_status, TradeApprovalStatus.PENDING, "rejection previous status")
    assert_equal(rejection.new_status, TradeApprovalStatus.REJECTED, "rejection new status")
    assert_equal(rejection.decision, "reject", "rejection decision")

    records = workflow.list_records()
    assert_equal(len(records), 2, "workflow record count")

    try:
        workflow.approve(
            pending,
            approved_by="operator",
            confirmation_text="APPROVE WRONG-ID",
        )
        raise AssertionError("Incorrect confirmation text should have failed.")
    except ManualApprovalWorkflowError:
        print("[OK] incorrect confirmation text rejected")

    try:
        workflow.approve(
            FakeProposal("proposal-btc-002", TradeApprovalStatus.APPROVED),
            approved_by="operator",
            confirmation_text="APPROVE proposal-btc-002",
        )
        raise AssertionError("Non-pending proposal should have failed.")
    except ManualApprovalWorkflowError:
        print("[OK] non-pending proposal rejected")

    try:
        workflow.approve(
            pending,
            approved_by="",
            confirmation_text="APPROVE proposal-btc-001",
        )
        raise AssertionError("Blank approver should have failed.")
    except ManualApprovalWorkflowError:
        print("[OK] blank approver rejected")

    record_text = str([record.to_dict() for record in records]).lower()
    assert_true("api_key" not in record_text, "records do not mention API keys")
    assert_true("secret" not in record_text, "records do not mention secrets")
    assert_true("live_trade" not in record_text, "records do not mention live trading")
    assert_true("place_order" not in record_text, "records do not mention order placement")

    shutil.rmtree(test_log_dir.parent)

    print("Manual approval workflow validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# ============================ docs updates ============================

$DecisionLogPath = Join-Path $DocsDir "11_DECISION_LOG.md"
if (Test-Path $DecisionLogPath) {
    $DecisionLog = Get-Content $DecisionLogPath -Raw
    if ($DecisionLog -notmatch "Slice 13C") {
        Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 13C Manual Approval Workflow

Decision:

Created a local manual approval workflow for trade proposals.

Key points:

- Approval requires exact confirmation text: `APPROVE <proposal_id>`.
- Rejection requires exact confirmation text: `REJECT <proposal_id>`.
- Approval/rejection records are written locally.
- The workflow does not place Kraken orders.
- The workflow does not cancel Kraken orders.
- The workflow does not call private exchange APIs.
- The workflow is still pre-execution only.
'@
    }
}

$RoadmapPath = Join-Path $DocsDir "03_ROADMAP.md"
if (Test-Path $RoadmapPath) {
    $Roadmap = Get-Content $RoadmapPath -Raw
    if ($Roadmap -notmatch "Slice 13C — Manual Approval Workflow") {
        Add-Content -Path $RoadmapPath -Encoding UTF8 -Value @'

## Slice 13C — Manual Approval Workflow

Status: Complete after validation and commit.

Goal:

Create a local manual approval/rejection workflow for pending trade proposals.

Deliverables:

- `tradingagents/manual_confirmation/workflow.py`
- `scripts/test_manual_approval_workflow.py`

Safety:

- No Kraken order placement.
- No Kraken cancellation.
- No live trading.
- No funding.
- No withdrawals.
- Local approval records only.
'@
    }
}

# ============================ .gitignore ============================

$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
if (Test-Path $GitIgnorePath) {
    $GitIgnoreText = Get-Content $GitIgnorePath -Raw
} else {
    $GitIgnoreText = ""
}

if ($GitIgnoreText -notmatch "\.manual-confirmation/") {
    Add-Content -Path $GitIgnorePath -Encoding UTF8 -Value @'

# Local manual confirmation records
.manual-confirmation/
.manual-confirmation-test/
'@
}

# ============================ validation ============================

Write-Host "=== SLICE 13C FILES CREATED ==="
Write-Host ""

Write-Host "=== RUNNING SLICE 13C VALIDATION ==="
python .\scripts\test_manual_approval_workflow.py

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "Slice 13C script completed."
Write-Host ""

Get-ChildItem .\tradingagents\manual_confirmation | Select-Object Name,Length,LastWriteTime
