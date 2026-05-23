# ============================ Slice 13B Validation - Trade Proposal Model ============================

from __future__ import annotations

import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import DecisionStatus, SignalDirection  # noqa: E402
from tradingagents.manual_confirmation import (  # noqa: E402
    OrderSide,
    OrderType,
    TradeApprovalStatus,
    TradeProposalError,
    TradeProposalLog,
    TradeProposalRiskSummary,
    build_trade_proposal_from_scorecard,
)


class FakeScorecard:
    asset = "btc-usd"
    action = DecisionStatus.PAPER_TRADE
    direction = SignalDirection.LONG
    confidence_score = 82
    risk_score = 35
    reason_summary = "Synthetic scorecard approved for paper/manual workflow."


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def main() -> int:
    print("Running Slice 13B trade proposal model validation...")

    proposal = build_trade_proposal_from_scorecard(
        scorecard=FakeScorecard(),
        side=OrderSide.BUY,
        order_type=OrderType.LIMIT,
        quantity=0.001,
        estimated_price=75000.0,
        max_trade_value=100.0,
        stop_loss_price=72000.0,
        take_profit_price=79000.0,
        proposal_id="proposal-test-001",
    )

    assert_equal(proposal.asset, "BTC/USD", "asset normalized")
    assert_equal(proposal.side, OrderSide.BUY, "proposal side")
    assert_equal(proposal.order_type, OrderType.LIMIT, "proposal order type")
    assert_equal(proposal.status, TradeApprovalStatus.PENDING, "new proposal starts pending")
    assert_equal(proposal.decision_status, DecisionStatus.PAPER_TRADE, "proposal decision status")
    assert_true(proposal.requires_manual_approval, "proposal requires manual approval")
    assert_equal(proposal.estimated_value, 75.0, "estimated value calculated")
    assert_equal(proposal.risk_summary.risk_score, 35, "risk score attached")

    approval = proposal.approve(approved_by="operator", note="test approval only")
    assert_equal(approval.previous_status, TradeApprovalStatus.PENDING, "approval previous status")
    assert_equal(approval.new_status, TradeApprovalStatus.APPROVED, "approval new status")

    rejection = proposal.reject(rejected_by="operator", note="test rejection only")
    assert_equal(rejection.new_status, TradeApprovalStatus.REJECTED, "rejection status")

    log_dir = PROJECT_ROOT / ".trade-proposals" / "slice-13b-test"
    if log_dir.exists():
        shutil.rmtree(log_dir)

    log = TradeProposalLog(log_dir)
    log.append_proposal(proposal)
    log.append_approval(approval)

    assert_equal(len(log.read_proposals()), 1, "proposal log count")
    assert_equal(len(log.read_approvals()), 1, "approval log count")

    proposal_dict = proposal.to_dict()
    assert_equal(proposal_dict["status"], "pending", "proposal dict status")
    assert_true("live_trade" not in str(proposal_dict).lower(), "proposal does not mention live trading")
    assert_true("api" not in str(proposal_dict).lower(), "proposal does not mention API keys")

    try:
        TradeProposalRiskSummary(risk_score=20, max_trade_value=10.0, estimated_trade_value=11.0)
        raise AssertionError("Oversized proposal risk summary should fail.")
    except TradeProposalError:
        print("[OK] oversized risk summary rejected")

    blocked_scorecard = FakeScorecard()
    blocked_scorecard.action = DecisionStatus.BLOCKED

    try:
        build_trade_proposal_from_scorecard(
            scorecard=blocked_scorecard,
            side=OrderSide.BUY,
            order_type=OrderType.MARKET,
            quantity=0.001,
            estimated_price=75000.0,
            max_trade_value=100.0,
        )
        raise AssertionError("Blocked scorecard should not create proposal.")
    except TradeProposalError:
        print("[OK] blocked scorecard rejected")

    print("Trade proposal model validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
