"""Disabled Kraken private signing material model.

This module intentionally defines data-only structures for future private request
signing workflows. It does not read secrets, generate nonces, build signatures,
or call private/network endpoints.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Tuple


_DISABLED_REASON = (
    "Private request signing material is data-only and disabled. "
    "No API secret reading, nonce generation, or signature generation is available."
)


@dataclass(frozen=True)
class DisabledKrakenPrivateSigningMaterial:
    """Data-only description of disabled future signing material.

    The fields deliberately describe availability and required capabilities
    without storing API keys, API secrets, nonces, or generated signatures.
    """

    exchange: str = "kraken"
    status: str = "disabled"
    can_read_api_secret: bool = False
    can_read_environment_secret: bool = False
    can_generate_nonce: bool = False
    can_generate_signature: bool = False
    can_call_private_endpoint: bool = False
    required_permissions: Tuple[str, ...] = ()

    @property
    def disabled_reason(self) -> str:
        return _DISABLED_REASON

    def as_review_payload(self) -> Mapping[str, object]:
        """Return an inert review payload with no sensitive material."""

        return {
            "exchange": self.exchange,
            "status": self.status,
            "can_read_api_secret": self.can_read_api_secret,
            "can_read_environment_secret": self.can_read_environment_secret,
            "can_generate_nonce": self.can_generate_nonce,
            "can_generate_signature": self.can_generate_signature,
            "can_call_private_endpoint": self.can_call_private_endpoint,
            "required_permissions": list(self.required_permissions),
            "disabled_reason": self.disabled_reason,
        }


def build_disabled_kraken_private_signing_material() -> DisabledKrakenPrivateSigningMaterial:
    """Build the disabled, data-only signing material model."""

    return DisabledKrakenPrivateSigningMaterial()
