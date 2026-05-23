# ============================ Slice 3 - Asset Model and Symbol Normalization ============================
# Purpose:
# Creates a small multi-asset symbol normalization layer for crypto and traditional assets.
#
# Run from:
# D:\Trading\TradingAgents
#
# Command:
# powershell -ExecutionPolicy Bypass -File .\scripts\create_slice_03_assets.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\Trading\TradingAgents"
$AssetsPath = Join-Path $ProjectRoot "tradingagents\assets"
$ScriptsPath = Join-Path $ProjectRoot "scripts"
$DocsPath = Join-Path $ProjectRoot "docs"

Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path $AssetsPath | Out-Null
New-Item -ItemType Directory -Force -Path $ScriptsPath | Out-Null

function Write-ProjectFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $Folder = Split-Path -Parent $Path
    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

Write-ProjectFile (Join-Path $AssetsPath "models.py") @'
# ============================ Asset Models ============================
"""
Shared asset models for the TradingAgents crypto / multi-asset project.

This module is intentionally small and dependency-free. It gives the rest of the
project one common way to represent assets before we connect external data
sources such as Kraken or TradingView.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class AssetType(StrEnum):
    """Supported high-level asset categories."""

    CRYPTO = "crypto"
    TRADITIONAL = "traditional"
    UNKNOWN = "unknown"


@dataclass(frozen=True, slots=True)
class AssetIdentifier:
    """Normalized representation of a tradable or analyzable asset.

    Attributes:
        original: The exact user-provided symbol.
        normalized: The internal canonical symbol, such as BTC/USD or AAPL.
        asset_type: High-level asset category.
        base: Base asset for crypto pairs or ticker for traditional assets.
        quote: Quote currency for crypto pairs, or None for traditional assets.
        venue_prefix: Optional TradingView-style prefix such as NASDAQ or KRAKEN.
    """

    original: str
    normalized: str
    asset_type: AssetType
    base: str
    quote: str | None = None
    venue_prefix: str | None = None

    @property
    def is_crypto(self) -> bool:
        return self.asset_type == AssetType.CRYPTO

    @property
    def is_traditional(self) -> bool:
        return self.asset_type == AssetType.TRADITIONAL

    def as_dict(self) -> dict[str, str | None]:
        """Return a JSON-friendly dictionary."""

        return {
            "original": self.original,
            "normalized": self.normalized,
            "asset_type": self.asset_type.value,
            "base": self.base,
            "quote": self.quote,
            "venue_prefix": self.venue_prefix,
        }
'@

Write-ProjectFile (Join-Path $AssetsPath "normalizer.py") @'
# ============================ Asset Symbol Normalizer ============================
"""
Asset symbol normalization for crypto and traditional assets.

Examples:
    BTC/USD        -> BTC/USD, crypto
    btc-usd        -> BTC/USD, crypto
    BTCUSD         -> BTC/USD, crypto
    KRAKEN:BTCUSD  -> BTC/USD, crypto, venue_prefix=KRAKEN
    XBT/USD        -> BTC/USD, crypto
    AAPL           -> AAPL, traditional
    NASDAQ:AAPL    -> AAPL, traditional, venue_prefix=NASDAQ
