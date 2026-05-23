"""
Validation script for Slice 15H.

This validates the manual execution review CLI usage guide.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path


GUIDE_PATH = Path("docs/15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md")


def test_usage_guide_exists() -> None:
    assert GUIDE_PATH.exists()
    assert GUIDE_PATH.stat().st_size > 1000

    print("[OK] usage guide exists")


def test_usage_guide_has_required_sections() -> None:
    text = GUIDE_PATH.read_text(encoding="utf-8")

    required_phrases = (
        "Manual Execution Review CLI Usage Guide",
        "Run the fixed sample",
        "Run the fixed sample as JSON",
        "Run a custom manual execution review",
        "Audit log location",
        "How to interpret the output",
        "What is still forbidden",
        "What must happen before future live execution work",
        "blocked and non-executable",
    )

    for phrase in required_phrases:
        assert phrase in text

    print("[OK] usage guide has required sections")


def test_usage_guide_includes_safe_commands() -> None:
    text = GUIDE_PATH.read_text(encoding="utf-8")

    required_commands = (
        "python .\\scripts\\run_manual_execution_review_sample.py",
        "python -m tradingagents.execution.manual_execution_review_cli",
        "--pair BTC/CAD",
        "--side buy",
        "--order-type limit",
        "--volume 0.000085168",
        "--limit-price 100000",
        "--audit-file-path reports/manual_execution_review.jsonl",
    )

    for command in required_commands:
        assert command in text

    print("[OK] usage guide includes safe commands")


def test_usage_guide_documents_blocked_interpretation() -> None:
    text = GUIDE_PATH.read_text(encoding="utf-8")

    required_terms = (
        "`blocked`",
        "`non_executable`",
        "`execution_allowed`",
        "`secrets_included`",
        "`execution_endpoint_called`",
        "Must be `true`",
        "Must be `false`",
    )

    for term in required_terms:
        assert term in text

    print("[OK] usage guide explains blocked/non-executable output")


def test_usage_guide_source_contains_no_private_execution_endpoint_names() -> None:
    text = GUIDE_PATH.read_text(encoding="utf-8").lower()

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
        assert term not in text

    print("[OK] usage guide contains no private execution endpoint names")


def main() -> None:
    print("Slice 15H validation: Manual Execution Review CLI Usage Guide")
    print("=" * 80)

    test_usage_guide_exists()
    test_usage_guide_has_required_sections()
    test_usage_guide_includes_safe_commands()
    test_usage_guide_documents_blocked_interpretation()
    test_usage_guide_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15H manual execution review CLI usage guide validation passed.")
    print("[PASS] Usage guide documents safe blocked non-executable review commands.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
