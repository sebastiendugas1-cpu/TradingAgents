"""
Execution audit logging.

Slice 15B purpose:
- Create a durable, safe-to-log audit record for every future simulated or live
  execution decision.
- Support JSONL audit files for local review and later reconciliation.
- Redact secret-like values before records are written.
- Keep the implementation independent from any broker/exchange execution endpoint.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT require trading, funding, or withdrawal permissions.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping


DEFAULT_AUDIT_DIR = Path(".chatGPT-output") / "execution_audit"
DEFAULT_AUDIT_FILE_NAME = "execution_audit.jsonl"

SECRET_MARKERS = (
    "api_key",
    "api secret",
    "api_secret",
    "kraken_api_key",
    "kraken_api_secret",
    "password",
    "private key",
    "token",
)

FORBIDDEN_AUDIT_ACTION_TERMS = (
    "withdraw",
    "withdrawal",
    "funding",
    "deposit",
    "transfer",
)


class ExecutionAuditLogError(ValueError):
    """Raised when an execution audit record or audit log path is invalid."""


@dataclass(frozen=True)
class ExecutionAuditRecord:
    """Safe audit record for simulated or future live execution decisions."""

    audit_id: str
    timestamp_utc: str
    package_id: str
    mode: str
    pair: str
    side: str
    order_type: str
    volume: str
    limit_price: str
    readiness_status: str
    risk_status: str
    manual_approval_status: str
    dry_run_preview_status: str
    final_status: str
    reasons: tuple[str, ...] = field(default_factory=tuple)
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Convert the record to a JSON-safe dictionary."""

        return {
            "audit_id": self.audit_id,
            "timestamp_utc": self.timestamp_utc,
            "package_id": self.package_id,
            "mode": self.mode,
            "pair": self.pair,
            "side": self.side,
            "order_type": self.order_type,
            "volume": self.volume,
            "limit_price": self.limit_price,
            "readiness_status": self.readiness_status,
            "risk_status": self.risk_status,
            "manual_approval_status": self.manual_approval_status,
            "dry_run_preview_status": self.dry_run_preview_status,
            "final_status": self.final_status,
            "reasons": list(self.reasons),
            "metadata": sanitize_for_audit(self.metadata),
            "secrets_included": False,
        }

    def safe_report(self) -> dict[str, Any]:
        """Return a safe, compact report for console output or logs."""

        return {
            "audit_id": self.audit_id,
            "package_id": self.package_id,
            "mode": self.mode,
            "pair": self.pair,
            "side": self.side,
            "order_type": self.order_type,
            "final_status": self.final_status,
            "reason_count": len(self.reasons),
            "secrets_included": False,
        }


class ExecutionAuditLogWriter:
    """Append-only JSONL writer for execution audit records."""

    def __init__(self, audit_file_path: str | os.PathLike[str] | None = None) -> None:
        self.audit_file_path = Path(audit_file_path) if audit_file_path else DEFAULT_AUDIT_DIR / DEFAULT_AUDIT_FILE_NAME
        self._validate_path()

    def _validate_path(self) -> None:
        path_text = str(self.audit_file_path).replace("\\", "/")

        if ".env" in path_text:
            raise ExecutionAuditLogError("Audit log path cannot target .env files.")

        if self.audit_file_path.suffix.lower() not in {".jsonl", ".log"}:
            raise ExecutionAuditLogError("Audit log path must end with .jsonl or .log.")

    def append_record(self, record: ExecutionAuditRecord) -> Path:
        """Append a record to the JSONL audit log and return the written path."""

        payload = record.to_dict()
        serialized = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        validate_no_secrets(serialized)

        self.audit_file_path.parent.mkdir(parents=True, exist_ok=True)

        with self.audit_file_path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(serialized)
            handle.write("\n")

        return self.audit_file_path

    def read_records(self) -> list[dict[str, Any]]:
        """Read all JSONL records from the audit file."""

        if not self.audit_file_path.exists():
            return []

        records: list[dict[str, Any]] = []
        with self.audit_file_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                stripped = line.strip()
                if stripped:
                    records.append(json.loads(stripped))

        return records