"""

from __future__ import annotations

import re

from tradingagents.assets.models import AssetIdentifier, AssetType


CRYPTO_BASE_ALIASES: dict[str, str] = {
    "XBT": "BTC",
    "XXBT": "BTC",
    "XDG": "DOGE",
}

KNOWN_CRYPTO_BASES: set[str] = {
    "AAVE",
    "ADA",
    "ARB",
    "ATOM",
    "AVAX",
    "BCH",
    "BTC",
    "DOGE",
    "DOT",
    "ETC",
    "ETH",
    "FIL",
    "LINK",
    "LTC",
    "MATIC",
    "NEAR",
    "OP",
    "PEPE",
    "SHIB",
    "SOL",
    "TRX",
    "UNI",
    "XBT",
    "XDG",
    "XLM",
    "XRP",
}

KNOWN_QUOTES: tuple[str, ...] = (
    "USDT",
    "USDC",
    "USD",
    "CAD",
    "EUR",
    "GBP",
    "JPY",
    "BTC",
    "ETH",
)

SYMBOL_CLEAN_RE = re.compile(r"[^A-Z0-9./_:-]")
SEPARATOR_RE = re.compile(r"[\s/_-]+")


class AssetNormalizationError(ValueError):
    """Raised when a symbol cannot be normalized safely."""


def normalize_asset_symbol(raw_symbol: str, default_crypto_quote: str = "USD") -> AssetIdentifier:
    """Normalize a user-provided symbol into an AssetIdentifier.

    Args:
        raw_symbol: User-provided symbol, such as BTC/USD, BTCUSD, AAPL, or NASDAQ:AAPL.
        default_crypto_quote: Quote currency used when a known crypto base is entered alone.

    Returns:
        AssetIdentifier with a canonical internal symbol.

    Raises:
        AssetNormalizationError: If the symbol is blank or malformed.
    """

    if raw_symbol is None:
        raise AssetNormalizationError("Symbol cannot be None.")

    original = str(raw_symbol).strip()
    if not original:
        raise AssetNormalizationError("Symbol cannot be blank.")

    prepared = _clean_symbol(original)
    venue_prefix, symbol_part = _split_venue_prefix(prepared)

    if not symbol_part:
        raise AssetNormalizationError(f"Symbol is missing after venue prefix: {original!r}")

    separated_pair = _parse_separated_crypto_pair(symbol_part)
    if separated_pair:
        base, quote = separated_pair
        return _build_crypto_identifier(original, base, quote, venue_prefix)

    compact_pair = _parse_compact_crypto_pair(symbol_part)
    if compact_pair:
        base, quote = compact_pair
        return _build_crypto_identifier(original, base, quote, venue_prefix)

    canonical_base = _canonical_crypto_base(symbol_part)
    if canonical_base in _canonical_crypto_bases():
        quote = default_crypto_quote.upper().strip()
        return _build_crypto_identifier(original, canonical_base, quote, venue_prefix)

    if _looks_like_traditional_ticker(symbol_part):
        return AssetIdentifier(
            original=original,
            normalized=symbol_part,
            asset_type=AssetType.TRADITIONAL,
            base=symbol_part,
            quote=None,
            venue_prefix=venue_prefix,
        )

    raise AssetNormalizationError(f"Could not safely normalize symbol: {original!r}")


def normalize_many(symbols: list[str] | tuple[str, ...]) -> list[AssetIdentifier]:
    """Normalize multiple symbols."""

    return [normalize_asset_symbol(symbol) for symbol in symbols]


def _clean_symbol(symbol: str) -> str:
    cleaned = symbol.strip().upper()
    cleaned = cleaned.removeprefix("$")
    cleaned = SYMBOL_CLEAN_RE.sub("", cleaned)
    return cleaned


def _split_venue_prefix(symbol: str) -> tuple[str | None, str]:
    if ":" not in symbol:
        return None, symbol

    prefix, rest = symbol.split(":", 1)
    prefix = prefix.strip() or None
    rest = rest.strip()

    return prefix, rest


def _parse_separated_crypto_pair(symbol: str) -> tuple[str, str] | None:
    parts = [part for part in SEPARATOR_RE.split(symbol) if part]

    if len(parts) != 2:
        return None

    base = _canonical_crypto_base(parts[0])
    quote = parts[1]

    if base in _canonical_crypto_bases() and quote in KNOWN_QUOTES:
        return base, quote

    return None


def _parse_compact_crypto_pair(symbol: str) -> tuple[str, str] | None:
    for quote in sorted(KNOWN_QUOTES, key=len, reverse=True):
        if not symbol.endswith(quote):
            continue

        possible_base = symbol[: -len(quote)]
        base = _canonical_crypto_base(possible_base)

        if base in _canonical_crypto_bases():
            return base, quote

    return None


def _canonical_crypto_base(base: str) -> str:
    cleaned = base.upper().strip()
    return CRYPTO_BASE_ALIASES.get(cleaned, cleaned)


def _canonical_crypto_bases() -> set[str]:
    return {_canonical_crypto_base(base) for base in KNOWN_CRYPTO_BASES}


def _looks_like_traditional_ticker(symbol: str) -> bool:
    if not 1 <= len(symbol) <= 12:
        return False

    return bool(re.fullmatch(r"[A-Z][A-Z0-9.-]*", symbol))


def _build_crypto_identifier(
    original: str,
    base: str,
    quote: str,
    venue_prefix: str | None,
) -> AssetIdentifier:
    canonical_base = _canonical_crypto_base(base)
    canonical_quote = quote.upper().strip()

    return AssetIdentifier(
        original=original,
        normalized=f"{canonical_base}/{canonical_quote}",
        asset_type=AssetType.CRYPTO,
        base=canonical_base,
        quote=canonical_quote,
        venue_prefix=venue_prefix,
    )
'@

Write-ProjectFile (Join-Path $AssetsPath "__init__.py") @'
# ============================ Assets Package ============================
"""Asset utilities for the TradingAgents crypto / multi-asset project."""

from tradingagents.assets.models import AssetIdentifier, AssetType
from tradingagents.assets.normalizer import AssetNormalizationError, normalize_asset_symbol, normalize_many

__all__ = [
    "AssetIdentifier",
    "AssetNormalizationError",
    "AssetType",
    "normalize_asset_symbol",
    "normalize_many",
]
'@

Write-ProjectFile (Join-Path $ScriptsPath "test_asset_normalizer.py") @'
# ============================ Test Asset Normalizer ============================
"""
Lightweight validation script for Slice 3.

