"""
Slice 15G sample runner for the manual execution review pipeline.

This script creates one known-safe sample manual execution review using the
Slice 15E command builder. It is intentionally non-executable.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from tradingagents.execution.manual_execution_command_builder import (
    build_manual_execution_command_from_order_intent,
    assert_builder_result_cannot_execute,
    ManualExecutionCommandBuilderError,
)


DEFAULT_AUDIT_PATH = Path("reports") / "manual_execution_review_sample.jsonl"


def build_sample_review(*, audit_file_path: str | Path = DEFAULT_AUDIT_PATH) -> dict[str, Any]:
    """
    Build one sample review package.

    The returned summary is safe to print and safe to log.
    """

    result = build_manual_execution_command_from_order_intent(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume="0.000085168",
        limit_price="100000",
        audit_file_path=audit_file_path,
        metadata={
            "source": "slice_15g_manual_execution_review_sample",
            "proposal_id": "sample-proposal-15g",
            "approval_id": "sample-approval-15g",
            "strategy_name": "sample_manual_review",
            "risk_summary": "sample only; non-executable",
            "operator_note": "Slice 15G sample runner",
        },
    )

    blocked_message = ""
    try:
        assert_builder_result_cannot_execute(result)
    except ManualExecutionCommandBuilderError as exc:
        blocked_message = str(exc)

    safe_report = result.safe_report()

    return {
        "slice": "15G",
        "mode": "manual_execution_review_sample",
        "pair": "BTC/CAD",
        "side": "buy",
        "order_type": "limit",
        "volume": "0.000085168",
        "limit_price": "100000",
        "audit_file_path": str(audit_file_path),
        "builder_id": safe_report["builder_id"],
        "package_id": safe_report["package_id"],
        "audit_id": safe_report["audit_id"],
        "command_id": safe_report["command_id"],
        "command_status": safe_report["command_status"],
        "final_status": safe_report["final_status"],
        "blocked": safe_report["blocked"],
        "non_executable": True,
        "execution_allowed": False,
        "blocked_message": blocked_message,
        "reason_count": safe_report["reason_count"],
        "reasons": safe_report["reasons"],
        "secrets_included": False,
        "execution_endpoint_called": False,
    }


def print_text_summary(summary: dict[str, Any]) -> None:
    """Print a readable review summary."""

    print("Manual Execution Review Sample")
    print("=" * 80)
    print(f"Slice:                 {summary['slice']}")
    print(f"Mode:                  {summary['mode']}")
    print(f"Pair:                  {summary['pair']}")
    print(f"Side:                  {summary['side']}")
    print(f"Order type:            {summary['order_type']}")
    print(f"Volume:                {summary['volume']}")
    print(f"Limit price:           {summary['limit_price']}")
    print(f"Command status:        {summary['command_status']}")
    print(f"Final status:          {summary['final_status']}")
    print(f"Blocked:               {summary['blocked']}")
    print(f"Non-executable:        {summary['non_executable']}")
    print(f"Execution allowed:     {summary['execution_allowed']}")
    print(f"Audit file:            {summary['audit_file_path']}")
    print(f"Audit ID:              {summary['audit_id']}")
    print(f"Command ID:            {summary['command_id']}")
    print("-" * 80)
    print("Reasons:")
    for reason in summary["reasons"]:
        print(f"- {reason}")
    print("-" * 80)
    print(f"Blocked message:       {summary['blocked_message']}")
    print("=" * 80)
    print("[SAFE] This sample is blocked and non-executable.")
    print("[SAFE] No private execution endpoint was called.")


def run_cli(argv: list[str] | None = None) -> int:
    """Run the sample review CLI."""

    parser = argparse.ArgumentParser(
        description="Run a safe non-executable manual execution review sample."
    )
    parser.add_argument(
        "--audit-file-path",
        default=str(DEFAULT_AUDIT_PATH),
        help="Path to local JSONL audit log output.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON output instead of text.",
    )

    args = parser.parse_args(argv)
    summary = build_sample_review(audit_file_path=args.audit_file_path)

    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print_text_summary(summary)

    return 0


if __name__ == "__main__":
    raise SystemExit(run_cli())
