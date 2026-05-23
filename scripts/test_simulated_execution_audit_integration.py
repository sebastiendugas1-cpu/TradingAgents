"""
Validation script for Slice 15C.

This validates integration between:
- Slice 15A manual live order simulation package
- Slice 15B execution audit log

It does not:
- place orders
- cancel orders
- call private execution endpoints
- require trading API permissions
- require funding or restricted account permissions
- print sensitive values
"""

from __future__ import annotations

from tempfile import TemporaryDirectory
from pathlib import Path

from tradingagents.execution.manual_live_order_simulation_package import (
    ManualLiveOrderSimulationInput,
    build_permissive_test_config,
)
from tradingagents.execution.simulated_execution_audit_integration import (
    assert_integration_report_is_safe,
    build_and_audit_simulated_execution_package,
    sanitize_reasons_for_audit,
)


def sample_limit_input() -> ManualLiveOrderSimulationInput:
    return ManualLiveOrderSimulationInput(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume="0.000085168",
        limit_price="100000",
        quote_currency="CAD",
        proposal_id="proposal-15c-test-001",
        approval_id="approval-15c-test-001",
        strategy_name="slice-15c-audit-integration",
        risk_summary="test risk summary",
        operator_note="simulation audit integration only",
    )


def test_default_simulation_package_is_written_to_audit_log() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_audit.jsonl"
        result = build_and_audit_simulated_execution_package(
            sample_limit_input(),
            audit_file_path=audit_file,
        )

        assert result.package.blocked is True
        assert result.package.simulation_only is True
        assert result.audit_record.package_id == result.package.simulation_id
        assert result.audit_record.mode == "simulation"
        assert result.audit_record.pair == "BTC/CAD"
        assert result.audit_record.side == "buy"
        assert result.audit_record.order_type == "limit"
        assert result.audit_record.volume == "0.000085168"
        assert result.audit_record.final_status == "blocked_simulation_only"
        assert result.records_read_back == 1
        assert result.last_record["audit_id"] == result.audit_record.audit_id
        assert result.last_record["package_id"] == result.package.simulation_id
        assert result.last_record["metadata"]["source"] == "slice_15c_simulated_execution_audit_integration"
        assert result.last_record["metadata"]["simulation_only"] is True
        assert result.last_record["secrets_included"] is False
        assert result.execution_endpoint_called is False

        assert_integration_report_is_safe(result.safe_report())

    print("[OK] default simulation package is written to audit log")


def test_permissive_config_still_audits_simulation_only() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_permissive.jsonl"
        result = build_and_audit_simulated_execution_package(
            sample_limit_input(),
            config=build_permissive_test_config(),
            risk_gate_ready=True,
            manual_approval_ready=True,
            audit_file_path=audit_file,
        )

        assert result.package.blocked is True
        assert result.package.simulation_only is True
        assert result.audit_record.risk_status == "ready"
        assert result.audit_record.manual_approval_status == "ready"
        assert result.audit_record.final_status == "blocked_simulation_only"
        assert result.records_read_back == 1
        assert result.execution_endpoint_called is False

    print("[OK] permissive config still audits simulation-only package")


def test_dangerous_environment_is_redacted_in_audit_reasons() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_dangerous_env.jsonl"
        result = build_and_audit_simulated_execution_package(
            sample_limit_input(),
            env={"KRAKEN_WITHDRAW_PERMISSION": "true"},
            audit_file_path=audit_file,
        )

        reason_text = " ".join(result.audit_record.reasons).lower()
        assert "withdraw" not in reason_text
        assert "restricted account-permission term detected" in reason_text
        assert result.package.blocked is True
        assert result.records_read_back == 1

    print("[OK] dangerous environment reason is redacted for audit log")


def test_bad_order_input_is_not_written_as_valid_audit_record() -> None:
    with TemporaryDirectory() as temp_dir:
        audit_file = Path(temp_dir) / "slice_15c_bad_input.jsonl"
        bad_input = ManualLiveOrderSimulationInput(
            pair="",
            side="hold",
            order_type="limit",
            volume="0",
            limit_price="",
        )

        try:
            build_and_audit_simulated_execution_package(
                bad_input,
                audit_file_path=audit_file,
            )
        except Exception as exc:  # noqa: BLE001 - validation may fail in either layer
            assert "pair" in str(exc).lower() or "side" in str(exc).lower()
            print(f"[OK] invalid order input cannot become valid audit record: blocked safely ({exc})")
            return

        raise AssertionError("Invalid order input unexpectedly became an audit record")


def test_sanitize_reasons_for_audit_removes_restricted_terms() -> None:
    safe = sanitize_reasons_for_audit(
        (
            "normal blocked reason",
            "restricted permission mentioned in reason",
            "account transfer behavior was blocked",
        )
    )

    joined = " ".join(safe).lower()
    assert "normal blocked reason" in joined
    assert "transfer" not in joined
    assert "restricted account-permission term detected" in joined

    print("[OK] audit reason sanitizer removes restricted terms")


def test_integration_source_contains_no_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/simulated_execution_audit_integration.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdrawfunds",
        "depositmethods",
        "wallettransfer",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] integration source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15C validation: Simulated Execution Package Audit Integration")
    print("=" * 80)

    test_default_simulation_package_is_written_to_audit_log()
    test_permissive_config_still_audits_simulation_only()
    test_dangerous_environment_is_redacted_in_audit_reasons()
    test_bad_order_input_is_not_written_as_valid_audit_record()
    test_sanitize_reasons_for_audit_removes_restricted_terms()
    test_integration_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15C simulated execution audit integration validation passed.")
    print("[PASS] Simulation packages are converted into safe local audit records.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
