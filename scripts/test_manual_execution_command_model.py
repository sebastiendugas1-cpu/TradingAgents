"""
Validation script for Slice 15D.

This test confirms the manual execution command model is valid, safe to log,
and non-executable by design.
"""

from __future__ import annotations

from tradingagents.execution.manual_execution_command import (
    ManualExecutionCommandError,
    ManualExecutionCommandStatus,
    build_manual_execution_command,
)


def expect_command_error(label: str, func) -> None:
    try:
        func()
    except ManualExecutionCommandError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected ManualExecutionCommandError")


def make_valid_command(**overrides):
    data = {
        "command_id": "cmd_slice_15d_001",
        "package_id": "pkg_slice_15a_001",
        "audit_id": "audit_slice_15b_001",
        "pair": "XBT/CAD",
        "side": "buy",
        "order_type": "limit",
        "volume": "0.000085168",
        "limit_price": "100000",
        "status": ManualExecutionCommandStatus.READY_FOR_REVIEW,
        "reasons": (),
        "metadata": {"source": "slice_15d_test"},
    }
    data.update(overrides)
    return build_manual_execution_command(**data)


def test_valid_command_safe_report() -> None:
    command = make_valid_command()

    assert command.command_id == "cmd_slice_15d_001"
    assert command.package_id == "pkg_slice_15a_001"
    assert command.audit_id == "audit_slice_15b_001"
    assert command.pair == "XBT/CAD"
    assert command.side == "buy"
    assert command.order_type == "limit"
    assert command.is_reviewable is True
    assert command.is_blocked is False

    report = command.safe_report()

    assert report["command_id"] == command.command_id
    assert report["package_id"] == command.package_id
    assert report["audit_id"] == command.audit_id
    assert report["credentials_included"] is False
    assert report["execution_enabled"] is False

    print("[OK] valid command safe report passed")


def test_command_is_non_executable() -> None:
    command = make_valid_command(
        status=ManualExecutionCommandStatus.APPROVED_FOR_FUTURE_EXECUTION
    )

    expect_command_error(
        "approved-for-future command remains non-executable",
        command.assert_not_executable,
    )


def test_blocked_command_state() -> None:
    command = make_valid_command(
        status=ManualExecutionCommandStatus.BLOCKED,
        reasons=("Readiness report is blocked.",),
    )

    assert command.is_blocked is True
    report = command.safe_report()
    assert report["blocked"] is True
    assert report["reason_count"] == 1

    print("[OK] blocked command state passed")


def test_invalid_commands_are_rejected() -> None:
    expect_command_error(
        "missing command_id rejected",
        lambda: make_valid_command(command_id=""),
    )
    expect_command_error(
        "missing package_id rejected",
        lambda: make_valid_command(package_id=""),
    )
    expect_command_error(
        "missing audit_id rejected",
        lambda: make_valid_command(audit_id=""),
    )
    expect_command_error(
        "missing pair rejected",
        lambda: make_valid_command(pair=""),
    )
    expect_command_error(
        "invalid side rejected",
        lambda: make_valid_command(side="hold"),
    )
    expect_command_error(
        "invalid order type rejected",
        lambda: make_valid_command(order_type="stop"),
    )
    expect_command_error(
        "zero volume rejected",
        lambda: make_valid_command(volume="0"),
    )
    expect_command_error(
        "missing limit price rejected",
        lambda: make_valid_command(order_type="limit", limit_price=None),
    )
    expect_command_error(
        "negative limit price rejected",
        lambda: make_valid_command(limit_price="-1"),
    )
    expect_command_error(
        "invalid status rejected",
        lambda: make_valid_command(status="live_now"),
    )


def test_sensitive_metadata_is_redacted() -> None:
    command = make_valid_command(
        metadata={
            "source": "slice_15d_test",
            "api_key": "abc123",
            "nested": {"token": "very-sensitive-value"},
        }
    )

    payload = command.to_dict()

    assert payload["metadata"]["api_key"] == "[REDACTED]"
    assert payload["metadata"]["nested"]["token"] == "[REDACTED]"
    assert payload["credentials_included"] is False
    assert payload["execution_enabled"] is False

    print("[OK] sensitive metadata is redacted")


def test_forbidden_command_terms_are_rejected() -> None:
    expect_command_error(
        "forbidden command term rejected",
        lambda: make_valid_command(reasons=("withdraw behavior is not allowed",)),
    )


def test_source_contains_no_private_execution_endpoint_names() -> None:
    from pathlib import Path

    source = Path(
        "tradingagents/execution/manual_execution_command.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdrawfunds",
        "depositmethods",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] command source contains no private execution endpoint names")


def main() -> None:
    print("Slice 15D validation: Manual Execution Command Model")
    print("=" * 80)

    test_valid_command_safe_report()
    test_command_is_non_executable()
    test_blocked_command_state()
    test_invalid_commands_are_rejected()
    test_sensitive_metadata_is_redacted()
    test_forbidden_command_terms_are_rejected()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 15D manual execution command model validation passed.")
    print("[PASS] Commands are safe to log and non-executable by design.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
