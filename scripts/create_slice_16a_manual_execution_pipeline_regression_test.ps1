$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 16A MANUAL EXECUTION PIPELINE END-TO-END REGRESSION TEST ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$testPath = ".\scripts\test_manual_execution_pipeline_regression.py"

$testContent = @'
"""
Slice 16A end-to-end regression test for the manual execution review pipeline.

This script validates the complete safe manual-review path:

sample runner
-> review CLI
-> command builder
-> command model
-> simulation package
-> audit record
-> blocked / non-executable output

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


REQUIRED_SOURCE_FILES = (
    Path("scripts/run_manual_execution_review_sample.py"),
    Path("tradingagents/execution/manual_execution_review_cli.py"),
    Path("tradingagents/execution/manual_execution_command_builder.py"),
    Path("tradingagents/execution/manual_execution_command.py"),
    Path("tradingagents/execution/manual_live_order_simulation_package.py"),
    Path("tradingagents/execution/execution_audit_log.py"),
    Path("docs/15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md"),
)


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )


def assert_safe_review_payload(payload: dict, *, expected_pair: str) -> None:
    assert payload["pair"] == expected_pair
    assert payload["blocked"] is True
    assert payload["non_executable"] is True
    assert payload["execution_allowed"] is False
    assert payload["secrets_included"] is False
    assert payload["execution_endpoint_called"] is False
    assert payload["audit_id"]
    assert payload["command_id"]
    assert payload["package_id"]

    final_status = str(payload["final_status"]).lower()
    assert "blocked" in final_status
    assert "execution" in final_status


def read_jsonl(path: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def test_sample_runner_json_pipeline() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "sample_pipeline.jsonl"

        completed = run_command(
            [
                sys.executable,
                ".\\scripts\\run_manual_execution_review_sample.py",
                "--audit-file-path",
                str(audit_path),
                "--json",
            ]
        )

        payload = json.loads(completed.stdout)
        assert_safe_review_payload(payload, expected_pair="BTC/CAD")
        assert payload["slice"] == "15G"
        assert payload["mode"] == "manual_execution_review_sample"

        rows = read_jsonl(audit_path)
        assert len(rows) == 1
        assert rows[0]["audit_id"] == payload["audit_id"]
        assert rows[0]["pair"] == "BTC/CAD"
        assert rows[0]["secrets_included"] is False

    print("[OK] sample runner JSON pipeline regression passed")


def test_custom_review_cli_json_pipeline() -> None:
    with TemporaryDirectory() as tmpdir:
        audit_path = Path(tmpdir) / "custom_pipeline.jsonl"

        completed = run_command(
            [
                sys.executable,
                "-m",
                "tradingagents.execution.manual_execution_review_cli",
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
                str(audit_path),
                "--json",
            ]
        )

        payload = json.loads(completed.stdout)
        assert_safe_review_payload(payload, expected_pair="SOL/CAD")
        assert payload["mode"] == "manual_execution_command_review"

        rows = read_jsonl(audit_path)
        assert len(rows) == 1
        assert rows[0]["audit_id"] == payload["audit_id"]
        assert rows[0]["pair"] == "SOL/CAD"
        assert rows[0]["side"] == "buy"
        assert rows[0]["secrets_included"] is False

    print("[OK] custom review CLI JSON pipeline regression passed")


def test_usage_guide_exists_and_mentions_safe_pipeline() -> None:
    guide = Path("docs/15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md")
    assert guide.exists()

    text = guide.read_text(encoding="utf-8")

    required_phrases = (
        "Manual Execution Review CLI Usage Guide",
        "Run the fixed sample",
        "Run a custom manual execution review",
        "Audit log location",
        "blocked",
        "non-executable",
        "execution_allowed",
        "secrets_included",
        "execution_endpoint_called",
    )

    for phrase in required_phrases:
        assert phrase in text

    print("[OK] usage guide regression passed")


def test_required_source_files_exist() -> None:
    for path in REQUIRED_SOURCE_FILES:
        assert path.exists(), f"Missing required pipeline file: {path}"

    print("[OK] required source files exist")


def test_pipeline_sources_contain_no_private_execution_endpoint_names() -> None:
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

    for path in REQUIRED_SOURCE_FILES:
        text = path.read_text(encoding="utf-8").lower()
        for term in forbidden_terms:
            assert term not in text, f"Forbidden term {term!r} found in {path}"

    print("[OK] pipeline source scan contains no private execution endpoint names")


def main() -> None:
    print("Slice 16A validation: Manual Execution Pipeline End-to-End Regression Test")
    print("=" * 80)

    test_required_source_files_exist()
    test_sample_runner_json_pipeline()
    test_custom_review_cli_json_pipeline()
    test_usage_guide_exists_and_mentions_safe_pipeline()
    test_pipeline_sources_contain_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 16A manual execution pipeline regression validation passed.")
    print("[PASS] Sample runner and custom CLI remain blocked and non-executable.")
    print("[PASS] Audit logs are written and safe to read back.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

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
## Slice 16A — Manual Execution Pipeline End-to-End Regression Test

Status: Implemented pending validation.

Goal:
Add one regression test that validates the complete manual execution review pipeline.

Scope:
- Create `scripts/test_manual_execution_pipeline_regression.py`.
- Validate the fixed sample runner.
- Validate the custom manual execution review CLI.
- Validate local audit log write/read behavior.
- Validate the usage guide exists.
- Validate source files do not contain private execution endpoint names.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 16A — Manual Execution Pipeline Regression Test

A regression test now validates the full manual execution review pipeline.

The regression test checks:
- sample runner output
- custom CLI output
- audit log write/read behavior
- blocked / non-executable status
- safe source wording
- usage guide presence

This protects the safe manual-review workflow from accidental breakage in future slices.
"@

$decisionBlock = @"
## Slice 16A Decision — Protect the Manual Review Pipeline with Regression Coverage

Decision:
Add an end-to-end regression test before moving closer to live execution adapter work.

Reason:
The project now has many connected safety pieces. A single regression test is needed to confirm the complete pipeline remains blocked, non-executable, auditable, and safe to log.

Result:
Future changes can be tested against one script that validates the manual review pipeline from sample runner through audit output.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 16A — Manual Execution Pipeline End-to-End Regression Test" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 16A — Manual Execution Pipeline Regression Test" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 16A Decision — Protect the Manual Review Pipeline with Regression Coverage" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 16A FILES ==="
Get-Item `
    ".\scripts\test_manual_execution_pipeline_regression.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 16A script completed."
