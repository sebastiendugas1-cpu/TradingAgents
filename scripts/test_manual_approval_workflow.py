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
