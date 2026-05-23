# ============================ Slice 13D Validation - Risk Gate Engine ============================

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.decision import DecisionStatus  # noqa: E402
from tradingagents.risk import RiskGateConfig, RiskGateDecision, RiskGateEngine  # noqa: E402


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"[OK] {label}: {actual!r}")


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")
    print(f"[OK] {label}: {value!r}")


def make_proposal(**overrides):
    data = {
        "asset": "BTC/USD",
        "approval_status": "approved",
        "estimated_value": 50.0,
        "risk_summary": SimpleNamespace(risk_score=35),
        "strategy_scorecard": SimpleNamespace(
            action=DecisionStatus.PAPER_TRADE,
            risk_score=35,
            confidence_score=82,
        ),
    }
    data.update(overrides)
    return SimpleNamespace(**data)


def violation_codes(result):
    return {violation.code for violation in result.violations}


def main() -> int:
    print("Running Slice 13D risk gate engine validation...")

    engine = RiskGateEngine(
        RiskGateConfig(
            allowed_symbols=("BTC/USD", "ETH/USD"),
            max_trade_value=100.0,
            max_risk_score=70,
            min_confidence_score=55,
        )
    )

    passed = engine.evaluate_proposal(make_proposal())
    assert_equal(passed.decision, RiskGateDecision.APPROVED_FOR_DRY_RUN, "safe proposal approved for dry-run only")
    assert_true(passed.passed, "safe proposal passed")
    assert_true(not passed.blocked, "safe proposal not blocked")

    pending = engine.evaluate_proposal(make_proposal(approval_status="pending"))
    assert_equal(pending.decision, RiskGateDecision.BLOCKED, "pending proposal blocked")
    assert_true("manual_approval_required" in violation_codes(pending), "manual approval violation present")

    oversized = engine.evaluate_proposal(make_proposal(estimated_value=150.0))
    assert_equal(oversized.decision, RiskGateDecision.BLOCKED, "oversized proposal blocked")
    assert_true("trade_value_too_large" in violation_codes(oversized), "oversized violation present")

    risky = engine.evaluate_proposal(make_proposal(risk_summary=SimpleNamespace(risk_score=90)))
    assert_equal(risky.decision, RiskGateDecision.BLOCKED, "high-risk proposal blocked")
    assert_true("risk_score_too_high" in violation_codes(risky), "risk violation present")

    low_confidence = engine.evaluate_proposal(
        make_proposal(strategy_scorecard=SimpleNamespace(action=DecisionStatus.PAPER_TRADE, risk_score=35, confidence_score=30))
    )
    assert_equal(low_confidence.decision, RiskGateDecision.BLOCKED, "low-confidence proposal blocked")
    assert_true("confidence_score_too_low" in violation_codes(low_confidence), "confidence violation present")

    bad_symbol = engine.evaluate_proposal(make_proposal(asset="DOGE/USD"))
    assert_equal(bad_symbol.decision, RiskGateDecision.BLOCKED, "disallowed symbol blocked")
    assert_true("symbol_not_allowed" in violation_codes(bad_symbol), "symbol violation present")

    blocked_scorecard = engine.evaluate_proposal(
        make_proposal(strategy_scorecard=SimpleNamespace(action=DecisionStatus.BLOCKED, risk_score=35, confidence_score=82))
    )
    assert_equal(blocked_scorecard.decision, RiskGateDecision.BLOCKED, "blocked scorecard blocked")
    assert_true("decision_status_not_allowed" in violation_codes(blocked_scorecard), "decision status violation present")

    kill_switch = RiskGateEngine(RiskGateConfig(kill_switch_enabled=True)).evaluate_proposal(make_proposal())
    assert_equal(kill_switch.decision, RiskGateDecision.BLOCKED, "kill switch blocks proposal")
    assert_true("kill_switch_enabled" in violation_codes(kill_switch), "kill switch violation present")

    result_text = str(passed.to_dict()).lower()
    assert_true("api_key" not in result_text, "risk result does not mention API keys")
    assert_true("withdraw" not in result_text, "risk result does not mention withdrawals")
    assert_true("place_order" not in result_text, "risk result does not mention order placement")

    try:
        RiskGateConfig(max_trade_value=0)
        raise AssertionError("Invalid max_trade_value should fail.")
    except ValueError:
        print("[OK] Invalid risk gate config rejected")

    print("Risk gate engine validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
