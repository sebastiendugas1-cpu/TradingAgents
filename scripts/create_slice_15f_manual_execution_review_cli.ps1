param(
    [string]$ProjectRoot = "D:\Trading\TradingAgents"
)

$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15F MANUAL EXECUTION COMMAND REVIEW CLI ==="

Set-Location $ProjectRoot

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null
New-Item -ItemType Directory -Force ".\docs" | Out-Null

$initPath = ".\tradingagents\execution\__init__.py"
if (-not (Test-Path $initPath)) {
@'
"""
Execution safety package.
"""
'@ | Set-Content -Path $initPath -Encoding UTF8
    Write-Host "[WRITTEN] $initPath"
} else {
    Write-Host "[SKIPPED] $initPath already exists; preserving current package exports."
}

$cliPath = ".\tradingagents\execution\manual_execution_review_cli.py"
@'
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
'@ | Set-Content -Path $cliPath -Encoding UTF8
Write-Host "[WRITTEN] $cliPath"

$testPath = ".\scripts\test_manual_execution_review_cli.py"
@'
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
'@ | Set-Content -Path $testPath -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

function Add-DocBlockIfMissing {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Force $Path | Out-Null
    }

    $existing = Get-Content $Path -Raw
    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value ""
        Add-Content -Path $Path -Value $Block
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @'
## Slice 15F — Manual Execution Command Review CLI

Status: Implemented pending validation.

Goal:
Add a local command-line review tool that builds a non-executable manual execution command candidate from terminal arguments.

Scope:
- Accept pair, side, order type, volume, limit price, and audit file path.
- Build the simulation/audit/command-builder workflow.
- Print a safe human-readable or JSON review summary.
- Keep the result blocked and non-executable.
- No private execution endpoint call.
- No live trading action.
- No private account-changing permission requirement.

Files introduced:
- `tradingagents/execution/manual_execution_review_cli.py`
- `scripts/test_manual_execution_review_cli.py`
- `scripts/create_slice_15f_manual_execution_review_cli.ps1`
'@

$controlsBlock = @'
## Slice 15F — Manual Execution Command Review CLI

Slice 15F introduces a local CLI review tool for manual execution command candidates.

The CLI:
- Builds the existing simulation package.
- Writes the local audit record.
- Builds the manual execution command candidate.
- Prints a safe review summary.
- Clearly reports that the command is blocked and non-executable.

This slice does not add private execution endpoint calls or live trading actions.
'@

$decisionBlock = @'
## Slice 15F Decision — Review CLI Before Any Execution Adapter

Decision:
Before any future execution adapter is considered, add a local manual command review CLI.

Reason:
The project now has a simulation package, audit log, command model, and command builder. A local CLI makes this pipeline practical to test from PowerShell while keeping the output non-executable.

Result:
Manual execution command candidates can be reviewed locally, written to audit logs, and inspected as safe summaries without enabling live execution.
'@

Add-DocBlockIfMissing -Path ".\docs\03_ROADMAP.md" -Marker "Slice 15F — Manual Execution Command Review CLI" -Block $roadmapBlock
Add-DocBlockIfMissing -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 15F — Manual Execution Command Review CLI" -Block $controlsBlock
Add-DocBlockIfMissing -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 15F Decision" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15F FILES ==="
Get-Item $cliPath, $testPath, ".\docs\03_ROADMAP.md", ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15F script completed."
