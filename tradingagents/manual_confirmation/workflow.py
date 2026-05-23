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
