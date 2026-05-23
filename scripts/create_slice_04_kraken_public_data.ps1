# ============================ Slice 4 - Create Kraken Public Market Data Adapter ============================
# Purpose:
# Creates a public-data-only Kraken adapter.
#
# Safety:
# - No private Kraken API key.
# - No balances.
# - No orders.
# - No execution.
# - Public market data only.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_04_kraken_public_data.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$MarketDataPath = Join-Path $ProjectRoot "tradingagents\marketdata"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $MarketDataPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-ProjectFile (Join-Path $MarketDataPath "__init__.py") @'
"""Market data adapters for the TradingAgents multi-asset project."""

from .kraken_public import (
    KrakenOhlcCandle,
    KrakenPublicClient,
    KrakenPublicError,
    KrakenTicker,
)

__all__ = [
    "KrakenOhlcCandle",
    "KrakenPublicClient",
    "KrakenPublicError",
    "KrakenTicker",
]
'@

Write-ProjectFile (Join-Path $MarketDataPath "kraken_public.py") @'
# ============================ Kraken Public Market Data Adapter ============================
"""
Public-data-only Kraken market data adapter.

Safety:
- Uses only Kraken public REST endpoints.
- Does not use API keys.
- Does not read balances.
- Does not place, edit, or cancel orders.

Initial supported functions:
- get_server_time()
- get_asset_pairs()
- resolve_pair(symbol)
- get_ticker(symbol)
- get_ohlcv(symbol, interval_minutes=60, since=None)
"""

from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any
from urllib import parse, request
from urllib.error import HTTPError, URLError

from tradingagents.assets import AssetIdentifier, AssetType, normalize_asset_symbol


KRAKEN_PUBLIC_BASE_URL = "https://api.kraken.com/0/public"


class KrakenPublicError(RuntimeError):
    """Raised when a Kraken public market data request fails."""


@dataclass(frozen=True)
class KrakenTicker:
    """Normalized Kraken ticker snapshot."""

    requested_symbol: str
    normalized_symbol: str
    kraken_pair_key: str
    last_price: float
    bid: float | None
    ask: float | None
    volume_today: float | None
    raw: dict[str, Any]


@dataclass(frozen=True)
class KrakenOhlcCandle:
    """Normalized OHLC candle from Kraken."""

    time: int
    open: float
    high: float
    low: float
    close: float
    vwap: float
    volume: float
    count: int


