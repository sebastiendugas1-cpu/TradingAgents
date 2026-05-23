"""
Validation script for Slice 19C.

This validates the payload review + disabled private client shell integration.

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
from tempfile import TemporaryDirectory

from tradingagents.execution.kraken_payload_review_private_client_integration import (
    assert_integration_report_is_safe,
    build_payload_review_and_route_to_private_client_shell,
)
from tradingagents.execution.kraken_private_client_shell import KrakenPrivateClientShell


def test_limit_payload_review_routes_to_private_client_shell() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_private_client.jsonl"

        result = build_payload_review_and_route_to_private_client_shell(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_19c_test"},
        )

        report = result.safe_report()
        payload = report["kraken_payload"]
        private_client_report = report["private_client_report"]

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert report["secrets_included"] is False
        assert payload["pair"] == "XBT/CAD"
        assert payload["type"] == "buy"
        assert payload["ordertype"] == "limit"
        assert payload["volume"] == "0.000085168"
        assert payload["price"] == "100000"
        assert payload["validate"] is True
        assert private_client_report["blocked"] is True
        assert private_client_report["operation"] == "submit_private_order_preview"
        assert private_client_report["private_endpoint_called"] is False
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] limit payload review routes to private client shell safely")


def test_market_payload_review_routes_to_private_client_shell() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_private_client_market.jsonl"

        result = build_payload_review_and_route_to_private_client_shell(
            pair="SOL/CAD",
            side="sell",
            order_type="market",
            volume=Decimal("0.1"),
            limit_price=None,
            audit_file_path=audit_path,
            metadata={"source": "slice_19c_test"},
        )

        report = result.safe_report()
        payload = report["kraken_payload"]

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert payload["pair"] == "SOL/CAD"
        assert payload["type"] == "sell"
        assert payload["ordertype"] == "market"
        assert payload["volume"] == "0.1"
        assert payload["price"] is None
        assert payload["validate"] is True
        assert report["private_client_report"]["blocked"] is True
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] market payload review routes to private client shell safely")


def test_custom_private_client_still_blocks() -> None:
    client = KrakenPrivateClientShell()

    result = build_payload_review_and_route_to_private_client_shell(
        pair="ETH/CAD",
        side="buy",
        order_type="limit",
        volume="0.01",
        limit_price="5000",
        private_client=client,
        metadata={"source": "slice_19c_test"},
    )

    report = result.safe_report()

    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False
    assert client.private_endpoint_called is False
    assert report["kraken_payload"]["pair"] == "ETH/CAD"
    assert report["private_client_report"]["private_endpoint_called"] is False

    print("[OK] custom private client still blocks")


def expect_error(label: str, func) -> None:
    try:
        func()
    except Exception as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected failure")


def test_invalid_inputs_fail_safely() -> None:
    expect_error(
        "unsupported pair rejected",
        lambda: build_payload_review_and_route_to_private_client_shell(
            pair="DOGE/CAD",
            side="buy",
            order_type="limit",
            volume="1",
            limit_price="1",
        ),
    )

    expect_error(
        "invalid side rejected",
        lambda: build_payload_review_and_route_to_private_client_shell(
            pair="BTC/CAD",
            side="hold",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
        ),
    )

    expect_error(
        "missing limit price rejected",
        lambda: build_payload_review_and_route_to_private_client_shell(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price=None,
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_payload_review_private_client_integration.py"
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

    print("[OK] integration source contains no private execution endpoint names")


def main() -> None:
    print("Slice 19C validation: Payload Review + Private Client Shell Integration")
    print("=" * 80)

    test_limit_payload_review_routes_to_private_client_shell()
    test_market_payload_review_routes_to_private_client_shell()
    test_custom_private_client_still_blocks()
    test_invalid_inputs_fail_safely()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 19C payload review private client integration validation passed.")
    print("[PASS] Payload review routes through disabled private client shell safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
