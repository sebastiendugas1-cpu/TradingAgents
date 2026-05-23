# ============================ Slice 12C-2 - Kraken Real Read-Only Client ============================
# Purpose:
# Creates a real Kraken private read-only client that can query balances, open orders,
# and trade history using read-only API keys from .env.
#
# Safety:
# - No order placement functions.
# - No cancellation functions.
# - No withdrawal/funding functions.
# - No secrets are printed.
# - Validation fails safely if credentials/permissions are missing.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_12c2_kraken_real_readonly_client.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$KrakenDir = Join-Path $ProjectRoot "tradingagents\kraken"
$ScriptsDir = Join-Path $ProjectRoot "scripts"
$DocsDir = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $KrakenDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-ProjectFile (Join-Path $KrakenDir "real_readonly.py") @'
# ============================ Kraken Real Read-Only Client ============================
"""
Real Kraken Spot REST read-only private client.

This module is intentionally limited to private read-only account endpoints:
- Balance
- OpenOrders
- TradesHistory

It does not implement:
- AddOrder
- CancelOrder
- Withdraw
- Funding operations
- Transfer operations

Secrets must come from environment variables or .env loading logic outside this module.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from typing import Any


KRAKEN_BASE_URL = "https://api.kraken.com"
DEFAULT_TIMEOUT_SECONDS = 20


class KrakenRealReadOnlyError(RuntimeError):
    """Raised when a real Kraken read-only API request fails."""


@dataclass(frozen=True)
class KrakenPrivateBalance:
    """Normalized Kraken account balance record."""

    asset: str
    balance: Decimal

    def to_dict(self) -> dict[str, str]:
        return {
            "asset": self.asset,
            "balance": str(self.balance),
        }


@dataclass(frozen=True)
class KrakenPrivateOpenOrder:
    """Normalized subset of a Kraken open order."""

    order_id: str
    pair: str | None
    side: str | None
    order_type: str | None
    volume: Decimal | None
    price: Decimal | None
    status: str | None
    raw: dict[str, Any] = field(repr=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "order_id": self.order_id,
            "pair": self.pair,
            "side": self.side,
            "order_type": self.order_type,
            "volume": str(self.volume) if self.volume is not None else None,
            "price": str(self.price) if self.price is not None else None,
            "status": self.status,
        }


@dataclass(frozen=True)
class KrakenPrivateTrade:
    """Normalized subset of a Kraken trade-history entry."""

    trade_id: str
    pair: str | None
    side: str | None
    order_type: str | None
    price: Decimal | None
    volume: Decimal | None
    fee: Decimal | None
    timestamp: float | None
    raw: dict[str, Any] = field(repr=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "trade_id": self.trade_id,
            "pair": self.pair,
            "side": self.side,
            "order_type": self.order_type,
            "price": str(self.price) if self.price is not None else None,
            "volume": str(self.volume) if self.volume is not None else None,
            "fee": str(self.fee) if self.fee is not None else None,
            "timestamp": self.timestamp,
        }


@dataclass(frozen=True)
class KrakenReadOnlySnapshot:
    """Read-only private account snapshot.

    This object intentionally does not include API keys or secrets.
    """

    source: str
    balances: list[KrakenPrivateBalance]
    open_orders: list[KrakenPrivateOpenOrder]
    trade_history: list[KrakenPrivateTrade]

    def to_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "balances": [item.to_dict() for item in self.balances],
            "open_orders": [item.to_dict() for item in self.open_orders],
            "trade_history": [item.to_dict() for item in self.trade_history],
        }


class KrakenRealReadOnlyClient:
    """Minimal real Kraken private read-only REST client."""

    def __init__(
        self,
        *,
        api_key: str,
        api_secret: str,
        base_url: str = KRAKEN_BASE_URL,
        timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    ) -> None:
        if not api_key or not api_key.strip():
            raise KrakenRealReadOnlyError("Kraken API key is required.")
        if not api_secret or not api_secret.strip():
            raise KrakenRealReadOnlyError("Kraken API secret is required.")

        self._api_key = api_key.strip()
        self._api_secret = api_secret.strip()
        self._base_url = base_url.rstrip("/")
        self._timeout_seconds = timeout_seconds

    @classmethod
    def from_env(cls) -> "KrakenRealReadOnlyClient":
        return cls(
            api_key=os.environ.get("KRAKEN_API_KEY", ""),
            api_secret=os.environ.get("KRAKEN_API_SECRET", ""),
        )

    def get_account_balance(self) -> list[KrakenPrivateBalance]:
        data = self._private_post("/0/private/Balance")
        result = data.get("result", {})

        if not isinstance(result, dict):
            raise KrakenRealReadOnlyError("Unexpected Kraken Balance response format.")

        balances: list[KrakenPrivateBalance] = []

        for asset, raw_balance in sorted(result.items()):
            balance = _safe_decimal(raw_balance)

            if balance is None:
                continue

            balances.append(
                KrakenPrivateBalance(
                    asset=str(asset),
                    balance=balance,
                )
            )

        return balances

    def get_open_orders(self) -> list[KrakenPrivateOpenOrder]:
        data = self._private_post("/0/private/OpenOrders")
        result = data.get("result", {})

        if not isinstance(result, dict):
            raise KrakenRealReadOnlyError("Unexpected Kraken OpenOrders response format.")

        open_orders = result.get("open", {})

        if not isinstance(open_orders, dict):
            raise KrakenRealReadOnlyError("Unexpected Kraken OpenOrders result format.")

        normalized: list[KrakenPrivateOpenOrder] = []

        for order_id, raw_order in sorted(open_orders.items()):
            if not isinstance(raw_order, dict):
                continue

            descr = raw_order.get("descr", {})
            if not isinstance(descr, dict):
                descr = {}

            normalized.append(
                KrakenPrivateOpenOrder(
                    order_id=str(order_id),
                    pair=_optional_str(descr.get("pair")),
                    side=_optional_str(descr.get("type")),
                    order_type=_optional_str(descr.get("ordertype")),
                    volume=_safe_decimal(raw_order.get("vol")),
                    price=_safe_decimal(descr.get("price")),
                    status=_optional_str(raw_order.get("status")),
                    raw=raw_order,
                )
            )

        return normalized

    def get_trade_history(self, *, count: int = 25) -> list[KrakenPrivateTrade]:
        if count < 1 or count > 50:
            raise KrakenRealReadOnlyError("count must be between 1 and 50.")

        data = self._private_post("/0/private/TradesHistory", {"trades": "true"})
        result = data.get("result", {})

        if not isinstance(result, dict):
            raise KrakenRealReadOnlyError("Unexpected Kraken TradesHistory response format.")

        trades = result.get("trades", {})

        if not isinstance(trades, dict):
            raise KrakenRealReadOnlyError("Unexpected Kraken TradesHistory trades format.")

        normalized: list[KrakenPrivateTrade] = []

        for trade_id, raw_trade in list(sorted(trades.items()))[-count:]:
            if not isinstance(raw_trade, dict):
                continue

            normalized.append(
                KrakenPrivateTrade(
                    trade_id=str(trade_id),
                    pair=_optional_str(raw_trade.get("pair")),
                    side=_optional_str(raw_trade.get("type")),
                    order_type=_optional_str(raw_trade.get("ordertype")),
                    price=_safe_decimal(raw_trade.get("price")),
                    volume=_safe_decimal(raw_trade.get("vol")),
                    fee=_safe_decimal(raw_trade.get("fee")),
                    timestamp=_safe_float(raw_trade.get("time")),
                    raw=raw_trade,
                )
            )

        return normalized

    def get_snapshot(self) -> KrakenReadOnlySnapshot:
        return KrakenReadOnlySnapshot(
            source="kraken_real_readonly",
            balances=self.get_account_balance(),
            open_orders=self.get_open_orders(),
            trade_history=self.get_trade_history(count=25),
        )

    def _private_post(self, uri_path: str, payload: dict[str, str] | None = None) -> dict[str, Any]:
        payload = dict(payload or {})
        payload["nonce"] = str(time.time_ns())

        encoded_payload = urllib.parse.urlencode(payload)
        signature = self._sign(uri_path, encoded_payload, payload["nonce"])

        request = urllib.request.Request(
            url=f"{self._base_url}{uri_path}",
            data=encoded_payload.encode("utf-8"),
            method="POST",
            headers={
                "API-Key": self._api_key,
                "API-Sign": signature,
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": "TradingAgents-ReadOnly/1.0",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=self._timeout_seconds) as response:
                raw_body = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raise KrakenRealReadOnlyError(f"Kraken HTTP error {exc.code} for {uri_path}") from exc
        except urllib.error.URLError as exc:
            raise KrakenRealReadOnlyError(f"Kraken connection error for {uri_path}: {exc}") from exc

        try:
            data = json.loads(raw_body)
        except json.JSONDecodeError as exc:
            raise KrakenRealReadOnlyError(f"Kraken returned invalid JSON for {uri_path}") from exc

        errors = data.get("error", [])

        if errors:
            raise KrakenRealReadOnlyError(f"Kraken API error for {uri_path}: {errors}")

        return data

    def _sign(self, uri_path: str, encoded_payload: str, nonce: str) -> str:
        encoded = (nonce + encoded_payload).encode("utf-8")
        message = uri_path.encode("utf-8") + hashlib.sha256(encoded).digest()

        try:
            secret = base64.b64decode(self._api_secret)
        except Exception as exc:
            raise KrakenRealReadOnlyError("Kraken API secret is not valid base64.") from exc

        mac = hmac.new(secret, message, hashlib.sha512)
        return base64.b64encode(mac.digest()).decode("utf-8")


def _safe_decimal(value: Any) -> Decimal | None:
    if value is None:
        return None

    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def _safe_float(value: Any) -> float | None:
    if value is None:
        return None

    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _optional_str(value: Any) -> str | None:
    if value is None:
        return None

    text = str(value).strip()
    return text or None
'@

Write-ProjectFile (Join-Path $KrakenDir "__init__.py") @'
# ============================ Kraken Package Exports ============================

from tradingagents.kraken.config import KrakenConfigError, KrakenReadOnlyConfig
from tradingagents.kraken.env_validation import KrakenReadOnlyEnvReport, validate_kraken_readonly_env
from tradingagents.kraken.private_readonly import (
    KrakenReadOnlyClient,
    KrakenReadOnlyMode,
    KrakenReadOnlyOperationBlocked,
)
from tradingagents.kraken.real_readonly import (
    KrakenPrivateBalance,
    KrakenPrivateOpenOrder,
    KrakenPrivateTrade,
    KrakenReadOnlySnapshot,
    KrakenRealReadOnlyClient,
    KrakenRealReadOnlyError,
)

__all__ = [
    "KrakenConfigError",
    "KrakenReadOnlyConfig",
    "KrakenReadOnlyEnvReport",
    "validate_kraken_readonly_env",
    "KrakenReadOnlyClient",
    "KrakenReadOnlyMode",
    "KrakenReadOnlyOperationBlocked",
    "KrakenPrivateBalance",
    "KrakenPrivateOpenOrder",
    "KrakenPrivateTrade",
    "KrakenReadOnlySnapshot",
    "KrakenRealReadOnlyClient",
    "KrakenRealReadOnlyError",
]
'@

Write-ProjectFile (Join-Path $ScriptsDir "test_kraken_real_readonly_client.py") @'
# ============================ Slice 12C-2 Validation - Kraken Real Read-Only Client ============================

from __future__ import annotations

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.kraken.env_validation import validate_kraken_readonly_env  # noqa: E402
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

    report = validate_kraken_readonly_env(require_keys=True)

    assert_true(report.has_api_key, "Kraken API key detected")
    assert_true(report.has_api_secret, "Kraken API secret detected")
    assert_true(report.ready_for_readonly_client, "read-only environment is ready")
    assert_true(not report.trading_enabled, "trading disabled")
    assert_true(not report.withdrawals_enabled, "withdrawals disabled")
    assert_true(not report.funding_enabled, "funding disabled")
    assert_true("KRAKEN_API_KEY" not in str(report.to_safe_dict()), "safe report does not reveal key name/value")

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
'@

# Update docs with a concise decision-log entry.
$DecisionLogPath = Join-Path $DocsDir "11_DECISION_LOG.md"
Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 12C-2: Real Kraken Read-Only Client

Decision:

Added a real Kraken private read-only client.

Safety boundaries:

- Balance reading only.
- Open-order reading only.
- Trade-history reading only.
- No order placement.
- No cancellation.
- No withdrawal.
- No funding operation.
- No secrets printed in validation.
'@

$RoadmapPath = Join-Path $DocsDir "03_ROADMAP.md"
Add-Content -Path $RoadmapPath -Encoding UTF8 -Value @'

## Slice 12C-2 — Real Kraken Read-Only Client

Status: Complete when validation passes.

Goal:

Read balances, open orders, and recent trade history from Kraken using read-only credentials.

Forbidden:

- Place orders.
- Cancel orders.
- Withdraw funds.
- Funding operations.
- Trading permissions.

Validation command:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python .\scripts\test_kraken_real_readonly_client.py
```

Commit message:

```text
Add Kraken real read-only client
```
'@

Write-Host "=== SLICE 12C-2 FILES CREATED ==="
Get-ChildItem $KrakenDir | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 12C-2 VALIDATION ==="
python .\scripts\test_kraken_real_readonly_client.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 12C-2 script completed."
