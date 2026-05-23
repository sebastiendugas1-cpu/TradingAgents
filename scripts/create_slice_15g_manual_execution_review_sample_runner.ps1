$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15G MANUAL EXECUTION REVIEW SAMPLE RUNNER ==="

$Root = Get-Location

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\scripts" | Out-Null
New-Item -ItemType Directory -Force ".\reports" | Out-Null

$sampleRunnerPath = ".\scripts\run_manual_execution_review_sample.py"
$testPath = ".\scripts\test_manual_execution_review_sample.py"

$sampleRunnerContent = @'
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
'@

$testContent = @'
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

from scripts.run_manual_execution_review_sample import build_sample_review, run_cli


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
'@

Set-Content -Path $sampleRunnerPath -Value $sampleRunnerContent -Encoding UTF8
Write-Host "[WRITTEN] $sampleRunnerPath"

Set-Content -Path $testPath -Value $testContent -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

function Add-DocBlockOnce {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing doc file: $Path"
    }

    $existing = Get-Content $Path -Raw

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`n$Block" -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @"
## Slice 15G — Manual Execution Review CLI Sample Runner

Status: Implemented pending validation.

Goal:
Add a simple sample runner for the manual execution review pipeline.

Scope:
- Create `scripts/run_manual_execution_review_sample.py`.
- Create `scripts/test_manual_execution_review_sample.py`.
- Use one fixed BTC/CAD sample command.
- Write a local JSONL audit record.
- Print a clean blocked / non-executable summary.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 15G — Manual Execution Review Sample Runner

A sample runner has been added for the manual execution review pipeline.

The sample runner:
- Builds a known-safe BTC/CAD review sample.
- Writes a local JSONL audit record.
- Prints a blocked and non-executable review summary.
- Confirms execution is not allowed.

The sample runner remains non-executable and does not call private execution endpoints.
"@

$decisionBlock = @"
## Slice 15G Decision — Add a Repeatable Manual Review Sample

Decision:
Add a repeatable sample runner for the manual execution review pipeline.

Reason:
After adding the manual execution review CLI, the project needs a simple known-good sample command that can be run without remembering CLI arguments.

Result:
The project can now run a one-command sample that creates a safe blocked review summary and writes a local audit record.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 15G — Manual Execution Review CLI Sample Runner" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 15G — Manual Execution Review Sample Runner" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 15G Decision — Add a Repeatable Manual Review Sample" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15G FILES ==="
Get-Item `
    ".\scripts\run_manual_execution_review_sample.py", `
    ".\scripts\test_manual_execution_review_sample.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15G script completed."
