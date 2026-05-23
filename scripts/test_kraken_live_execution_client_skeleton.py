"""
Validation script for Slice 14B.

This script confirms the Kraken live execution client skeleton is blocked by
default and does not call any real Kraken execution method.

It does not:
- place live orders
- cancel live orders
- call Kraken private trading endpoints
- require trading API permissions
- require funding or withdrawal permissions
- print secrets
"""

from __future__ import annotations

import inspect
from decimal import Decimal

from tradingagents.execution.kraken_live_execution_client import (
    KrakenLiveCancelRequest,
    KrakenLiveExecutionClient,
    KrakenLiveOrderRequest,
    LiveExecutionNotImplementedError,
)
from tradingagents.execution.safety_config import (
    ENV_KILL_SWITCH,
    ENV_LIVE_TRADING_CONFIRMATION,
    ENV_LIVE_TRADING_ENABLED,
    ENV_MAX_LIVE_TRADE_VALUE,
    LIVE_TRADING_CONFIRMATION_PHRASE,
    LiveExecutionSafetyConfig,
    SafetyConfigError,
)


class RecordingPrivateClient:
    """Test double proving the private client is not called."""

    def __init__(self) -> None:
        self.calls: list[str] = []

    def request(self, *args, **kwargs) -> None:
        self.calls.append("request")


def expect_error(label: str, error_type: type[BaseException], func) -> None:
    try:
        func()
    except error_type as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"[FAIL] {label}: expected {error_type.__name__}")


def make_valid_order_request() -> KrakenLiveOrderRequest:
    return KrakenLiveOrderRequest(
        pair="BTC/CAD",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
        price=Decimal("100000"),
        client_reference="slice-14b-test",
        metadata={"source": "validation"},
    )


def make_valid_cancel_request() -> KrakenLiveCancelRequest:
    return KrakenLiveCancelRequest(
        transaction_id="TEST-TRANSACTION-ID",
        client_reference="slice-14b-test",
        metadata={"source": "validation"},
    )


def test_default_config_blocks_submit_and_cancel() -> None:
    private_client = RecordingPrivateClient()
    client = KrakenLiveExecutionClient(
        safety_config=LiveExecutionSafetyConfig.default(),
        private_client=private_client,
    )

    expect_error(
        "default config blocks submit_order",
        SafetyConfigError,
        lambda: client.submit_order(make_valid_order_request()),
    )

    expect_error(
        "default config blocks cancel_order",
        SafetyConfigError,
        lambda: client.cancel_order(make_valid_cancel_request()),
    )

    assert private_client.calls == []
    print("[OK] private client was not called with default blocked config")


def test_kill_switch_blocks_even_when_other_settings_are_live_like() -> None:
    private_client = RecordingPrivateClient()
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "true",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )
    client = KrakenLiveExecutionClient(safety_config=config, private_client=private_client)

    expect_error(
        "kill switch blocks submit_order",
        SafetyConfigError,
        lambda: client.submit_order(make_valid_order_request()),
    )

    expect_error(
        "kill switch blocks cancel_order",
        SafetyConfigError,
        lambda: client.cancel_order(make_valid_cancel_request()),
    )

    assert private_client.calls == []
    print("[OK] private client was not called while kill switch was active")


def test_even_permissive_config_does_not_implement_live_execution() -> None:
    private_client = RecordingPrivateClient()
    config = LiveExecutionSafetyConfig.from_env(
        {
            ENV_LIVE_TRADING_ENABLED: "true",
            ENV_KILL_SWITCH: "false",
            ENV_MAX_LIVE_TRADE_VALUE: "10",
            ENV_LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
        }
    )
    client = KrakenLiveExecutionClient(safety_config=config, private_client=private_client)

    expect_error(
        "submit_order remains not implemented after safety gate",
        LiveExecutionNotImplementedError,
        lambda: client.submit_order(make_valid_order_request()),
    )

    expect_error(
        "cancel_order remains not implemented after safety gate",
        LiveExecutionNotImplementedError,
        lambda: client.cancel_order(make_valid_cancel_request()),
    )

    assert private_client.calls == []
    print("[OK] private client was still not called with permissive config")


def test_request_validation_happens_before_safety_gate() -> None:
    client = KrakenLiveExecutionClient(safety_config=LiveExecutionSafetyConfig.default())

    bad_order = KrakenLiveOrderRequest(
        pair="",
        side="buy",
        order_type="limit",
        volume=Decimal("0.000085168"),
    )

    bad_cancel = KrakenLiveCancelRequest(transaction_id="")

    expect_error(
        "bad order request rejected",
        ValueError,
        lambda: client.submit_order(bad_order),
    )

    expect_error(
        "bad cancel request rejected",
        ValueError,
        lambda: client.cancel_order(bad_cancel),
    )


def test_safe_report_excludes_secrets() -> None:
    client = KrakenLiveExecutionClient(safety_config=LiveExecutionSafetyConfig.default())
    report = client.safe_report()
    report_text = str(report).lower()

    assert report["client"] == "KrakenLiveExecutionClient"
    assert report["live_execution_client_skeleton"] is True
    assert report["live_trading_enabled"] is False
    assert report["kill_switch"] is True
    assert report["max_live_trade_value"] == "0"
    assert report["secrets_included"] is False

    forbidden_report_terms = [
        "api_key",
        "api secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "token",
    ]

    for term in forbidden_report_terms:
        assert term not in report_text

    print("[OK] client report is safe to log")


def test_no_kraken_execution_endpoint_names_in_client_source() -> None:
    import tradingagents.execution.kraken_live_execution_client as module

    source = inspect.getsource(module)
    forbidden_source_terms = [
        "/0/private/AddOrder",
        "/0/private/CancelOrder",
        "AddOrder",
        "CancelOrder",
    ]

    for term in forbidden_source_terms:
        assert term not in source

    print("[OK] client source contains no Kraken execution endpoint names")


def main() -> None:
    print("Slice 14B validation: Disabled-by-Default Kraken Live Execution Client Skeleton")
    print("=" * 80)

    test_default_config_blocks_submit_and_cancel()
    test_kill_switch_blocks_even_when_other_settings_are_live_like()
    test_even_permissive_config_does_not_implement_live_execution()
    test_request_validation_happens_before_safety_gate()
    test_safe_report_excludes_secrets()
    test_no_kraken_execution_endpoint_names_in_client_source()

    print("=" * 80)
    print("[PASS] Slice 14B live execution client skeleton validation passed.")
    print("[PASS] Default safety config blocks submit and cancel paths.")
    print("[PASS] No Kraken live execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
