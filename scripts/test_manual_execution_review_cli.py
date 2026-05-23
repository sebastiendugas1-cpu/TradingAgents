"""
Validation script for Slice 15F.

This script validates the local manual execution command review CLI.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- perform live trading
- require private account-changing permissions
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from tradingagents.execution.manual_execution_review_cli import (
    build_manual_execution_review,
    run_cli,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CLI_PATH = PROJECT_ROOT / "tradingagents" / "execution" / "manual_execution_review_cli.py"


def expect_blocked(label: str, func) -> None:
    try:
        func()
    except Exception as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected safe block")


def test_direct_review_builder_creates_blocked_summary() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "execution_review.jsonl"

        summary = build_manual_execution_review(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.0001",
            limit_price="100000",
            audit_file_path=audit_file,
            proposal_id="test-proposal",
            approval_id="test-approval",
            strategy_name="slice_15f_test",
            operator_note="direct builder test",
        )

        assert summary["execution_allowed"] is False
        assert summary["non_executable"] is True
        assert summary["blocked"] is True
        assert summary["execution_endpoint_called"] is False
        assert summary["secrets_included"] is False
        assert summary["package_id"]
        assert summary["audit_id"]
        assert summary["command_id"]
        assert audit_file.exists()

        lines = audit_file.read_text(encoding="utf-8").splitlines()
        assert len(lines) == 1
        record = json.loads(lines[0])
        assert record["audit_id"] == summary["audit_id"]

    print("[OK] direct review builder creates blocked safe summary")


def test_cli_text_output_is_blocked_and_non_executable() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "cli_review.jsonl"

        result = subprocess.run(
            [
                sys.executable,
                str(CLI_PATH),
                "--pair",
                "BTC/CAD",
                "--side",
                "buy",
                "--order-type",
                "limit",
                "--volume",
                "0.0001",
                "--limit-price",
                "100000",
                "--audit-file-path",
                str(audit_file),
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        assert result.returncode == 0, result.stderr + result.stdout
        assert "EXECUTION STATUS: BLOCKED" in result.stdout
        assert "NON-EXECUTABLE: TRUE" in result.stdout
        assert "No private execution endpoint call was made." in result.stdout
        assert audit_file.exists()

    print("[OK] CLI text output is blocked and non-executable")


def test_cli_json_output_is_safe() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "cli_review.jsonl"

        result = subprocess.run(
            [
                sys.executable,
                str(CLI_PATH),
                "--pair",
                "ETH/CAD",
                "--side",
                "sell",
                "--order-type",
                "market",
                "--volume",
                "0.01",
                "--audit-file-path",
                str(audit_file),
                "--json",
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        assert result.returncode == 0, result.stderr + result.stdout

        payload = json.loads(result.stdout)
        assert payload["execution_allowed"] is False
        assert payload["non_executable"] is True
        assert payload["execution_endpoint_called"] is False
        assert payload["secrets_included"] is False
        assert payload["order_type"] == "market"

    print("[OK] CLI JSON output is safe")


def test_invalid_cli_input_fails_safely() -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(CLI_PATH),
            "--pair",
            "BTC/CAD",
            "--side",
            "buy",
            "--order-type",
            "limit",
            "--volume",
            "0.0001",
        ],
        cwd=PROJECT_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 2
    assert "[BLOCKED] Manual execution review failed safely:" in result.stdout

    print("[OK] invalid CLI input fails safely")


def test_run_cli_helper_returns_success() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "helper_review.jsonl"

        code = run_cli(
            [
                "--pair",
                "SOL/CAD",
                "--side",
                "buy",
                "--order-type",
                "limit",
                "--volume",
                "0.1",
                "--limit-price",
                "200",
                "--audit-file-path",
                str(audit_file),
                "--json",
            ]
        )

        assert code == 0
        assert audit_file.exists()

    print("[OK] run_cli helper returns success")


def test_cli_source_contains_no_private_execution_endpoint_names() -> None:
    source = CLI_PATH.read_text(encoding="utf-8").lower()

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

    print("[OK] CLI source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15F validation: Manual Execution Command Review CLI")
    print("=" * 80)

    test_direct_review_builder_creates_blocked_summary()
    test_cli_text_output_is_blocked_and_non_executable()
    test_cli_json_output_is_safe()
    test_invalid_cli_input_fails_safely()
    test_run_cli_helper_returns_success()
    test_cli_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15F manual execution command review CLI validation passed.")
    print("[PASS] CLI builds safe non-executable command reviews.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
