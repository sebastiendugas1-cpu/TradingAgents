"""Disabled signing-material review integration for the Kraken signer shell.

This module attaches the disabled signing-material review payload to the signer
shell review surface. It is intentionally data-only and blocked.
"""

from __future__ import annotations

from dataclasses import asdict, is_dataclass
import inspect
from typing import Any, Mapping

from tradingagents.execution.kraken_private_signing_material_model import (
    build_disabled_kraken_private_signing_material,
)


_SIGNER_SHELL_BUILDER_NAMES = (
    "build_disabled_kraken_private_request_signer_shell",
    "build_disabled_kraken_private_request_signer",
    "build_disabled_private_request_signer_shell",
    "build_disabled_private_request_signer",
)


def _to_review_payload(value: Any) -> Mapping[str, object]:
    if isinstance(value, Mapping):
        return dict(value)

    if hasattr(value, "as_review_payload"):
        payload = value.as_review_payload()
        if isinstance(payload, Mapping):
            return dict(payload)

    if is_dataclass(value):
        return asdict(value)

    return {
        "status": "disabled",
        "review_object_type": type(value).__name__,
        "review_object_repr": repr(value),
    }


def _build_signer_shell_review_snapshot() -> Mapping[str, object]:
    from tradingagents.execution import kraken_private_request_signer_shell as signer_shell

    for builder_name in _SIGNER_SHELL_BUILDER_NAMES:
        builder = getattr(signer_shell, builder_name, None)
        if builder is None or not callable(builder):
            continue

        signature = inspect.signature(builder)
        required_parameters = [
            parameter
            for parameter in signature.parameters.values()
            if parameter.default is inspect.Parameter.empty
            and parameter.kind
            in (
                inspect.Parameter.POSITIONAL_ONLY,
                inspect.Parameter.POSITIONAL_OR_KEYWORD,
                inspect.Parameter.KEYWORD_ONLY,
            )
        ]

        if required_parameters:
            continue

        return _to_review_payload(builder())

    return {
        "status": "disabled",
        "review_object_type": "kraken_private_request_signer_shell",
        "review_object_repr": "No zero-argument signer shell builder was available.",
    }


def build_disabled_signer_shell_review_with_signing_material(
    signer_review: Mapping[str, object] | None = None,
) -> Mapping[str, object]:
    """Return a disabled review payload with signing material attached."""

    base_review = dict(signer_review or _build_signer_shell_review_snapshot())
    signing_material = build_disabled_kraken_private_signing_material().as_review_payload()

    return {
        "status": "disabled",
        "signer_shell_review": base_review,
        "signing_material_review": dict(signing_material),
        "can_read_api_secret": False,
        "can_read_environment_secret": False,
        "can_generate_nonce": False,
        "can_generate_signature": False,
        "can_call_private_endpoint": False,
        "required_permissions": [],
    }
