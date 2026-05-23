# ============================ Slice 5 - Local Market Data Cache ============================
# Purpose:
# Creates a local market data cache layer for TradingAgents.
# This is public-data only. No private API keys. No trading.

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
Set-Location $ProjectRoot

$CacheDir = Join-Path $ProjectRoot "tradingagents\marketdata"
$ScriptsDir = Join-Path $ProjectRoot "scripts"
$DocsDir = Join-Path $ProjectRoot "docs"

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
New-Item -ItemType Directory -Force -Path $DocsDir | Out-Null

# ============================ Update .gitignore ============================
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
$GitIgnoreText = ""
if (Test-Path $GitIgnorePath) {
    $GitIgnoreText = Get-Content $GitIgnorePath -Raw
}
if ($GitIgnoreText -notmatch "(?m)^\.data-cache/$") {
    Add-Content -Path $GitIgnorePath -Value "`n# Local market data cache`n.data-cache/"
}

# ============================ Create cache.py ============================
$CachePy = @'
"""Local market data cache utilities.

This module stores public market data snapshots locally so repeated development
and testing does not hammer remote APIs unnecessarily.

Safety:
- No private API keys.
- No exchange account data.
- No order execution.
- Cache files are intended to be ignored by Git.
"""

from __future__ import annotations

import json
import re
import shutil
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CACHE_ROOT = PROJECT_ROOT / ".data-cache" / "marketdata"


class MarketDataCacheError(RuntimeError):
    """Raised when market data cache operations fail."""


@dataclass(frozen=True)
class CacheRecord:
    """Structured cache record wrapper."""

    source: str
    kind: str
    symbol: str
    created_at_utc: str
    payload: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class MarketDataCache:
    """Simple JSON-file market data cache."""

    def __init__(self, root: Path | str = DEFAULT_CACHE_ROOT) -> None:
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def make_key(self, source: str, kind: str, symbol: str, extra: str | None = None) -> Path:
        source_part = _safe_path_part(source)
        kind_part = _safe_path_part(kind)
        symbol_part = _safe_path_part(symbol)
        name = symbol_part if not extra else f"{symbol_part}_{_safe_path_part(extra)}"
        return self.root / source_part / kind_part / f"{name}.json"

    def write(
        self,
        *,
        source: str,
        kind: str,
        symbol: str,
        payload: dict[str, Any],
        extra: str | None = None,
    ) -> Path:
        path = self.make_key(source, kind, symbol, extra)
        path.parent.mkdir(parents=True, exist_ok=True)

        record = CacheRecord(
            source=source,
            kind=kind,
            symbol=symbol,
            created_at_utc=_utc_now_iso(),
            payload=payload,
        )

        path.write_text(json.dumps(record.to_dict(), indent=2, sort_keys=True), encoding="utf-8")
        return path

    def read(
        self,
        *,
        source: str,
        kind: str,
        symbol: str,
        extra: str | None = None,
    ) -> CacheRecord | None:
        path = self.make_key(source, kind, symbol, extra)
        if not path.exists():
            return None

        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            return CacheRecord(
                source=str(raw["source"]),
                kind=str(raw["kind"]),
                symbol=str(raw["symbol"]),
                created_at_utc=str(raw["created_at_utc"]),
                payload=dict(raw["payload"]),
            )
        except Exception as exc:  # noqa: BLE001
            raise MarketDataCacheError(f"Failed to read cache file {path}: {exc}") from exc

    def is_stale(
        self,
        record: CacheRecord | None,
        *,
        max_age_seconds: int,
    ) -> bool:
        if record is None:
            return True

        created = datetime.fromisoformat(record.created_at_utc.replace("Z", "+00:00"))
        age = datetime.now(timezone.utc) - created
        return age.total_seconds() > max_age_seconds

    def clear(self) -> None:
        if self.root.exists():
            shutil.rmtree(self.root)
        self.root.mkdir(parents=True, exist_ok=True)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _safe_path_part(value: str) -> str:
    cleaned = value.strip().upper().replace("/", "-").replace(":", "-")
    cleaned = re.sub(r"[^A-Z0-9._-]+", "-", cleaned)
    cleaned = cleaned.strip(".-_")
    if not cleaned:
        raise MarketDataCacheError(f"Invalid cache key part: {value!r}")
    return cleaned
