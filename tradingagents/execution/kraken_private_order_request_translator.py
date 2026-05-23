"""
Slice 18A Kraken private order request translator.

This module translates a safe ManualExecutionCommand or SubmitOrderRequest
into a Kraken-style order payload for review only.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

The returned payload is not sent anywhere.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any, Mapping

from tradingagents.execution.execution_adapter import SubmitOrderRequest
from tradingagents.execution.manual_execution_command import ManualExecutionCommand


class KrakenOrderRequestTranslationError(ValueError):
    """Raised when a Kraken order request cannot be translated safely."""


@dataclass(frozen=True)
class KrakenPrivateOrderPayload:
    """
    Safe review payload shaped like a future Kraken order request.

    This object is only for local review. It is not executable.
    """

    pair: str
    type: str
    ordertype: str
    volume: str
    price: str | None = None
    validate: bool = True
    userref: str | None = None

    def to_payload(self) -> dict[str, str | bool]:
        payload: dict[str, str | bool] = {
            "pair": self.pair,
            "type": self.type,
            "ordertype": self.ordertype,
            "volume": self.volume,
            "validate": self.validate,
        }

        if self.price is not None:
            payload["price"] = self.price

        if self.userref is not None:
            payload["userref"] = self.userref

        return payload

    def safe_report(self) -> dict[str, Any]:
        return {
            "pair": self.pair,
            "type": self.type,
            "ordertype": self.ordertype,
            "volume": self.volume,
            "price": self.price,
            "validate": self.validate,
            "userref": self.userref,
            "payload_created_for_review_only": True,
            "secrets_included": False,
            "private_endpoint_called": False,
            "execution_allowed": False,
        }


@dataclass(frozen=True)
class KrakenOrderTranslationResult:
    """Safe-to-log result for a Kraken order translation."""

    source: str
    command_id: str
    package_id: str
    audit_id: str
    payload: KrakenPrivateOrderPayload
    warnings: tuple[str, ...] = ()
    secrets_included: bool = False
    private_endpoint_called: bool = False

    def safe_report(self) -> dict[str, Any]:
        payload_report = self.payload.safe_report()

        return {
            "source": self.source,
            "command_id": self.command_id,
            "package_id": self.package_id,
            "audit_id": self.audit_id,
            "payload": payload_report,
            "warning_count": len(self.warnings),
            "warnings": list(self.warnings),
            "payload_created_for_review_only": True,
            "secrets_included": False,
            "private_endpoint_called": False,
            "execution_allowed": False,
        }


SUPPORTED_ORDER_TYPES = {
    "market": "market",
    "limit": "limit",
}

SUPPORTED_SIDES = {
    "buy",
    "sell",
}


def translate_command_to_kraken_private_order_payload(
    command: ManualExecutionCommand,
    *,
    userref: str | None = None,
) -> KrakenOrderTranslationResult:
    """
    Translate a ManualExecutionCommand into a Kraken-style review payload.

    No endpoint is called.
    """

    if not isinstance(command, ManualExecutionCommand):
        raise KrakenOrderRequestTranslationError(
            "command must be a ManualExecutionCommand."
        )

    pair = normalize_pair(command.pair)
    side = normalize_side(command.side)
    ordertype = normalize_order_type(command.order_type)
    volume = normalize_positive_decimal_text(command.volume, "volume")

    price: str | None = None
    if ordertype == "limit":
        if command.limit_price is None:
            raise KrakenOrderRequestTranslationError(
                "limit_price is required for limit orders."
            )
        price = normalize_positive_decimal_text(command.limit_price, "limit_price")

    payload = KrakenPrivateOrderPayload(
        pair=pair,
        type=side,
        ordertype=ordertype,
        volume=volume,
        price=price,
        validate=True,
        userref=normalize_optional_userref(userref),
    )

    return KrakenOrderTranslationResult(
        source="manual_execution_command",
        command_id=command.command_id,
        package_id=command.package_id,
        audit_id=command.audit_id,
        payload=payload,
        warnings=("Payload created for review only; no endpoint call was made.",),
        secrets_included=False,
        private_endpoint_called=False,
    )


def translate_submit_request_to_kraken_private_order_payload(
    request: SubmitOrderRequest,
    *,
    userref: str | None = None,
) -> KrakenOrderTranslationResult:
    """
    Translate a SubmitOrderRequest into a Kraken-style review payload.

    No endpoint is called.
    """

    if not isinstance(request, SubmitOrderRequest):
        raise KrakenOrderRequestTranslationError(
            "request must be a SubmitOrderRequest."
        )

    request.validate()

    return translate_command_to_kraken_private_order_payload(
        request.command,
        userref=userref or request.command.command_id,
    )


def normalize_pair(pair: str) -> str:
    text = str(pair or "").strip().upper()

    if not text:
        raise KrakenOrderRequestTranslationError("pair is required.")

    compact = text.replace("/", "").replace("-", "").replace("_", "")

    allowed = {
        "BTCCAD": "XBT/CAD",
        "XBTCAD": "XBT/CAD",
        "ETHCAD": "ETH/CAD",
        "SOLCAD": "SOL/CAD",
        "ADACAD": "ADA/CAD",
        "XRPCAD": "XRP/CAD",
    }

    if compact not in allowed:
        raise KrakenOrderRequestTranslationError(
            f"Unsupported Kraken order pair for Slice 18A: {pair}"
        )

    return allowed[compact]


def normalize_side(side: str) -> str:
    text = str(side or "").strip().lower()

    if text not in SUPPORTED_SIDES:
        raise KrakenOrderRequestTranslationError("side must be buy or sell.")

    return text


def normalize_order_type(order_type: str) -> str:
    text = str(order_type or "").strip().lower()

    if text not in SUPPORTED_ORDER_TYPES:
        raise KrakenOrderRequestTranslationError(
            "order_type must be market or limit."
        )

    return SUPPORTED_ORDER_TYPES[text]


def normalize_positive_decimal_text(value: str | Decimal, field_name: str) -> str:
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise KrakenOrderRequestTranslationError(
            f"{field_name} must be a valid decimal number."
        ) from exc

    if parsed <= Decimal("0"):
        raise KrakenOrderRequestTranslationError(f"{field_name} must be greater than zero.")

    return format(parsed.normalize(), "f")


def normalize_optional_userref(userref: str | None) -> str | None:
    if userref is None:
        return None

    text = str(userref).strip()

    if not text:
        return None

    safe = "".join(ch for ch in text if ch.isalnum() or ch in ("_", "-"))

    if not safe:
        raise KrakenOrderRequestTranslationError("userref contains no safe characters.")

    return safe[:32]


def assert_translation_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that a translation report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenOrderRequestTranslationError("Translation report includes secrets.")

    if report.get("private_endpoint_called") is not False:
        raise KrakenOrderRequestTranslationError(
            "Translation report indicates a private endpoint call."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenOrderRequestTranslationError(
            "Translation report must not allow execution."
        )

    text = str(report).lower()
    forbidden_secret_terms = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "token=",
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise KrakenOrderRequestTranslationError(
                f"Unsafe secret-like term detected: {term}"
            )
