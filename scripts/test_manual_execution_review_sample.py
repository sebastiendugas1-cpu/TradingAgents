"""
Validation script for Slice 15G.

This validates the sample runner for the manual execution review pipeline.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

import importlib.util

_SAMPLE_PATH = Path("scripts/run_manual_execution_review_sample.py")
_SPEC = importlib.util.spec_from_file_location("run_manual_execution_review_sample", _SAMPLE_PATH)

if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("Could not load sample runner module.")

_SAMPLE_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_SAMPLE_MODULE)

build_sample_review = _SAMPLE_MODULE.build_sample_review
run_cli = _SAMPLE_MODULE.run_cli


def assert_safe_summary(summary: dict) -> None:
    assert summary["slice"] == "15G"
    assert summary["mode"] == "manual_execution_review_sample"
    assert summary["pair"] == "BTC/CAD"
    assert summary["side"] == "buy"
    assert summary["order_type"] == "limit"
    assert summary["volume"] == "0.000085168"
    assert summary["limit_price"] == "100000"
    assert summary["blocked"] is True
    assert summary["non_executable"] is True
    assert summary["execution_allowed"] is False
    assert summary["secrets_included"] is False
    assert summary["execution_endpoint_called"] is False
    assert summary["audit_id"]
    assert summary["command_id"]
    assert "non-executable" in summary["blocked_message"].lower()


def test_build_sample_review_writes_audit_file() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "sample_review.jsonl"
        summary = build_sample_review(audit_file_path=audit_path)

        assert_safe_summary(summary)
        assert audit_path.exists()

        rows = [
            json.loads(line)
            for line in audit_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

        assert len(rows) == 1
        assert rows[0]["audit_id"] == summary["audit_id"]
        assert rows[0]["pair"] == "BTC/CAD"
        assert rows[0]["side"] == "buy"
        assert rows[0]["secrets_included"] is False

    print("[OK] sample review builds and writes safe audit file")


def test_run_cli_text_mode() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "sample_review_text.jsonl"
        exit_code = run_cli(["--audit-file-path", str(audit_path)])

        assert exit_code == 0
        assert audit_path.exists()

    print("[OK] run_cli text mode works")


def test_subprocess_json_mode() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "sample_review_json.jsonl"

        completed = subprocess.run(
            [
                sys.executable,
                ".\\scripts\\run_manual_execution_review_sample.py",
                "--audit-file-path",
                str(audit_path),
                "--json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        summary = json.loads(completed.stdout)
        assert_safe_summary(summary)
        assert audit_path.exists()

    print("[OK] subprocess JSON mode works")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path("scripts/run_manual_execution_review_sample.py").read_text(
        encoding="utf-8"
    ).lower()

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

    print("[OK] sample runner source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15G validation: Manual Execution Review Sample Runner")
    print("=" * 80)

    test_build_sample_review_writes_audit_file()
    test_run_cli_text_mode()
    test_subprocess_json_mode()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15G manual execution review sample runner validation passed.")
    print("[PASS] Sample runner produces safe blocked non-executable review output.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()

