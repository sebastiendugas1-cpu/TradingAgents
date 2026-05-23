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
    except Exception as exc:
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