'@
Set-Content -Path (Join-Path $CacheDir "cache.py") -Value $CachePy -Encoding UTF8

# ============================ Update marketdata __init__.py ============================
$InitPath = Join-Path $CacheDir "__init__.py"
$InitText = @'
"""Market data adapters and cache utilities."""

from tradingagents.marketdata.cache import CacheRecord, MarketDataCache, MarketDataCacheError
from tradingagents.marketdata.kraken_public import KrakenPublicClient, KrakenPublicDataError

__all__ = [
    "CacheRecord",
    "MarketDataCache",
    "MarketDataCacheError",
    "KrakenPublicClient",
    "KrakenPublicDataError",
]
'@
Set-Content -Path $InitPath -Value $InitText -Encoding UTF8

# ============================ Create validation script ============================
$TestPy = @'
# ============================ Slice 5 Market Data Cache Validation ============================

from __future__ import annotations

import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from tradingagents.marketdata.cache import MarketDataCache  # noqa: E402


def main() -> int:
    print("Running Slice 5 market data cache validation...")

    cache = MarketDataCache(PROJECT_ROOT / ".data-cache" / "marketdata-test")
    cache.clear()

    payload = {
        "pair": "XXBTZUSD",
        "last": "75379.4",
        "bid": "75379.3",
        "ask": "75379.5",
    }

    path = cache.write(source="kraken", kind="ticker", symbol="BTC/USD", payload=payload)
    print(f"[OK] Wrote cache file: {path.relative_to(PROJECT_ROOT)}")

    record = cache.read(source="kraken", kind="ticker", symbol="BTC/USD")
    if record is None:
        print("[FAIL] Cache read returned None")
        return 1

    if record.payload != payload:
        print(f"[FAIL] Cache payload mismatch: {record.payload}")
        return 1

    print(f"[OK] Read cache record: source={record.source}, kind={record.kind}, symbol={record.symbol}")

    if cache.is_stale(record, max_age_seconds=3600):
        print("[FAIL] Fresh cache record was marked stale")
        return 1

    print("[OK] Fresh cache record is not stale")

    time.sleep(1)
    if not cache.is_stale(record, max_age_seconds=0):
        print("[FAIL] Cache record should be stale with max_age_seconds=0")
        return 1

    print("[OK] Stale cache detection works")

    ohlcv_path = cache.write(
        source="kraken",
        kind="ohlcv",
        symbol="BTC/USD",
        extra="60m",
        payload={"candles": [[1, "1", "2", "0.5", "1.5", "10", "100"]]},
    )
    print(f"[OK] Wrote OHLCV cache file: {ohlcv_path.relative_to(PROJECT_ROOT)}")

    cache.clear()
    missing = cache.read(source="kraken", kind="ticker", symbol="BTC/USD")
    if missing is not None:
        print("[FAIL] Cache clear did not remove ticker record")
        return 1

    print("[OK] Cache clear works")
    print("Market data cache validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@
Set-Content -Path (Join-Path $ScriptsDir "test_market_data_cache.py") -Value $TestPy -Encoding UTF8

# ============================ Update decision log ============================
$DecisionLogPath = Join-Path $DocsDir "11_DECISION_LOG.md"
$DecisionLogText = Get-Content $DecisionLogPath -Raw
if ($DecisionLogText -notmatch "Slice 5 — Local Market Data Cache") {
    Add-Content -Path $DecisionLogPath -Value @'

## 2026-05-22 — Slice 5 — Local Market Data Cache

Decision:

Add a local JSON-file market data cache for public market data snapshots.

Key points:

- Cache is local only and ignored by Git under `.data-cache/`.
- Cache supports ticker and OHLCV-style payloads.
- Cache has stale-data detection.
- Cache can be cleared manually.
- No private API data, balances, orders, or execution are included.
'@
}

Write-Host "=== SLICE 5 FILES CREATED ==="
Get-ChildItem $CacheDir | Select-Object Name, Length, LastWriteTime
Get-ChildItem $ScriptsDir -Filter "*market_data_cache*" | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 5 VALIDATION ==="
python .\scripts\test_market_data_cache.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 5 script completed."