def create_execution_audit_record(
    *,
    package_id: str,
    mode: str,
    pair: str,
    side: str,
    order_type: str,
    volume: str | Decimal | int | float,
    limit_price: str | Decimal | int | float | None,
    readiness_status: str,
    risk_status: str,
    manual_approval_status: str,
    dry_run_preview_status: str,
    final_status: str,
    reasons: tuple[str, ...] | list[str] | None = None,
    metadata: Mapping[str, Any] | None = None,
    timestamp_utc: str | None = None,
) -> ExecutionAuditRecord:
    """Create and validate a safe execution audit record."""

    safe_reasons = tuple(str(reason) for reason in (reasons or ()))
    safe_metadata = sanitize_for_audit(metadata or {})

    normalized = {
        "package_id": require_text(package_id, "package_id"),
        "mode": require_text(mode, "mode"),
        "pair": require_text(pair, "pair"),
        "side": require_text(side, "side").lower(),
        "order_type": require_text(order_type, "order_type").lower(),
        "volume": normalize_number_text(volume, "volume"),
        "limit_price": normalize_optional_number_text(limit_price),
        "readiness_status": require_text(readiness_status, "readiness_status"),
        "risk_status": require_text(risk_status, "risk_status"),
        "manual_approval_status": require_text(manual_approval_status, "manual_approval_status"),
        "dry_run_preview_status": require_text(dry_run_preview_status, "dry_run_preview_status"),
        "final_status": require_text(final_status, "final_status"),
    }

    if normalized["side"] not in {"buy", "sell"}:
        raise ExecutionAuditLogError("side must be buy or sell.")

    if normalized["mode"] not in {"simulation", "paper", "manual_live_candidate", "live_blocked"}:
        raise ExecutionAuditLogError("mode is not an allowed audit mode.")

    validate_no_forbidden_audit_terms(normalized.values())
    validate_no_forbidden_audit_terms(safe_reasons)
    validate_no_secrets(json.dumps(safe_metadata, sort_keys=True, default=str))

    timestamp = timestamp_utc or datetime.now(UTC).isoformat()
    audit_id = build_audit_id(timestamp=timestamp, values=normalized, reasons=safe_reasons)

    return ExecutionAuditRecord(
        audit_id=audit_id,
        timestamp_utc=timestamp,
        package_id=normalized["package_id"],
        mode=normalized["mode"],
        pair=normalized["pair"],
        side=normalized["side"],
        order_type=normalized["order_type"],
        volume=normalized["volume"],
        limit_price=normalized["limit_price"],
        readiness_status=normalized["readiness_status"],
        risk_status=normalized["risk_status"],
        manual_approval_status=normalized["manual_approval_status"],
        dry_run_preview_status=normalized["dry_run_preview_status"],
        final_status=normalized["final_status"],
        reasons=safe_reasons,
        metadata=safe_metadata,
    )


def build_audit_id(*, timestamp: str, values: Mapping[str, str], reasons: tuple[str, ...]) -> str:
    """Build a deterministic short audit ID from safe record content."""

    payload = json.dumps(
        {
            "timestamp": timestamp,
            "values": dict(values),
            "reasons": list(reasons),
        },
        sort_keys=True,
        ensure_ascii=False,
    )
    return "audit_" + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:24]


def require_text(value: str, field_name: str) -> str:
    """Require a non-empty text value."""

    normalized = str(value).strip()
    if not normalized:
        raise ExecutionAuditLogError(f"{field_name} is required.")
    return normalized


def normalize_number_text(value: str | Decimal | int | float, field_name: str) -> str:
    """Normalize a required numeric field to plain text."""

    text = str(value).strip()
    if not text:
        raise ExecutionAuditLogError(f"{field_name} is required.")

    try:
        parsed = Decimal(text)
    except Exception as exc:  # noqa: BLE001 - strict conversion wrapper
        raise ExecutionAuditLogError(f"{field_name} must be numeric.") from exc

    if parsed <= Decimal("0"):
        raise ExecutionAuditLogError(f"{field_name} must be greater than zero.")

    return format(parsed, "f")


def normalize_optional_number_text(value: str | Decimal | int | float | None) -> str:
    """Normalize an optional numeric value to text."""

    if value is None or str(value).strip() == "":
        return ""

    return normalize_number_text(value, "limit_price")


def sanitize_for_audit(value: Any) -> Any:
    """Recursively sanitize metadata before audit logging."""

    if isinstance(value, Mapping):
        sanitized: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if contains_secret_marker(key_text):
                sanitized[key_text] = "[REDACTED]"
            else:
                sanitized[key_text] = sanitize_for_audit(item)
        return sanitized

    if isinstance(value, (list, tuple, set)):
        return [sanitize_for_audit(item) for item in value]

    text = str(value)
    if contains_secret_marker(text):
        return "[REDACTED]"

    return value


def validate_no_secrets(text: str) -> None:
    """Reject text that appears to contain secret-like values."""

    lowered = text.lower()
    for marker in SECRET_MARKERS:
        if marker in lowered and "[redacted]" not in lowered:
            raise ExecutionAuditLogError(f"Secret-like value rejected from audit log: {marker}")


def validate_no_forbidden_audit_terms(values: Any) -> None:
    """Reject funding/withdrawal terms in audit action fields and reasons."""

    joined = " ".join(str(value) for value in values).lower()
    for term in FORBIDDEN_AUDIT_ACTION_TERMS:
        if term in joined:
            raise ExecutionAuditLogError(f"Forbidden audit action term rejected: {term}")


def contains_secret_marker(text: str) -> bool:
    """Return whether text contains a secret-like marker."""

    lowered = text.lower()
    return any(marker in lowered for marker in SECRET_MARKERS)


