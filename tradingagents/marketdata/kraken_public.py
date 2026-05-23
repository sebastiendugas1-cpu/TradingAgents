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
