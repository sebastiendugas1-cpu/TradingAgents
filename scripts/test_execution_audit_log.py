"""
Validation script for Slice 15B.

This script validates execution audit logging only.
It does not place orders, cancel orders, or call private execution endpoints.
"""

from __future__ import annotations

import inspect
import tempfile
from pathlib import Path

from tradingagents.execution.execution_audit_log import (
    ExecutionAuditLogError,
    ExecutionAuditLogWriter,
    create_execution_audit_record,
)
import tradingagents.execution.execution_audit_log as audit_module


def expect_audit_error(label: str, func) -> None:
    try:
        func()
    except ExecutionAuditLogError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ExecutionAuditLogError")


def make_valid_record(**overrides):
    values = {
        "package_id": "sim_pkg_test_001",
        "mode": "simulation",
        "pair": "BTC/CAD",
        "side": "buy",
        "order_type": "limit",
        "volume": "0.000085168",
        "limit_price": "100000",
        "readiness_status": "blocked",
        "risk_status": "approved_for_simulation",
        "manual_approval_status": "approved_for_simulation",
        "dry_run_preview_status": "ready",
        "final_status": "simulation_only_blocked_from_live_execution",
        "reasons": ("Simulation package only; live execution is not implemented.",),
        "metadata": {"source": "slice_15b_test"},
        "timestamp_utc": "2026-05-22T22:30:00+00:00",
    }
    values.update(overrides)
    return create_execution_audit_record(**values)


def test_record_creation_and_safe_report() -> None:
    record = make_valid_record()

    assert record.audit_id.startswith("audit_")
    assert record.package_id == "sim_pkg_test_001"
    assert record.mode == "simulation"
    assert record.pair == "BTC/CAD"
    assert record.side == "buy"
    assert record.volume == "0.000085168"

    report = record.safe_report()
    assert report["secrets_included"] is False
    assert report["final_status"] == "simulation_only_blocked_from_live_execution"

    print("[OK] audit record creation and safe report passed")


def test_jsonl_writer_appends_and_reads_records() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        audit_path = Path(tmp_dir) / "execution_audit.jsonl"
        writer = ExecutionAuditLogWriter(audit_path)
        record = make_valid_record()

        written_path = writer.append_record(record)
        assert written_path == audit_path
        assert audit_path.exists()

        records = writer.read_records()
        assert len(records) == 1
        assert records[0]["audit_id"] == record.audit_id
        assert records[0]["secrets_included"] is False
        assert records[0]["metadata"]["source"] == "slice_15b_test"

    print("[OK] JSONL writer appends and reads records")


def test_secret_metadata_is_redacted() -> None:
    record = make_valid_record(
        metadata={
            "strategy": "manual_test",
            "api_key": "SHOULD_NOT_BE_LOGGED",
            "nested": {"token": "ALSO_NOT_LOGGED"},
        }
    )

    payload = record.to_dict()
    assert payload["metadata"]["api_key"] == "[REDACTED]"
    assert payload["metadata"]["nested"]["token"] == "[REDACTED]"

    print("[OK] secret-like metadata is redacted")


def test_invalid_records_are_rejected() -> None:
    expect_audit_error("missing package_id rejected", lambda: make_valid_record(package_id=""))
    expect_audit_error("invalid side rejected", lambda: make_valid_record(side="hold"))
    expect_audit_error("zero volume rejected", lambda: make_valid_record(volume="0"))
    expect_audit_error("negative limit price rejected", lambda: make_valid_record(limit_price="-1"))
    expect_audit_error("forbidden audit action term rejected", lambda: make_valid_record(reasons=("withdrawal requested",)))


def test_audit_path_validation() -> None:
    expect_audit_error(
        "audit path cannot target env file",
        lambda: ExecutionAuditLogWriter(".env"),
    )
    expect_audit_error(
        "audit path must be jsonl or log",
        lambda: ExecutionAuditLogWriter("audit.txt"),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source = inspect.getsource(audit_module).lower()
    forbidden_terms = (
        "addorder",
        "cancelorder",
        "private/addorder",
        "private/cancelorder",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] audit source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15B validation: Execution Audit Log")
    print("=" * 80)

    test_record_creation_and_safe_report()
    test_jsonl_writer_appends_and_reads_records()
    test_secret_metadata_is_redacted()
    test_invalid_records_are_rejected()
    test_audit_path_validation()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15B execution audit log validation passed.")
    print("[PASS] Audit records are safe to log and redact secret-like metadata.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