Run:
    python scripts/test_asset_normalizer.py
"""

from __future__ import annotations

from tradingagents.assets import AssetNormalizationError, AssetType, normalize_asset_symbol


TEST_CASES = [
    ("BTC/USD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("btc-usd", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("BTCUSD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("XBT/USD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", None),
    ("ETHCAD", "ETH/CAD", AssetType.CRYPTO, "ETH", "CAD", None),
    ("KRAKEN:BTCUSD", "BTC/USD", AssetType.CRYPTO, "BTC", "USD", "KRAKEN"),
    ("SOL", "SOL/USD", AssetType.CRYPTO, "SOL", "USD", None),
    ("AAPL", "AAPL", AssetType.TRADITIONAL, "AAPL", None, None),
    ("SPY", "SPY", AssetType.TRADITIONAL, "SPY", None, None),
    ("NASDAQ:AAPL", "AAPL", AssetType.TRADITIONAL, "AAPL", None, "NASDAQ"),
]

INVALID_CASES = [
    "",
    "   ",
    "BTC//USD",
    "???",
]


def main() -> int:
    print("Running Slice 3 asset normalizer validation...")

    passed = 0
    failed = 0

    for raw, expected_normalized, expected_type, expected_base, expected_quote, expected_venue in TEST_CASES:
        try:
            result = normalize_asset_symbol(raw)
        except Exception as exc:
            failed += 1
            print(f"[FAIL] {raw!r}: unexpected exception: {exc}")
            continue

        checks = [
            result.normalized == expected_normalized,
            result.asset_type == expected_type,
            result.base == expected_base,
            result.quote == expected_quote,
            result.venue_prefix == expected_venue,
        ]

        if all(checks):
            passed += 1
            print(f"[OK]   {raw!r} -> {result.as_dict()}")
        else:
            failed += 1
            print(f"[FAIL] {raw!r} -> {result.as_dict()}")
            print(
                "       expected:",
                {
                    "normalized": expected_normalized,
                    "asset_type": expected_type.value,
                    "base": expected_base,
                    "quote": expected_quote,
                    "venue_prefix": expected_venue,
                },
            )

    for raw in INVALID_CASES:
        try:
            result = normalize_asset_symbol(raw)
        except AssetNormalizationError:
            passed += 1
            print(f"[OK]   invalid {raw!r} rejected")
        except Exception as exc:
            failed += 1
            print(f"[FAIL] invalid {raw!r}: wrong exception: {exc}")
        else:
            failed += 1
            print(f"[FAIL] invalid {raw!r}: unexpectedly normalized as {result.as_dict()}")

    print()
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")

    if failed:
        print("Asset normalizer validation failed.")
        return 1

    print("Asset normalizer validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@

# Append a Slice 3 decision log entry once.
$DecisionLogPath = Join-Path $DocsPath "11_DECISION_LOG.md"
$DecisionMarker = "## 2026-05-22 — Slice 3 Asset Normalization"
if ((Test-Path $DecisionLogPath) -and -not (Select-String -Path $DecisionLogPath -Pattern ([regex]::Escape($DecisionMarker)) -Quiet)) {
    Add-Content -Path $DecisionLogPath -Encoding UTF8 -Value @'

## 2026-05-22 — Slice 3 Asset Normalization

Decision:

The project will use a shared asset normalization layer before adding Kraken, TradingView, backtesting, or execution logic.

Initial normalized formats:

- Crypto pairs use `BASE/QUOTE`, such as `BTC/USD`.
- Traditional tickers use uppercase ticker symbols, such as `AAPL`.
- TradingView-style prefixes such as `NASDAQ:AAPL` and `KRAKEN:BTCUSD` are preserved as `venue_prefix` metadata.
- Kraken alias `XBT` is normalized to `BTC`.

Safety:

This slice adds no trading capability and no external API calls.
'@
}

Write-Host "=== SLICE 3 FILES CREATED ==="
Get-ChildItem $AssetsPath | Select-Object Name, Length, LastWriteTime
Get-ChildItem $ScriptsPath -Filter "test_asset_normalizer.py" | Select-Object Name, Length, LastWriteTime

Write-Host "`n=== RUNNING SLICE 3 VALIDATION ==="
python .\scripts\test_asset_normalizer.py

Write-Host "`n=== CURRENT BRANCH ==="
git branch --show-current

Write-Host "`n=== GIT STATUS ==="
git status --short

Write-Host "`nSlice 3 script completed."
