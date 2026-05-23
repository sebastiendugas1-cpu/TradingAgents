$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 19E ADD PRIVATE CLIENT RESULT TO PAYLOAD REVIEW CLI ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

$cliPath = ".\scripts\run_kraken_order_payload_review.py"
$testPath = ".\scripts\test_kraken_order_payload_review_cli.py"

if (-not (Test-Path $cliPath)) {
    throw "Missing CLI file: $cliPath"
}

if (-not (Test-Path $testPath)) {
    throw "Missing CLI test file: $testPath"
}

if (-not (Test-Path ".\tradingagents\execution\kraken_payload_review_private_client_integration.py")) {
    throw "Missing Slice 19C payload review private client integration module."
}

$cliContent = @'
"""
Slice 19E Kraken order payload review CLI.

This CLI builds a manual command candidate, translates it into a Kraken-style
validate=true review payload, routes it through the disabled Kraken adapter
skeleton, and then routes the reviewed payload into the disabled private client
shell preview.

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

from tradingagents.execution.kraken_payload_review_private_client_integration import (
    build_payload_review_and_route_to_private_client_shell,
)


def build_payload_review(
    *,
    pair: str,
    side: str,
    order_type: str,
    volume: str,
    limit_price: str | None = None,
    audit_file_path: str | Path | None = None,
) -> dict[str, Any]:
    """
    Build a safe Kraken-style payload review report and private client preview.

    No endpoint is called.
    """

    result = build_payload_review_and_route_to_private_client_shell(
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        audit_file_path=audit_file_path,
        metadata={"source": "slice_19e_payload_review_cli"},
    )

    report = result.safe_report()

    return {
        "mode": "kraken_order_payload_review",
        "slice": "19E",
        "pair": pair,
        "side": side,
        "order_type": order_type,
        "volume": volume,
        "limit_price": limit_price,
        "kraken_payload": report["kraken_payload"],
        "final_status": report["final_status"],
        "blocked": report["blocked"],
        "execution_allowed": False,
        "private_endpoint_called": False,
        "secrets_included": False,
        "command_id": report["command_id"],
        "request_id": report["request_id"],
        "audit_id": report["audit_id"],
        "package_id": report["package_id"],
        "payload_review_report": report["payload_review_report"],
        "private_client_report": report["private_client_report"],
    }


def print_text_review(report: dict[str, Any]) -> None:
    payload = dict(report["kraken_payload"])
    private_client_report = dict(report["private_client_report"])

    print("Kraken Order Payload Review")
    print("=" * 80)
    print(f"Slice:                 {report['slice']}")
    print(f"Mode:                  {report['mode']}")
    print(f"Pair input:            {report['pair']}")
    print(f"Side input:            {report['side']}")
    print(f"Order type input:      {report['order_type']}")
    print(f"Volume input:          {report['volume']}")
    print(f"Limit price input:     {report['limit_price']}")
    print("-" * 80)
    print("Kraken-style validate=true payload preview")
    print(f"pair:                  {payload.get('pair')}")
    print(f"type:                  {payload.get('type')}")
    print(f"ordertype:             {payload.get('ordertype')}")
    print(f"volume:                {payload.get('volume')}")
    print(f"price:                 {payload.get('price')}")
    print(f"validate:              {payload.get('validate')}")
    print(f"userref:               {payload.get('userref')}")
    print("-" * 80)
    print("Disabled private client shell preview")
    print(f"operation:             {private_client_report.get('operation')}")
    print(f"status:                {private_client_report.get('status')}")
    print(f"blocked:               {private_client_report.get('blocked')}")
    print(f"execution allowed:     {private_client_report.get('execution_allowed')}")
    print(f"private endpoint call: {private_client_report.get('private_endpoint_called')}")
    print("-" * 80)
    print(f"Final status:          {report['final_status']}")
    print(f"Blocked:               {report['blocked']}")
    print(f"Execution allowed:     {report['execution_allowed']}")
    print(f"Private endpoint call: {report['private_endpoint_called']}")
    print(f"Secrets included:      {report['secrets_included']}")
    print(f"Command ID:            {report['command_id']}")
    print(f"Request ID:            {report['request_id']}")
    print(f"Audit ID:              {report['audit_id']}")
    print(f"Package ID:            {report['package_id']}")
    print("=" * 80)
    print("[SAFE] This review is blocked and non-executable.")
    print("[SAFE] No private endpoint was called.")
    print("[SAFE] The payload is for review only.")
    print("[SAFE] The private client shell preview is disabled.")


def run_cli(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build a safe Kraken-style order payload review."
    )
    parser.add_argument("--pair", required=True)
    parser.add_argument("--side", required=True, choices=("buy", "sell"))
    parser.add_argument("--order-type", required=True, choices=("market", "limit"))
    parser.add_argument("--volume", required=True)
    parser.add_argument("--limit-price")
    parser.add_argument(
        "--audit-file",
        default=str(Path("reports") / "kraken_order_payload_review.jsonl"),
    )
    parser.add_argument("--json", action="store_true")

    args = parser.parse_args(argv)

    report = build_payload_review(
        pair=args.pair,
        side=args.side,
        order_type=args.order_type,
        volume=args.volume,
        limit_price=args.limit_price,
        audit_file_path=args.audit_file,
    )

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_text_review(report)

    return 0


if __name__ == "__main__":
    raise SystemExit(run_cli())
'@

Set-Content -Path $cliPath -Value $cliContent -Encoding UTF8
Write-Host "[UPDATED] $cliPath"

$test = Get-Content $testPath -Raw

if ($test -notlike "*private_client_report*") {
    $test = $test.Replace(
'        assert report["secrets_included"] is False
        assert audit_path.exists()',
'        assert report["secrets_included"] is False
        assert "private_client_report" in report
        assert report["private_client_report"]["blocked"] is True
        assert report["private_client_report"]["operation"] == "submit_private_order_preview"
        assert report["private_client_report"]["private_endpoint_called"] is False
        assert audit_path.exists()'
    )

    $test = $test.Replace(
'        assert payload["secrets_included"] is False',
'        assert payload["secrets_included"] is False
        assert payload["private_client_report"]["blocked"] is True
        assert payload["private_client_report"]["operation"] == "submit_private_order_preview"
        assert payload["private_client_report"]["private_endpoint_called"] is False'
    )

    $test = $test.Replace(
'        assert payload["slice"] == "18E"',
'        assert payload["slice"] == "19E"'
    )

    $test = $test.Replace(
'    print("[OK] payload review builder creates safe limit review")',
'    print("[OK] payload review builder creates safe limit review with private client preview")'
    )

    Write-Host "[UPDATED] $testPath"
} else {
    Write-Host "[SKIPPED] $testPath already validates private client report"
}

Set-Content -Path $testPath -Value $test -Encoding UTF8

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
## Slice 19E — Add Private Client Result to Payload Review CLI

Status: Implemented pending validation.

Goal:
Extend the Kraken payload review CLI so it shows the disabled private client shell preview result.

Scope:
- Update `scripts/run_kraken_order_payload_review.py`.
- Update `scripts/test_kraken_order_payload_review_cli.py`.
- Route the CLI review path through the Slice 19C private client integration.
- Include `private_client_report` in text and JSON output.
- Validate the private client report remains blocked and safe.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 19E — Payload Review CLI Includes Private Client Shell Preview

The Kraken payload review CLI now includes the disabled private client shell preview result.

The CLI output now shows:
- Kraken-style validate=true payload
- disabled private client operation
- blocked private client status
- private endpoint call = false
- execution allowed = false
"@

$decisionBlock = @"
## Slice 19E Decision — Surface Private Client Shell Preview in Review CLI

Decision:
Update the payload review CLI to show the disabled private client shell preview result.

Reason:
The operator should see the full path from payload generation to private client boundary before future private transport work begins.

Result:
The CLI now displays the reviewed payload and the blocked private client shell result in one safe report.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 19E — Add Private Client Result to Payload Review CLI" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 19E — Payload Review CLI Includes Private Client Shell Preview" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 19E Decision — Surface Private Client Shell Preview in Review CLI" -Block $decisionBlock

python -m py_compile $cliPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 19E FILES ==="
Get-Item `
    ".\scripts\run_kraken_order_payload_review.py", `
    ".\scripts\test_kraken_order_payload_review_cli.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 19E script completed."
