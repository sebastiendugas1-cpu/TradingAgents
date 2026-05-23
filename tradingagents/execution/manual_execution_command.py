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
