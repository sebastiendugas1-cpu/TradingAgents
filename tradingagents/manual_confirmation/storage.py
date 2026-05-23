# ============================ Manual Confirmation Proposal Storage ============================
"""
Local JSONL storage for trade proposals and manual approval records.

This writes local audit files only. It does not execute trades.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tradingagents.manual_confirmation.models import ManualApprovalRecord, TradeProposal


class TradeProposalLog:
    """Append-only local JSONL log for trade proposals and manual approval records."""

    def __init__(self, log_dir: str | Path = ".trade-proposals") -> None:
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.proposals_path = self.log_dir / "proposals.jsonl"
        self.approvals_path = self.log_dir / "approvals.jsonl"

    def append_proposal(self, proposal: TradeProposal) -> Path:
        self._append_json(self.proposals_path, proposal.to_dict())
        return self.proposals_path

    def append_approval(self, record: ManualApprovalRecord) -> Path:
        self._append_json(self.approvals_path, record.to_dict())
        return self.approvals_path

    def read_proposals(self) -> list[dict[str, Any]]:
        return self._read_jsonl(self.proposals_path)

    def read_approvals(self) -> list[dict[str, Any]]:
        return self._read_jsonl(self.approvals_path)

    @staticmethod
    def _append_json(path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, sort_keys=True) + "\n")

    @staticmethod
    def _read_jsonl(path: Path) -> list[dict[str, Any]]:
        if not path.exists():
            return []
        records: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                cleaned = line.strip()
                if cleaned:
                    records.append(json.loads(cleaned))
        return records
