"""
Manual execution command review CLI.

Slice 15F purpose:
- Provide a local terminal review tool for manual execution command candidates.
- Build the existing simulation/audit/command-builder flow from CLI arguments.
- Print a safe human-readable review summary.
- Keep the result blocked and non-executable.

Important:
This module does NOT place orders.
This module does NOT cancel orders.
This module does NOT call private execution endpoints.
This module does NOT require private account-changing permissions.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Mapping, Sequence

from tradingagents.execution.manual_execution_command_builder import (
    ManualExecutionCommandBuilderError,
    assert_builder_result_cannot_execute,
    build_manual_execution_command_from_order_intent,
)


DEFAULT_AUDIT_FILE_PATH = Path("reports") / "manual_execution_review_audit.jsonl"


class ManualExecutionReviewCliError(ValueError):
    """Raised when the manual execution review CLI cannot complete safely."""


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""

    parser = argparse.ArgumentParser(
        description=(
            "Build and review a non-executable manual execution command candidate. "
            "Slice 15F is review-only and cannot execute broker actions."
        )
    )

    parser.add_argument("--pair", required=True, help="Trading pair, for example BTC/CAD.")
    parser.add_argument("--side", required=True, choices=("buy", "sell"), help="Order side.")
    parser.add_argument(
        "--order-type",
        required=True,
        choices=("market", "limit"),
        help="Order type.",
    )
    parser.add_argument("--volume", required=True, help="Order volume as a positive decimal.")
    parser.add_argument(
        "--limit-price",
        default=None,
        help="Limit price. Required for limit orders; ignored for market orders.",
    )
    parser.add_argument(
        "--audit-file-path",
        default=str(DEFAULT_AUDIT_FILE_PATH),
        help="Local JSONL audit file path.",
    )
    parser.add_argument(
        "--proposal-id",
        default="cli-review",
        help="Optional proposal identifier for traceability.",
    )
    parser.add_argument(
        "--approval-id",
        default="cli-review",
        help="Optional approval identifier for traceability.",
    )
    parser.add_argument(
        "--strategy-name",
        default="manual_execution_review_cli",
        help="Optional strategy/source name for traceability.",
    )
    parser.add_argument(
        "--operator-note",
        default="Slice 15F CLI review-only command candidate",
        help="Optional operator note for the simulation package.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the safe review summary as JSON.",
    )

    return parser


def build_manual_execution_review(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str,
    limit_price: str | None,
    audit_file_path: str | Path,
    proposal_id: str = "cli-review",
    approval_id: str = "cli-review",
    strategy_name: str = "manual_execution_review_cli",
    operator_note: str = "Slice 15F CLI review-only command candidate",
) -> dict[str, Any]:
    """
    Build a safe manual execution review summary.

    This function writes a local audit record through the existing builder flow,
    but it never executes the resulting command.
    """

    metadata = {
        "source": "slice_15f_manual_execution_review_cli",
        "proposal_id": proposal_id,
        "approval_id": approval_id,
        "strategy_name": strategy_name,
        "risk_summary": "CLI review generated a non-executable command candidate.",
        "operator_note": operator_note,
    }

    result = build_manual_execution_command_from_order_intent(
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        audit_file_path=Path(audit_file_path),
        metadata=metadata,
    )

    blocked_by_design = False
    blocked_message = ""

    try:
        assert_builder_result_cannot_execute(result)
    except ManualExecutionCommandBuilderError as exc:
        blocked_by_design = True
        blocked_message = str(exc)

    if not blocked_by_design:
        raise ManualExecutionReviewCliError(
            "Manual execution review unexpectedly appeared executable."
        )

    summary = {
        "slice": "15F",
        "mode": "manual_execution_command_review",
        "execution_allowed": False,
        "non_executable": True,
        "blocked": True,
        "blocked_message": blocked_message,
        "builder_id": result.builder_id,
        "package_id": result.package_id,
        "audit_id": result.audit_id,
        "command_id": result.command_id,
        "command_status": str(result.command_status),
        "final_status": result.final_status,
        "pair": pair,
        "side": side,
        "order_type": order_type,
        "volume": str(volume),
        "limit_price": str(limit_price) if limit_price is not None else None,
        "audit_file_path": str(audit_file_path),
        "reason_count": len(result.reasons),
        "reasons": list(result.reasons),
        "secrets_included": False,
        "execution_endpoint_called": False,
    }

    assert_review_summary_is_safe(summary)
    return summary


def assert_review_summary_is_safe(summary: Mapping[str, Any]) -> None:
    """Validate that a review summary is safe to print."""

    text = json.dumps(summary, sort_keys=True, default=str).lower()

    forbidden_fragments = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "secret=",
        "token=",
    )

    for fragment in forbidden_fragments:
        if fragment in text:
            raise ManualExecutionReviewCliError(
                f"Unsafe value rejected from CLI review summary: {fragment}"
            )

    if summary.get("execution_allowed") is not False:
        raise ManualExecutionReviewCliError("CLI review summary must not allow execution.")

    if summary.get("non_executable") is not True:
        raise ManualExecutionReviewCliError("CLI review summary must remain non-executable.")

    if summary.get("execution_endpoint_called") is not False:
        raise ManualExecutionReviewCliError("CLI review summary reported an endpoint call.")


def format_text_summary(summary: Mapping[str, Any]) -> str:
    """Format a human-readable review summary."""

    lines = [
        "Manual Execution Command Review",
        "=" * 80,
        f"Slice: {summary['slice']}",
        f"Mode: {summary['mode']}",
        f"Pair: {summary['pair']}",
        f"Side: {summary['side']}",
        f"Order Type: {summary['order_type']}",
        f"Volume: {summary['volume']}",
        f"Limit Price: {summary['limit_price']}",
        f"Command Status: {summary['command_status']}",
        f"Final Status: {summary['final_status']}",
        f"Package ID: {summary['package_id']}",
        f"Audit ID: {summary['audit_id']}",
        f"Command ID: {summary['command_id']}",
        f"Audit File: {summary['audit_file_path']}",
        "",
        "EXECUTION STATUS: BLOCKED",
        "NON-EXECUTABLE: TRUE",
        f"Blocked Message: {summary['blocked_message']}",
        "",
        "Reasons:",
    ]

    reasons = summary.get("reasons", [])
    if reasons:
        lines.extend(f"- {reason}" for reason in reasons)
    else:
        lines.append("- Review is blocked by design.")

    lines.extend(
        [
            "",
            "Safety:",
            "- No private execution endpoint call was made.",
            "- No live trading action was performed.",
            "- This is a review-only command candidate.",
        ]
    )

    return "\n".join(lines)


def run_cli(argv: Sequence[str] | None = None) -> int:
    """Run the CLI and return a process exit code."""

    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        summary = build_manual_execution_review(
            pair=args.pair,
            side=args.side,
            order_type=args.order_type,
            volume=args.volume,
            limit_price=args.limit_price,
            audit_file_path=args.audit_file_path,
            proposal_id=args.proposal_id,
            approval_id=args.approval_id,
            strategy_name=args.strategy_name,
            operator_note=args.operator_note,
        )
    except Exception as exc:
        print(f"[BLOCKED] Manual execution review failed safely: {exc}")
        return 2

    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True, default=str))
    else:
        print(format_text_summary(summary))

    return 0


def main() -> None:
    """CLI entrypoint."""

    raise SystemExit(run_cli())


if __name__ == "__main__":
    main()
