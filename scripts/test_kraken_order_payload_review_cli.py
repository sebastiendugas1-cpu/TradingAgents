"""
Validation script for Slice 18E.

This validates the Kraken order payload review CLI.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


_CLI_PATH = Path("scripts/run_kraken_order_payload_review.py")
_SPEC = importlib.util.spec_from_file_location("run_kraken_order_payload_review", _CLI_PATH)

if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("Could not load Kraken order payload review CLI.")

_CLI_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _CLI_MODULE
_SPEC.loader.exec_module(_CLI_MODULE)

build_payload_review = _CLI_MODULE.build_payload_review
run_cli = _CLI_MODULE.run_cli


def test_build_payload_review_limit_order() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_review.jsonl"

        report = build_payload_review(
            pair="BTC/CAD",
            side="buy",
            order_type="limit",
            volume="0.000085168",
            limit_price="100000",
            audit_file_path=audit_path,
        )

        payload = report["kraken_payload"]

        assert payload["pair"] == "XBT/CAD"
        assert payload["type"] == "buy"
        assert payload["ordertype"] == "limit"
        assert payload["volume"] == "0.000085168"
        assert payload["price"] == "100000"
        assert payload["validate"] is True
        assert report["blocked"] is True
        assert report["execution_allowed"] is False
        assert report["private_endpoint_called"] is False
        assert report["secrets_included"] is False
        assert "private_client_report" in report
        assert report["private_client_report"]["blocked"] is True
        assert report["private_client_report"]["operation"] == "submit_private_order_preview"
        assert report["private_client_report"]["private_endpoint_called"] is False
        assert audit_path.exists()

    print("[OK] payload review builder creates safe limit review with private client preview")


def test_run_cli_text_mode() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_review_text.jsonl"

        code = run_cli(
            [
                "--pair",
                "BTC/CAD",
                "--side",
                "buy",
                "--order-type",
                "limit",
                "--volume",
                "0.000085168",
                "--limit-price",
                "100000",
                "--audit-file",
                str(audit_path),
            ]
        )

        assert code == 0
        assert audit_path.exists()

    print("[OK] CLI text mode works")


def test_subprocess_json_mode() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "payload_review_json.jsonl"

        completed = subprocess.run(
            [
                sys.executable,
                "scripts/run_kraken_order_payload_review.py",
                "--pair",
                "SOL/CAD",
                "--side",
                "sell",
                "--order-type",
                "market",
                "--volume",
                "0.1",
                "--audit-file",
                str(audit_path),
                "--json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        payload = json.loads(completed.stdout)
        kraken_payload = payload["kraken_payload"]

        assert payload["mode"] == "kraken_order_payload_review"
        assert payload["slice"] == "19E"
        assert payload["blocked"] is True
        assert payload["execution_allowed"] is False
        assert payload["private_endpoint_called"] is False
        assert payload["secrets_included"] is False
        assert payload["private_client_report"]["blocked"] is True
        assert payload["private_client_report"]["operation"] == "submit_private_order_preview"
        assert payload["private_client_report"]["private_endpoint_called"] is False
        assert kraken_payload["pair"] == "SOL/CAD"
        assert kraken_payload["type"] == "sell"
        assert kraken_payload["ordertype"] == "market"
        assert kraken_payload["volume"] == "0.1"
        assert kraken_payload["price"] is None
        assert kraken_payload["validate"] is True
        assert audit_path.exists()

    print("[OK] subprocess JSON mode works")


def test_invalid_cli_input_fails_safely() -> None:
    completed = subprocess.run(
        [
            sys.executable,
            "scripts/run_kraken_order_payload_review.py",
            "--pair",
            "DOGE/CAD",
            "--side",
            "buy",
            "--order-type",
            "limit",
            "--volume",
            "1",
            "--limit-price",
            "1",
            "--json",
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    assert completed.returncode != 0

    print("[OK] invalid CLI input fails safely")


def test_cli_source_contains_no_private_execution_endpoint_names() -> None:
    source = _CLI_PATH.read_text(encoding="utf-8").lower()

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
    print("Slice 18E validation: Kraken Order Payload Review CLI")
    print("=" * 80)

    test_build_payload_review_limit_order()
    test_run_cli_text_mode()
    test_subprocess_json_mode()
    test_invalid_cli_input_fails_safely()
    test_cli_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 18E Kraken order payload review CLI validation passed.")
    print("[PASS] CLI produces blocked validate=true payload reviews only.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()

