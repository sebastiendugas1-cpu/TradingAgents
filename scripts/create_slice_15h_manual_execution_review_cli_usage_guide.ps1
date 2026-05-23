$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 15H MANUAL EXECUTION REVIEW CLI USAGE GUIDE ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\docs" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$guidePath = ".\docs\15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md"
$testPath = ".\scripts\test_manual_execution_review_cli_usage_guide.py"

$guideContent = @'
# Manual Execution Review CLI Usage Guide

Slice 15H documents how to safely use the manual execution review pipeline.

This guide covers:

- the fixed sample runner
- the custom manual execution review CLI
- where local audit logs are written
- how to interpret blocked / non-executable output
- what is still forbidden
- what must happen before any future live execution work

## Current safety status

The manual execution review tools are intentionally non-executable.

They do not:

- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

The review tools only create safe local review data and local audit records.

## Run the fixed sample

From the project root:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python .\scripts\run_manual_execution_review_sample.py; Read-Host "Press Enter to close..."
```

Expected behavior:

- prints a manual execution review sample
- marks the command as blocked
- marks the command as non-executable
- writes a local JSONL audit record under `reports/`
- does not call private execution endpoints

## Run the fixed sample as JSON

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python .\scripts\run_manual_execution_review_sample.py --json; Read-Host "Press Enter to close..."
```

Use JSON mode when you want to inspect the output as structured data.

## Run a custom manual execution review

Example:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python -m tradingagents.execution.manual_execution_review_cli --pair BTC/CAD --side buy --order-type limit --volume 0.000085168 --limit-price 100000 --audit-file-path reports/manual_execution_review.jsonl; Read-Host "Press Enter to close..."
```

This creates a blocked non-executable review for a custom order intent.

## Run a custom manual execution review as JSON

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python -m tradingagents.execution.manual_execution_review_cli --pair SOL/CAD --side buy --order-type limit --volume 0.1 --limit-price 200 --audit-file-path reports/manual_execution_review.jsonl --json; Read-Host "Press Enter to close..."
```

## Audit log location

By default, local review tools write JSONL audit records under:

```text
reports/
```

The `reports/` folder is local output and should remain ignored by Git.

Each audit record is intended for local review and later reconciliation.

## How to interpret the output

Important fields:

| Field | Meaning |
|---|---|
| `blocked` | Must be `true` in the current phase. |
| `non_executable` | Must be `true` in the current phase. |
| `execution_allowed` | Must be `false` in the current phase. |
| `command_status` | Shows the command review state, normally `blocked`. |
| `final_status` | Should clearly state that the command is blocked from live execution. |
| `audit_id` | ID of the local audit record. |
| `command_id` | ID of the non-executable command candidate. |
| `package_id` | ID of the simulation package. |
| `secrets_included` | Must be `false`. |
| `execution_endpoint_called` | Must be `false`. |

## What is still forbidden

The current system must not:

- place a real order
- cancel a real order
- enable automatic live execution
- use private account-changing permissions
- remove the global kill switch
- bypass manual review
- bypass the risk gate
- bypass audit logging

## What must happen before future live execution work

Before any future live execution slice is considered, the project must still preserve:

- global safety config
- kill switch
- max live trade value cap
- live execution preflight
- manual readiness report
- manual approval workflow
- risk gate
- dry-run / preview layer
- local audit log
- manual execution command model
- explicit user review

## Slice 15H conclusion

The current manual execution review pipeline is useful for local testing and review.

It remains blocked and non-executable by design.
'@

$testContent = @'
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
'@

Set-Content -Path $guidePath -Value $guideContent -Encoding UTF8
Write-Host "[WRITTEN] $guidePath"

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
## Slice 15H — Manual Execution Review CLI Usage Guide

Status: Implemented pending validation.

Goal:
Document how to safely use the manual execution review CLI and sample runner.

Scope:
- Create `docs/15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md`.
- Create `scripts/test_manual_execution_review_cli_usage_guide.py`.
- Document sample runner commands.
- Document custom review commands.
- Document audit log location.
- Document blocked / non-executable output interpretation.

Safety:
- Documentation and validation only.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 15H — Manual Execution Review CLI Usage Guide

The manual execution review CLI now has a usage guide.

The guide documents:
- how to run the fixed sample
- how to run a custom review
- how to read blocked / non-executable output
- where local audit logs are written
- what remains forbidden before future live execution work

This slice is documentation and validation only.
"@

$decisionBlock = @"
## Slice 15H Decision — Document Manual Review CLI Usage

Decision:
Add a usage guide for the manual execution review CLI and sample runner.

Reason:
The project now has a working safe review pipeline. It needs clear commands and interpretation rules before more execution-adjacent slices are added.

Result:
The user can run the manual review tools safely from PowerShell and understand that the output remains blocked and non-executable.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 15H — Manual Execution Review CLI Usage Guide" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 15H — Manual Execution Review CLI Usage Guide" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 15H Decision — Document Manual Review CLI Usage" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 15H FILES ==="
Get-Item `
    ".\docs\15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md", `
    ".\scripts\test_manual_execution_review_cli_usage_guide.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 15H script completed."
