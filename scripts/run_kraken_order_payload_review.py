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

from tradingagents.execution.kraken_private_signing_material_review_integration import (
    build_disabled_signer_shell_review_with_signing_material,
)

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



def _attach_disabled_signing_material_review(payload):
    """Attach disabled signing-material review data to mapping-based CLI output."""

    if not isinstance(payload, dict):
        return payload

    if "signing_material_review" in payload:
        return payload

    updated_payload = dict(payload)
    signer_review = updated_payload.get("signer_shell_review")
    if signer_review is None:
        signer_review = updated_payload.get("private_signer_review")
    if signer_review is None:
        signer_review = updated_payload.get("private_client_review")
    if signer_review is None:
        signer_review = {"status": "disabled", "source": "payload_review_cli"}

    updated_payload["signing_material_review"] = dict(
        build_disabled_signer_shell_review_with_signing_material(signer_review=signer_review)
    )
    return updated_payload

if __name__ == "__main__":
    raise SystemExit(run_cli())
