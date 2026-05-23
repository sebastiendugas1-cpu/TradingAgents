# ============================ Slice 12C-2 Validation - Kraken Real Read-Only Client ============================

from __future__ import annotations

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken.env_validation import validate_kraken_readonly_environment  # noqa: E402
from tradingagents.kraken.real_readonly import KrakenRealReadOnlyClient, KrakenRealReadOnlyError  # noqa: E402


ENV_FILE = PROJECT_ROOT / ".env"


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        if key and key not in os.environ:
            os.environ[key] = value


def assert_true(value, label: str) -> None:
    if not value:
        raise AssertionError(f"{label}: expected truthy value, got {value!r}")

    print(f"[OK] {label}: {value!r}")


def assert_equal(actual, expected, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")

    print(f"[OK] {label}: {actual!r}")


def main() -> int:
    print("Running Slice 12C-2 Kraken real read-only client validation...")

    load_env_file(ENV_FILE)

    report = validate_kraken_readonly_environment(env_file=PROJECT_ROOT / '.env', require_keys=True)

    assert_true(report.has_api_key, "Kraken API key detected")
    assert_true(report.has_api_secret, "Kraken API secret detected")
    assert_true(report.is_ready_for_readonly_private_client, "read-only environment is ready")
    assert_true(not report.trading_enabled, "trading disabled")
    assert_true(not report.withdrawals_enabled, "withdrawals disabled")
    assert_true(not report.funding_enabled, "funding disabled")
    assert_true("KRAKEN_API_KEY" not in str(report.to_dict()), "safe report does not reveal key name/value")

    client = KrakenRealReadOnlyClient.from_env()

    balances = client.get_account_balance()
    print(f"[OK] balance call succeeded: {len(balances)} balance rows")

    open_orders = client.get_open_orders()
    print(f"[OK] open orders call succeeded: {len(open_orders)} open order rows")

    trade_history = client.get_trade_history(count=25)
    print(f"[OK] trade history call succeeded: {len(trade_history)} trade rows")

    snapshot = client.get_snapshot()

    assert_equal(snapshot.source, "kraken_real_readonly", "snapshot source")
    assert_equal(len(snapshot.balances), len(balances), "snapshot balance count")
    assert_equal(len(snapshot.open_orders), len(open_orders), "snapshot open order count")
    assert_true("secret" not in str(snapshot.to_dict()).lower(), "snapshot does not reveal secrets")
    assert_true("api" not in str(snapshot.to_dict()).lower(), "snapshot does not mention API keys")

    print("Kraken real read-only client validation passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KrakenRealReadOnlyError as exc:
        print(f"[FAIL] Kraken read-only API call failed safely: {exc}")
        raise SystemExit(1)




