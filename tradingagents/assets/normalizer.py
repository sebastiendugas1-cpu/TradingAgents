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
    if "//" in original or "--" in original or "__" in original:
        raise AssetNormalizationError(f"Invalid asset symbol with repeated separators: {raw_symbol!r}")
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


