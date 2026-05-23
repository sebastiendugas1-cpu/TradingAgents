$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 18A KRAKEN PRIVATE ORDER REQUEST TRANSLATOR - NO ENDPOINT CALL ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$translatorPath = ".\tradingagents\execution\kraken_private_order_request_translator.py"
$testPath = ".\scripts\test_kraken_private_order_request_translator.py"

$translatorContent = @'
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
'@

$testContent = @'
"""
Validation script for Slice 18A.

This validates the Kraken private order request translator.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path

from tradingagents.execution.execution_adapter import (
    SubmitOrderRequest,
    build_default_blocked_readiness_report,
)
from tradingagents.execution.kraken_private_order_request_translator import (
    KrakenOrderRequestTranslationError,
    assert_translation_report_is_safe,
    translate_command_to_kraken_private_order_payload,
    translate_submit_request_to_kraken_private_order_payload,
)
from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommand,
    ManualExecutionCommandStatus,
)


def make_command(
    *,
    pair: str = "BTC/CAD",
    side: str = "buy",
    order_type: str = "limit",
    volume: Decimal = Decimal("0.000085168"),
    limit_price: Decimal | None = Decimal("100000"),
) -> ManualExecutionCommand:
    return ManualExecutionCommand(
        command_id="cmd_slice_18a_test",
        package_id="sim_slice_18a_test",
        audit_id="audit_slice_18a_test",
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        status=ManualExecutionCommandStatus.BLOCKED,
        metadata={"source": "slice_18a_test"},
    )


def test_limit_command_translates_to_review_payload() -> None:
    command = make_command()

    result = translate_command_to_kraken_private_order_payload(
        command,
        userref="cmd_slice_18a_test",
    )
    report = result.safe_report()
    payload = result.payload.to_payload()

    assert payload["pair"] == "XBT/CAD"
    assert payload["type"] == "buy"
    assert payload["ordertype"] == "limit"
    assert payload["volume"] == "0.000085168"
    assert payload["price"] == "100000"
    assert payload["validate"] is True
    assert payload["userref"] == "cmd_slice_18a_test"

    assert report["payload_created_for_review_only"] is True
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False

    assert_translation_report_is_safe(report)

    print("[OK] limit command translates to safe review payload")


def test_market_command_translates_without_price() -> None:
    command = make_command(
        pair="SOL/CAD",
        side="sell",
        order_type="market",
        volume=Decimal("0.1"),
        limit_price=None,
    )

    result = translate_command_to_kraken_private_order_payload(command)
    payload = result.payload.to_payload()
    report = result.safe_report()

    assert payload["pair"] == "SOL/CAD"
    assert payload["type"] == "sell"
    assert payload["ordertype"] == "market"
    assert payload["volume"] == "0.1"
    assert "price" not in payload
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False

    assert_translation_report_is_safe(report)

    print("[OK] market command translates without price")


def test_submit_request_translates_to_review_payload() -> None:
    command = make_command(pair="ETH/CAD", volume=Decimal("0.01"), limit_price=Decimal("5000"))
    readiness = build_default_blocked_readiness_report()

    request = SubmitOrderRequest(
        request_id="submit_slice_18a_test",
        command=command,
        readiness_report=readiness,
        metadata={"source": "slice_18a_test"},
    )

    result = translate_submit_request_to_kraken_private_order_payload(request)
    payload = result.payload.to_payload()
    report = result.safe_report()

    assert payload["pair"] == "ETH/CAD"
    assert payload["type"] == "buy"
    assert payload["ordertype"] == "limit"
    assert payload["volume"] == "0.01"
    assert payload["price"] == "5000"
    assert payload["validate"] is True
    assert payload["userref"] == "cmd_slice_18a_test"
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False

    assert_translation_report_is_safe(report)

    print("[OK] submit request translates to safe review payload")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenOrderRequestTranslationError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenOrderRequestTranslationError")


def test_invalid_translation_inputs_are_rejected() -> None:
    expect_error(
        "unsupported pair rejected",
        lambda: translate_command_to_kraken_private_order_payload(
            make_command(pair="DOGE/CAD")
        ),
    )

    expect_error(
        "limit order missing price rejected",
        lambda: translate_command_to_kraken_private_order_payload(
            make_command(order_type="limit", limit_price=None)
        ),
    )

    expect_error(
        "unsafe userref rejected",
        lambda: translate_command_to_kraken_private_order_payload(
            make_command(),
            userref="!!!",
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_order_request_translator.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdraw",
        "withdrawal",
        "deposit",
        "funding",
        "tradebalance",
        "ledgers",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] translator source contains no private execution endpoint names")


def main() -> None:
    print("Slice 18A validation: Kraken Private Order Request Translator")
    print("=" * 80)

    test_limit_command_translates_to_review_payload()
    test_market_command_translates_without_price()
    test_submit_request_translates_to_review_payload()
    test_invalid_translation_inputs_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 18A Kraken private order request translator validation passed.")
    print("[PASS] Translator creates review payloads only and calls no endpoint.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $translatorPath -Value $translatorContent -Encoding UTF8
Write-Host "[WRITTEN] $translatorPath"

Set-Content -Path $testPath -Value $testContent -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

function Add-DocBlockOnce {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing doc file: $Path"
    }

    $existing = Get-Content $Path -Raw

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`n$Block" -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @"
## Slice 18A — Kraken Private Order Request Translator, No Endpoint Call

Status: Implemented pending validation.

Goal:
Translate safe manual execution commands into Kraken-style order payloads for review only.

Scope:
- Create `tradingagents/execution/kraken_private_order_request_translator.py`.
- Create `scripts/test_kraken_private_order_request_translator.py`.
- Translate `ManualExecutionCommand` to a Kraken-style review payload.
- Translate `SubmitOrderRequest` to a Kraken-style review payload.
- Validate pair/side/order type/volume/price.
- Force payloads to `validate=true`.
- Validate reports are safe to log.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 18A — Kraken Private Order Request Translator

A Kraken-style order request translator has been added for review-only payload generation.

The translator:
- accepts safe command/request objects
- validates trading pair, side, order type, volume, and price
- creates a Kraken-style payload with validate=true
- produces safe reports
- does not call Kraken
- does not enable execution
"@

$decisionBlock = @"
## Slice 18A Decision — Translate Future Kraken Payloads Before Endpoint Work

Decision:
Add a Kraken-style private order request translator before any future private endpoint implementation.

Reason:
Before any future live-capable code can be considered, the exact order payload shape must be reviewed and tested without calling Kraken.

Result:
The project can now generate safe review-only Kraken-style order payloads from command/request objects.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 18A — Kraken Private Order Request Translator, No Endpoint Call" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 18A — Kraken Private Order Request Translator" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 18A Decision — Translate Future Kraken Payloads Before Endpoint Work" -Block $decisionBlock

python -m py_compile $translatorPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 18A FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_private_order_request_translator.py", `
    ".\scripts\test_kraken_private_order_request_translator.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 18A script completed."