class KrakenPublicClient:
    """Small public REST client for Kraken market data."""

    def __init__(self, base_url: str = KRAKEN_PUBLIC_BASE_URL, timeout_seconds: int = 20) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    def get_server_time(self) -> dict[str, Any]:
        """Return Kraken server time response."""
        return self._public_get("Time")

    def get_asset_pairs(self) -> dict[str, dict[str, Any]]:
        """Return Kraken tradable asset pairs."""
        response = self._public_get("AssetPairs")
        result = response.get("result", {})

        if not isinstance(result, dict):
            raise KrakenPublicError("Unexpected AssetPairs response format.")

        return result

    def resolve_pair(self, symbol: str) -> str:
        """
        Resolve a normalized internal symbol such as BTC/USD into a Kraken pair key.

        Kraken has legacy naming in some places, for example XBT instead of BTC.
        This method checks wsname, altname, and pair keys.
        """
        asset = normalize_asset_symbol(symbol)

        if asset.asset_type != AssetType.CRYPTO:
            raise KrakenPublicError(
                f"Kraken public adapter currently supports crypto pairs only. Got: {symbol!r}"
            )

        if not asset.quote:
            raise KrakenPublicError(f"Crypto symbol has no quote currency: {symbol!r}")

        pairs = self.get_asset_pairs()
        candidates = self._pair_candidates(asset)

        for pair_key, pair_data in pairs.items():
            wsname = str(pair_data.get("wsname", "")).upper()
            altname = str(pair_data.get("altname", "")).upper()
            key = str(pair_key).upper()

            searchable = {
                wsname,
                altname,
                key,
                wsname.replace("/", ""),
                altname.replace("/", ""),
                key.replace("/", ""),
            }

            if candidates.intersection(searchable):
                return pair_key

        raise KrakenPublicError(
            f"Could not resolve {symbol!r} to a Kraken pair. Tried candidates: {sorted(candidates)}"
        )

    def get_ticker(self, symbol: str) -> KrakenTicker:
        """Return a normalized ticker snapshot for a symbol."""
        pair_key = self.resolve_pair(symbol)
        asset = normalize_asset_symbol(symbol)

        response = self._public_get("Ticker", {"pair": pair_key})
        result = response.get("result", {})

        if not isinstance(result, dict) or not result:
            raise KrakenPublicError(f"Unexpected ticker response for {symbol!r}: {response!r}")

        returned_pair_key = next(iter(result.keys()))
        raw_ticker = result[returned_pair_key]

        return KrakenTicker(
            requested_symbol=symbol,
            normalized_symbol=asset.normalized,
            kraken_pair_key=returned_pair_key,
            last_price=self._safe_float(raw_ticker.get("c", [None])[0]),
            bid=self._safe_float(raw_ticker.get("b", [None])[0]),
            ask=self._safe_float(raw_ticker.get("a", [None])[0]),
            volume_today=self._safe_float(raw_ticker.get("v", [None, None])[1]),
            raw=raw_ticker,
        )

    def get_ohlcv(
        self,
        symbol: str,
        interval_minutes: int = 60,
        since: int | None = None,
    ) -> list[KrakenOhlcCandle]:
        """Return recent OHLCV candles for a symbol."""
        pair_key = self.resolve_pair(symbol)

        params: dict[str, Any] = {
            "pair": pair_key,
            "interval": interval_minutes,
        }

        if since is not None:
            params["since"] = since

        response = self._public_get("OHLC", params)
        result = response.get("result", {})

        if not isinstance(result, dict):
            raise KrakenPublicError(f"Unexpected OHLC response for {symbol!r}: {response!r}")

        candle_rows: list[list[Any]] | None = None

        for key, value in result.items():
            if key == "last":
                continue

            if isinstance(value, list):
                candle_rows = value
                break

        if candle_rows is None:
            raise KrakenPublicError(f"No OHLC candle data returned for {symbol!r}.")

        candles: list[KrakenOhlcCandle] = []

        for row in candle_rows:
            if len(row) < 8:
                continue

            candles.append(
                KrakenOhlcCandle(
                    time=int(row[0]),
                    open=float(row[1]),
                    high=float(row[2]),
                    low=float(row[3]),
                    close=float(row[4]),
                    vwap=float(row[5]),
                    volume=float(row[6]),
                    count=int(row[7]),
                )
            )

        return candles

    def _public_get(self, endpoint: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        query = ""

        if params:
            query = "?" + parse.urlencode(params)

        url = f"{self.base_url}/{endpoint}{query}"

        try:
            with request.urlopen(url, timeout=self.timeout_seconds) as response:
                payload = response.read().decode("utf-8")
        except HTTPError as exc:
            raise KrakenPublicError(f"Kraken HTTP error {exc.code} for {url}") from exc
        except URLError as exc:
            raise KrakenPublicError(f"Kraken connection error for {url}: {exc}") from exc

        try:
            data = json.loads(payload)
        except json.JSONDecodeError as exc:
            raise KrakenPublicError(f"Kraken returned invalid JSON for {url}") from exc

        errors = data.get("error", [])

        if errors:
            raise KrakenPublicError(f"Kraken API error for {endpoint}: {errors}")

        return data

    def _pair_candidates(self, asset: AssetIdentifier) -> set[str]:
        base = asset.base.upper()
        quote = (asset.quote or "").upper()

        bases = {base}
        quotes = {quote}

        if base == "BTC":
            bases.add("XBT")
        if base == "XBT":
            bases.add("BTC")

        candidates: set[str] = set()

        for b in bases:
            for q in quotes:
                candidates.add(f"{b}/{q}")
                candidates.add(f"{b}{q}")
                candidates.add(f"X{b}Z{q}")
                candidates.add(f"{b}Z{q}")
                candidates.add(f"X{b}{q}")

        candidates.add(asset.normalized.upper())
        candidates.add(asset.normalized.upper().replace("/", ""))

        return {candidate for candidate in candidates if candidate}

    @staticmethod
    def _safe_float(value: Any) -> float | None:
        if value is None:
            return None

        try:
            return float(value)
        except (TypeError, ValueError):
            return None
'@

Write-ProjectFile (Join-Path $ScriptsPath "test_kraken_public_data.py") @'
# ============================ Slice 4 - Kraken Public Data Validation ============================
"""
Validation script for the public-data-only Kraken adapter.

This script:
- Uses no Kraken API key.
- Does not access private account data.
- Does not place orders.
"""

from __future__ import annotations

import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))


