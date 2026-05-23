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
