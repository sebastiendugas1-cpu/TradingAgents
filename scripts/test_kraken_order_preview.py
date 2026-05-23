# ============================ Slice 13E Validation - Kraken Order Preview ============================

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.execution import (  # noqa: E402
    KrakenOrderPreviewError,
    OrderPreviewStatus,
    create_kraken_order_preview,
)


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 13E Kraken order preview validation...")

    approved_proposal = SimpleNamespace(
        proposal_id="proposal-001",
        asset="BTC/USD",
        side="buy",
        order_type="limit",
        volume=0.001,
        limit_price=75000.0,
        estimated_value=75.0,
        approval_status="approved",
    )

    passed_risk_gate = SimpleNamespace(
        passed=True,
        decision="approved_for_dry_run",
        reasons=("All configured risk gates passed.",),
    )

    preview = create_kraken_order_preview(
        proposal=approved_proposal,
        risk_gate_result=passed_risk_gate,
        kraken_pair="XXBTZUSD",
    )

    assert_equal(preview.status, OrderPreviewStatus.DRY_RUN_ONLY, "preview status")
    assert_true(preview.dry_run_only, "preview is dry-run only")
    assert_true(preview.is_previewable, "previewable payload created")
    assert_equal(preview.asset, "BTC/USD", "preview asset")
    assert_equal(preview.kraken_pair, "XXBTZUSD", "Kraken pair")
    assert_equal(preview.payload["pair"], "XXBTZUSD", "payload pair")
    assert_equal(preview.payload["type"], "buy", "payload side")
    assert_equal(preview.payload["ordertype"], "limit", "payload order type")
    assert_equal(preview.payload["volume"], "0.001", "payload volume")
    assert_equal(preview.payload["price"], "75000", "payload price")
    assert_equal(preview.payload["validate"], "true", "payload validate flag")
    assert_equal(preview.payload["dry_run_only"], "true", "payload dry-run flag")
    assert_equal(preview.estimated_notional, 75.0, "estimated notional")

    blocked_risk = SimpleNamespace(
        passed=False,
        decision="blocked",
        reasons=("Risk score too high.",),
    )

    blocked_preview = create_kraken_order_preview(
        proposal=approved_proposal,
        risk_gate_result=blocked_risk,
        kraken_pair="XXBTZUSD",
    )

    assert_equal(blocked_preview.status, OrderPreviewStatus.BLOCKED, "blocked preview status")
    assert_true(blocked_preview.is_blocked, "blocked preview is blocked")
    assert_equal(blocked_preview.payload, {}, "blocked preview has no payload")

    pending_proposal = SimpleNamespace(
        proposal_id="proposal-002",
        asset="ETH/USD",
        side="sell",
        order_type="market",
        volume=0.01,
        estimated_value=30.0,
        approval_status="pending",
    )

    pending_preview = create_kraken_order_preview(
        proposal=pending_proposal,
        risk_gate_result=passed_risk_gate,
    )

    assert_equal(pending_preview.status, OrderPreviewStatus.BLOCKED, "pending proposal blocked")
    assert_true("not manually approved" in pending_preview.reason.lower(), "pending reason explains approval requirement")

    preview_dict = preview.to_dict()
    preview_text = str(preview_dict).lower()
    assert_true("api_key" not in preview_text, "preview does not mention API keys")
    assert_true("api_secret" not in preview_text, "preview does not mention API secrets")
    assert_true("withdraw" not in preview_text, "preview does not mention withdrawals")
    assert_true("funding" not in preview_text, "preview does not mention funding")
    assert_true("addorder" not in preview_text, "preview does not mention AddOrder")
    assert_true("cancelorder" not in preview_text, "preview does not mention CancelOrder")
    assert_true("live trading" not in preview_text, "preview does not mention live trading")

    try:
        create_kraken_order_preview(
            proposal=SimpleNamespace(
                proposal_id="bad-proposal",
                asset="BTC/USD",
                side="buy",
                order_type="limit",
                volume=0.0,
                limit_price=75000.0,
                estimated_value=0.0,
                approval_status="approved",
            ),
            risk_gate_result=passed_risk_gate,
        )
        raise AssertionError("Invalid volume should have failed.")
    except KrakenOrderPreviewError:
        print("[OK] Invalid volume rejected")

    print("Kraken order preview validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
