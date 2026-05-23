"""
Validation script for Slice 17D.

This validates the live execution activation policy.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.live_execution_activation_policy import (
    ActivationPolicyError,
    ActivationPolicyStatus,
    LiveExecutionActivationEvidence,
    assert_activation_policy_report_is_safe,
    build_theoretical_ready_evidence_for_tests,
    evaluate_live_execution_activation_policy,
)


def test_default_policy_is_blocked() -> None:
    result = evaluate_live_execution_activation_policy()
    report = result.safe_report()

    assert result.status == ActivationPolicyStatus.BLOCKED
    assert result.blocked is True
    assert result.theoretically_ready is False
    assert report["execution_enabled_by_policy"] is False
    assert report["secrets_included"] is False
    assert report["private_endpoint_called"] is False
    assert report["reason_count"] > 5

    assert_activation_policy_report_is_safe(report)

    print("[OK] default activation policy is blocked")


def test_theoretical_ready_policy_still_does_not_enable_execution() -> None:
    evidence = build_theoretical_ready_evidence_for_tests()
    result = evaluate_live_execution_activation_policy(evidence)
    report = result.safe_report()

    assert result.status == ActivationPolicyStatus.THEORETICALLY_READY
    assert result.blocked is True
    assert result.theoretically_ready is True
    assert report["execution_enabled_by_policy"] is False
    assert report["emergency_shutdown_required"] is True
    assert report["secrets_included"] is False
    assert report["private_endpoint_called"] is False

    assert_activation_policy_report_is_safe(report)

    print("[OK] theoretically ready policy still does not enable execution")


def expect_error(label: str, func) -> None:
    try:
        func()
    except ActivationPolicyError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected ActivationPolicyError")


def test_invalid_policy_inputs_are_rejected() -> None:
    expect_error(
        "negative max value rejected",
        lambda: LiveExecutionActivationEvidence(
            max_live_trade_value="-1",
        ).safe_report(),
    )

    expect_error(
        "non-numeric max value rejected",
        lambda: LiveExecutionActivationEvidence(
            max_live_trade_value="not-a-number",
        ).safe_report(),
    )

    expect_error(
        "non-CAD currency rejected",
        lambda: LiveExecutionActivationEvidence(
            max_live_trade_value="10",
            max_live_trade_value_currency="USD",
        ).safe_report(),
    )


def test_policy_document_exists() -> None:
    path = Path("docs/16_LIVE_EXECUTION_ACTIVATION_POLICY.md")
    assert path.exists()
    text = path.read_text(encoding="utf-8")

    required_phrases = (
        "Live Execution Activation Policy",
        "Required evidence before future live execution can be considered",
        "Required manual statement",
        "Emergency shutdown rule",
        "theoretically_ready",
        "does not enable live execution",
    )

    for phrase in required_phrases:
        assert phrase in text

    print("[OK] activation policy document exists")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source_paths = (
        Path("tradingagents/execution/live_execution_activation_policy.py"),
        Path("docs/16_LIVE_EXECUTION_ACTIVATION_POLICY.md"),
    )

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

    for path in source_paths:
        source = path.read_text(encoding="utf-8").lower()
        for term in forbidden_terms:
            assert term not in source, f"Forbidden term {term!r} found in {path}"

    print("[OK] activation policy source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17D validation: Live Execution Activation Policy")
    print("=" * 80)

    test_default_policy_is_blocked()
    test_theoretical_ready_policy_still_does_not_enable_execution()
    test_invalid_policy_inputs_are_rejected()
    test_policy_document_exists()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17D live execution activation policy validation passed.")
    print("[PASS] Activation policy remains blocked and does not enable execution.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