from tradingagents.marketdata import KrakenPublicClient, KrakenPublicError  # noqa: E402


def main() -> int:
    print("Running Slice 4 Kraken public market data validation...")

    client = KrakenPublicClient(timeout_seconds=20)

    failures = 0

    try:
        server_time = client.get_server_time()
        print(f"[OK] Server time response keys: {list(server_time.keys())}")
    except KrakenPublicError as exc:
        failures += 1
        print(f"[FAIL] get_server_time: {exc}")

    for symbol in ["BTC/USD", "ETH/USD"]:
        try:
            pair_key = client.resolve_pair(symbol)
            print(f"[OK] {symbol} resolved to Kraken pair: {pair_key}")
        except KrakenPublicError as exc:
            failures += 1
            print(f"[FAIL] resolve_pair({symbol!r}): {exc}")

    try:
        ticker = client.get_ticker("BTC/USD")
        print(
            "[OK] BTC/USD ticker: "
            f"pair={ticker.kraken_pair_key}, "
            f"last={ticker.last_price}, "
            f"bid={ticker.bid}, "
            f"ask={ticker.ask}"
        )
    except KrakenPublicError as exc:
        failures += 1
        print(f"[FAIL] get_ticker('BTC/USD'): {exc}")

    try:
        candles = client.get_ohlcv("BTC/USD", interval_minutes=60)
        if not candles:
            failures += 1
            print("[FAIL] get_ohlcv('BTC/USD'): no candles returned")
        else:
            latest = candles[-1]
            print(
                "[OK] BTC/USD OHLCV: "
                f"candles={len(candles)}, "
                f"latest_time={latest.time}, "
                f"latest_close={latest.close}"
            )
    except KrakenPublicError as exc:
        failures += 1
        print(f"[FAIL] get_ohlcv('BTC/USD'): {exc}")

    try:
        client.resolve_pair("AAPL")
        failures += 1
        print("[FAIL] resolve_pair('AAPL'): expected traditional asset rejection")
    except KrakenPublicError:
        print("[OK] Traditional symbol AAPL rejected by Kraken crypto adapter")

    print()
    print(f"Failures: {failures}")

    if failures:
        print("Kraken public data validation failed.")
        return 1

    print("Kraken public data validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

$DecisionLog = Join-Path $DocsPath "11_DECISION_LOG.md"
$DecisionText = Get-Content $DecisionLog -Raw

if ($DecisionText -notmatch "Slice 4 — Kraken Public Market Data Adapter")
{
    Add-Content -Path $DecisionLog -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 4 — Kraken Public Market Data Adapter

Decision:

Add a public-data-only Kraken adapter.

Scope:

- Public REST endpoints only.
- No Kraken API key.
- No private account data.
- No balances.
- No order placement.
- No order cancellation.
- No live execution.

Initial functions:

- `get_server_time()`
- `get_asset_pairs()`
- `resolve_pair(symbol)`
- `get_ticker(symbol)`
- `get_ohlcv(symbol, interval_minutes=60)`

Validation:

- Resolve BTC/USD and ETH/USD.
- Fetch BTC/USD ticker.
- Fetch BTC/USD OHLCV candles.
- Reject traditional symbols such as AAPL in the Kraken crypto adapter.
'@
}

Write-Host "=== SLICE 4 FILES CREATED ==="
Get-ChildItem $MarketDataPath | Select-Object Name, Length, LastWriteTime
Get-ChildItem $ScriptsPath -Filter "*kraken*" | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 4 VALIDATION ==="
python .\scripts\test_kraken_public_data.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 4 script completed."
