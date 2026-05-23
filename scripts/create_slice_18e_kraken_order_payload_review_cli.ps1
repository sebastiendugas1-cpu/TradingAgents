$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 18E KRAKEN ORDER PAYLOAD REVIEW CLI ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$cliPath = ".\scripts\run_kraken_order_payload_review.py"
$testPath = ".\scripts\test_kraken_order_payload_review_cli.py"

$cliContent = @'
"""
Slice 18E Kraken order payload review CLI.

This CLI builds a manual command candidate, translates it into a Kraken-style
validate=true review payload, and routes it through the disabled Kraken adapter
skeleton.

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

from tradingagents.execution.kraken_order_translation_adapter_integration import (
    build_translate_and_route_to_kraken_skeleton,
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
    Build a safe Kraken-style payload review report.

    No endpoint is called.
    """

    result = build_translate_and_route_to_kraken_skeleton(
        pair=pair,
        side=side,
        order_type=order_type,
        volume=volume,
        limit_price=limit_price,
        audit_file_path=audit_file_path,
        metadata={"source": "slice_18e_payload_review_cli"},
    )

    report = result.safe_report()

    return {
        "mode": "kraken_order_payload_review",
        "slice": "18E",
        "pair": pair,
        "side": side,
        "order_type": order_type,
        "volume": volume,
        "limit_price": limit_price,
        "kraken_payload": report["translation_payload"],
        "final_status": report["final_status"],
        "blocked": report["blocked"],
        "execution_allowed": False,
        "private_endpoint_called": False,
        "secrets_included": False,
        "command_id": report["command_id"],
        "request_id": report["request_id"],
        "audit_id": report["audit_id"],
        "package_id": report["package_id"],
        "adapter_result_id": report["adapter_result_id"],
        "adapter_report": report["adapter_report"],
    }


def print_text_review(report: dict[str, Any]) -> None:
    payload = dict(report["kraken_payload"])

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

$testContent = @'
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
        assert audit_path.exists()

    print("[OK] payload review builder creates safe limit review")


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
        assert payload["slice"] == "18E"
        assert payload["blocked"] is True
        assert payload["execution_allowed"] is False
        assert payload["private_endpoint_called"] is False
        assert payload["secrets_included"] is False
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
'@

Set-Content -Path $cliPath -Value $cliContent -Encoding UTF8
Write-Host "[WRITTEN] $cliPath"

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
## Slice 18E — Kraken Order Payload Review CLI

Status: Implemented pending validation.

Goal:
Add a human-readable CLI for reviewing Kraken-style validate=true order payloads.

Scope:
- Create `scripts/run_kraken_order_payload_review.py`.
- Create `scripts/test_kraken_order_payload_review_cli.py`.
- Build command candidates from CLI arguments.
- Translate to Kraken-style validate=true payload.
- Route through disabled Kraken adapter skeleton.
- Print text or JSON safe review output.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 18E — Kraken Order Payload Review CLI

A CLI has been added to review Kraken-style validate=true payloads.

The CLI:
- accepts pair, side, order type, volume, and optional limit price
- creates a review-only Kraken-style payload
- routes through the disabled adapter skeleton
- prints blocked safe output
- supports JSON mode
- does not call Kraken
"@

$decisionBlock = @"
## Slice 18E Decision — Add Human Review CLI Before Private Client Work

Decision:
Add a payload review CLI before creating any private client shell.

Reason:
The operator should be able to inspect the exact Kraken-style validate=true payload and blocked adapter result before future private-client architecture is added.

Result:
The project now has a safe human-review command for payload inspection.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 18E — Kraken Order Payload Review CLI" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 18E — Kraken Order Payload Review CLI" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 18E Decision — Add Human Review CLI Before Private Client Work" -Block $decisionBlock

python -m py_compile $cliPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 18E FILES ==="
Get-Item `
    ".\scripts\run_kraken_order_payload_review.py", `
    ".\scripts\test_kraken_order_payload_review_cli.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 18E script completed."
