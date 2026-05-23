# ============================ Kraken Read-Only Environment Validation ============================
"""
Safe Kraken read-only environment validator.

This module only validates local configuration.
It does not call Kraken.
It does not read balances.
It does not read orders.
It does not place, cancel, fund, or withdraw anything.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Mapping


KRAKEN_API_KEY_ENV = "KRAKEN_API_KEY"
KRAKEN_API_SECRET_ENV = "KRAKEN_API_SECRET"

# Explicit safety flags. These are expected to be false or absent.
KRAKEN_TRADING_ENABLED_ENV = "KRAKEN_TRADING_ENABLED"
KRAKEN_WITHDRAWALS_ENABLED_ENV = "KRAKEN_WITHDRAWALS_ENABLED"
KRAKEN_FUNDING_ENABLED_ENV = "KRAKEN_FUNDING_ENABLED"

DANGEROUS_PERMISSION_WORDS = {
    "trade",
    "trading",
    "order",
    "orders",
    "cancel",
    "withdraw",
    "withdrawal",
    "funding",
    "deposit",
    "transfer",
    "margin",
    "leverage",
    "futures",
}


class KrakenReadOnlyEnvironmentError(ValueError):
    """Raised when Kraken read-only environment configuration is unsafe."""


@dataclass(frozen=True)
class KrakenReadOnlyEnvironmentReport:
    """Safe report that never exposes API key or secret values."""

    env_file: str | None
    has_api_key: bool
    has_api_secret: bool
    trading_enabled: bool
    withdrawals_enabled: bool
    funding_enabled: bool
    dangerous_permission_words_found: tuple[str, ...]
    is_ready_for_readonly_private_client: bool
    notes: tuple[str, ...]

    def to_dict(self) -> dict[str, object]:
        """Return a JSON-serializable report with no secrets."""
        return asdict(self)


def validate_kraken_readonly_environment(
    *,
    env_file: str | Path | None = None,
    environ: Mapping[str, str] | None = None,
    require_keys: bool = False,
) -> KrakenReadOnlyEnvironmentReport:
    """Validate local Kraken read-only environment settings.

    Args:
        env_file:
            Optional .env path to read. Values from environ override values from env_file.
        environ:
            Optional mapping to validate, useful for tests.
        require_keys:
            If true, raise when KRAKEN_API_KEY or KRAKEN_API_SECRET is missing.

    Returns:
        KrakenReadOnlyEnvironmentReport with presence booleans only.

    Safety:
        This function never returns the API key or secret values.
    """

    file_values = _load_env_file(Path(env_file)) if env_file else {}
    merged_values = dict(file_values)

    if environ is not None:
        merged_values.update({key: value for key, value in environ.items() if value is not None})

    api_key = _clean_value(merged_values.get(KRAKEN_API_KEY_ENV))
    api_secret = _clean_value(merged_values.get(KRAKEN_API_SECRET_ENV))

    trading_enabled = _parse_bool(merged_values.get(KRAKEN_TRADING_ENABLED_ENV))
    withdrawals_enabled = _parse_bool(merged_values.get(KRAKEN_WITHDRAWALS_ENABLED_ENV))
    funding_enabled = _parse_bool(merged_values.get(KRAKEN_FUNDING_ENABLED_ENV))

    dangerous_words = _find_dangerous_permission_words(merged_values)

    notes: list[str] = []

    if not api_key:
        notes.append("KRAKEN_API_KEY is missing.")

    if not api_secret:
        notes.append("KRAKEN_API_SECRET is missing.")

    if trading_enabled:
        notes.append("KRAKEN_TRADING_ENABLED is true. Read-only mode requires false.")

    if withdrawals_enabled:
        notes.append("KRAKEN_WITHDRAWALS_ENABLED is true. This is forbidden.")

    if funding_enabled:
        notes.append("KRAKEN_FUNDING_ENABLED is true. This is forbidden.")

    if dangerous_words:
        notes.append(
            "Dangerous permission words were found in local Kraken configuration. "
            "Only read-only permissions should be used."
        )

    has_keys = bool(api_key and api_secret)
    unsafe_flags = trading_enabled or withdrawals_enabled or funding_enabled or bool(dangerous_words)
    ready = has_keys and not unsafe_flags

    report = KrakenReadOnlyEnvironmentReport(
        env_file=str(env_file) if env_file else None,
        has_api_key=bool(api_key),
        has_api_secret=bool(api_secret),
        trading_enabled=trading_enabled,
        withdrawals_enabled=withdrawals_enabled,
        funding_enabled=funding_enabled,
        dangerous_permission_words_found=tuple(sorted(dangerous_words)),
        is_ready_for_readonly_private_client=ready,
        notes=tuple(notes),
    )

    if require_keys and not has_keys:
        raise KrakenReadOnlyEnvironmentError(
            "Kraken read-only credentials are required but KRAKEN_API_KEY or KRAKEN_API_SECRET is missing."
        )

    if unsafe_flags:
        raise KrakenReadOnlyEnvironmentError(
            "Unsafe Kraken environment settings detected. Read-only validation failed."
        )

    return report


def _load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}

    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        values[key.strip()] = _clean_value(value)

    return values


def _clean_value(value: object) -> str:
    if value is None:
        return ""

    cleaned = str(value).strip()
    cleaned = cleaned.strip('"').strip("'")
    return cleaned


def _parse_bool(value: object) -> bool:
    cleaned = _clean_value(value).lower()

    if cleaned in {"1", "true", "yes", "y", "on", "enabled"}:
        return True

    return False


def _find_dangerous_permission_words(values: Mapping[str, str]) -> set[str]:
    found: set[str] = set()

    # Scan only permission-oriented fields, not the raw API key/secret.
    permission_fields = {
        key: value
        for key, value in values.items()
        if "permission" in key.lower()
        or "scope" in key.lower()
        or "mode" in key.lower()
        or "enabled" in key.lower()
    }

    combined = " ".join(str(value).lower() for value in permission_fields.values())

    for word in DANGEROUS_PERMISSION_WORDS:
        if word in combined:
            found.add(word)

    return found
