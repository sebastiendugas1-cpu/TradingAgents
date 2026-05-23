"""
Validation script for Slice 18C.

This validates the Kraken order translator + disabled adapter skeleton integration.

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

from tradingagents.execution.kraken_live_adapter_skeleton import KrakenLiveAdapterSkeleton
from tradingagents.execution.kraken_order_translation_adapter_integration import (
    assert_integration_report_is_safe,
    build_translate_and_route_to_kraken_skeleton,
)


def test_limit_order_translation_routes_to_disabled_skeleton() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "kraken_translation_adapter.jsonl"

        result = build_translate_and_route_to_kraken_skeleton(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
            metadata={"source": "slice_18c_test"},
        )

        report = result.safe_report()
        payload = report["translation_payload"]

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
        assert report["adapter_report"]["blocked"] is True
        assert report["adapter_report"]["private_endpoint_called"] is False
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] limit order translation routes to disabled skeleton safely")


def test_market_order_translation_routes_to_disabled_skeleton() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "kraken_translation_adapter_market.jsonl"

        result = build_translate_and_route_to_kraken_skeleton(
            pair="SOL/CAD",
            side="sell",
            order_type="market",
            volume=Decimal("0.1"),
            limit_price=None,
            audit_file_path=audit_path,
            metadata={"source": "slice_18c_test"},
        )

        report = result.safe_report()
        payload = report["translation_payload"]

        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert payload["pair"] == "SOL/CAD"
        assert payload["type"] == "sell"
        assert payload["ordertype"] == "market"
        assert payload["volume"] == "0.1"
        assert payload["price"] is None
        assert payload["validate"] is True
        assert report["adapter_report"]["blocked"] is True
        assert audit_path.exists()

        assert_integration_report_is_safe(report)

    print("[OK] market order translation routes to disabled skeleton safely")


def test_custom_skeleton_still_blocks() -> None:
    adapter = KrakenLiveAdapterSkeleton()

    result = build_translate_and_route_to_kraken_skeleton(
        pair="ETH/CAD",
        side="buy",
        order_type="limit",
        volume="0.01",
        limit_price="5000",
        adapter=adapter,
        metadata={"source": "slice_18c_test"},
    )

    report = result.safe_report()

    assert report["blocked"] is True
    assert report["execution_allowed"] is False
    assert report["private_endpoint_called"] is False
    assert adapter.private_endpoint_called is False
    assert report["translation_payload"]["pair"] == "ETH/CAD"

    print("[OK] custom skeleton still blocks")


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
        lambda: build_translate_and_route_to_kraken_skeleton(
            pair="DOGE/CAD",
            side="buy",
            order_type="limit",
            volume="1",
            limit_price="1",
        ),
    )

    expect_error(
        "invalid side rejected",
        lambda: build_translate_and_route_to_kraken_skeleton(
            pair="BTC/CAD",
            side="hold",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
        ),
    )

    expect_error(
        "missing limit price rejected",
        lambda: build_translate_and_route_to_kraken_skeleton(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price=None,
        ),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_order_translation_adapter_integration.py"
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
    print("Slice 18C validation: Kraken Order Translator + Adapter Skeleton Integration")
    print("=" * 80)

    test_limit_order_translation_routes_to_disabled_skeleton()
    test_market_order_translation_routes_to_disabled_skeleton()
    test_custom_skeleton_still_blocks()
    test_invalid_inputs_fail_safely()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 18C Kraken order translator adapter integration validation passed.")
    print("[PASS] Translator routes validate=true payloads through disabled skeleton safely.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
