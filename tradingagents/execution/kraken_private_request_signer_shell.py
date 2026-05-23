"""
Slice 21A disabled Kraken private request signer shell.

This module defines the future private request signing boundary.

It does not:
- use API secrets
- read environment secrets
- generate a nonce
- compute HMAC signatures
- compute hashlib digests for signing
- sign private requests
- send network traffic
- call private execution endpoints
- place orders
- cancel orders
- enable live trading
- require private account-changing permissions

Every operation is blocked by default. This file is an interface shell only.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Mapping
from uuid import uuid4

from tradingagents.execution.live_execution_activation_policy import (
    LiveExecutionActivationEvidence,
    LiveExecutionActivationPolicyResult,
    evaluate_live_execution_activation_policy,
)


class KrakenPrivateRequestSignerShellError(ValueError):
    """Raised when the disabled private request signer shell blocks use."""


class KrakenPrivateRequestSignerShellStatus(str, Enum):
    """Signer shell result status."""

    BLOCKED = "blocked"
    DISABLED = "disabled"
    NOT_IMPLEMENTED = "not_implemented"


@dataclass(frozen=True)
class KrakenPrivateRequestSignerShellConfig:
    """Safe-to-log config for the disabled private request signer shell."""

    signer_name: str = "KrakenPrivateRequestSignerShell"
    enabled: bool = False
    dry_run_only: bool = True
    require_activation_policy: bool = True
    allow_secret_material: bool = False
    allow_nonce_generation: bool = False
    allow_signature_generation: bool = False
    allow_private_endpoint_calls: bool = False
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def safe_report(self) -> dict[str, Any]:
        return {
            "signer_name": self.signer_name,
            "enabled": False,
            "dry_run_only": True,
            "require_activation_policy": self.require_activation_policy,
            "allow_secret_material": False,
            "allow_nonce_generation": False,
            "allow_signature_generation": False,
            "allow_private_endpoint_calls": False,
            "secret_material_loaded": False,
            "nonce_generated": False,
            "signature_generated": False,
            "private_endpoint_calls_enabled": False,
            "secrets_included": False,
        }


@dataclass(frozen=True)
class KrakenPrivateSigningPreviewRequest:
    """
    Safe preview request for future private request signing.

    This is not signed. It must not contain secrets.
    """

    method_name: str
    path_name: str
    payload_preview: Mapping[str, Any] = field(default_factory=dict)
    metadata: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        if not str(self.method_name or "").strip():
            raise KrakenPrivateRequestSignerShellError("method_name is required.")

        if not str(self.path_name or "").strip():
            raise KrakenPrivateRequestSignerShellError("path_name is required.")

        _assert_no_secret_like_terms(
            {
                "method_name": self.method_name,
                "path_name": self.path_name,
                "payload_preview": dict(self.payload_preview or {}),
                "metadata": dict(self.metadata or {}),
            }
        )

    def safe_report(self) -> dict[str, Any]:
        self.validate()

        return {
            "method_name": str(self.method_name).strip(),
            "path_name": str(self.path_name).strip(),
            "payload_preview": dict(self.payload_preview or {}),
            "metadata": dict(self.metadata or {}),
            "signed": False,
            "nonce_generated": False,
            "signature_generated": False,
            "secret_material_loaded": False,
            "sent": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "secrets_included": False,
        }


@dataclass(frozen=True)
class KrakenPrivateRequestSignerShellResult:
    """Safe-to-log blocked private signer shell result."""

    result_id: str
    signer_name: str
    operation: str
    status: KrakenPrivateRequestSignerShellStatus
    blocked: bool
    message: str
    reasons: tuple[str, ...]
    request_preview: Mapping[str, Any] | None = None
    activation_policy_report: Mapping[str, Any] | None = None
    secrets_included: bool = False
    secret_material_loaded: bool = False
    nonce_generated: bool = False
    signature_generated: bool = False
    network_call_made: bool = False
    private_endpoint_called: bool = False
    execution_allowed: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "result_id": self.result_id,
            "signer_name": self.signer_name,
            "operation": self.operation,
            "status": self.status.value,
            "blocked": self.blocked,
            "message": self.message,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "request_preview": dict(self.request_preview or {}),
            "activation_policy_report": dict(self.activation_policy_report or {}),
            "secrets_included": False,
            "secret_material_loaded": False,
            "nonce_generated": False,
            "signature_generated": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "execution_allowed": False,
        }


class KrakenPrivateRequestSignerShell:
    """
    Disabled shell for future Kraken private request signing.

    This class intentionally contains no API key, no API secret, no nonce
    generator, no HMAC implementation, no digest implementation, no network
    client, and no endpoint implementation. All operations return blocked
    results.
    """

    def __init__(
        self,
        *,
        config: KrakenPrivateRequestSignerShellConfig | None = None,
        activation_evidence: LiveExecutionActivationEvidence | None = None,
    ) -> None:
        self.config = config or KrakenPrivateRequestSignerShellConfig()
        self.activation_evidence = activation_evidence

        self.secret_material_loaded = False
        self.nonce_generated = False
        self.signature_generated = False
        self.network_call_made = False
        self.private_endpoint_called = False

        if self.config.allow_secret_material:
            raise KrakenPrivateRequestSignerShellError(
                "Secret material is not allowed in Slice 21A."
            )

        if self.config.allow_nonce_generation:
            raise KrakenPrivateRequestSignerShellError(
                "Nonce generation is not allowed in Slice 21A."
            )

        if self.config.allow_signature_generation:
            raise KrakenPrivateRequestSignerShellError(
                "Signature generation is not allowed in Slice 21A."
            )

        if self.config.allow_private_endpoint_calls:
            raise KrakenPrivateRequestSignerShellError(
                "Private endpoint calls are not allowed in Slice 21A."
            )

    def activation_policy_result(self) -> LiveExecutionActivationPolicyResult:
        return evaluate_live_execution_activation_policy(self.activation_evidence)

    def capabilities(self) -> dict[str, Any]:
        return {
            "signer_name": self.config.signer_name,
            "enabled": False,
            "dry_run_only": True,
            "can_load_secret_material": False,
            "can_generate_nonce": False,
            "can_generate_signature": False,
            "can_sign_private_requests": False,
            "can_send_network_requests": False,
            "can_call_private_endpoints": False,
            "requires_activation_policy": True,
            "secret_material_loaded": False,
            "nonce_generated": False,
            "signature_generated": False,
            "network_calls_enabled": False,
            "private_endpoint_calls_enabled": False,
            "secrets_included": False,
        }

    def preview_sign_private_request(
        self,
        request: KrakenPrivateSigningPreviewRequest,
    ) -> KrakenPrivateRequestSignerShellResult:
        """
        Accept a future private signing preview request and block it.

        No nonce is generated. No signature is generated. No secret is loaded.
        """

        if not isinstance(request, KrakenPrivateSigningPreviewRequest):
            raise KrakenPrivateRequestSignerShellError(
                "request must be a KrakenPrivateSigningPreviewRequest."
            )

        request_report = request.safe_report()

        return self._blocked_result(
            operation="preview_sign_private_request",
            request_preview=request_report,
        )

    def safe_report(self) -> dict[str, Any]:
        policy_report = self.activation_policy_result().safe_report()

        return {
            "signer_name": self.config.signer_name,
            "slice": "21A",
            "enabled": False,
            "dry_run_only": True,
            "secret_material_loaded": False,
            "nonce_generated": False,
            "signature_generated": False,
            "network_call_made": False,
            "private_endpoint_called": False,
            "secrets_included": False,
            "execution_allowed": False,
            "config": self.config.safe_report(),
            "capabilities": self.capabilities(),
            "activation_policy": policy_report,
        }

    def _blocked_result(
        self,
        *,
        operation: str,
        request_preview: Mapping[str, Any] | None = None,
    ) -> KrakenPrivateRequestSignerShellResult:
        policy_result = self.activation_policy_result()

        reasons = tuple(str(reason) for reason in policy_result.reasons)
        reasons += (
            "Kraken private request signer shell is disabled in Slice 21A.",
            "No API secret is loaded.",
            "No nonce generation is implemented.",
            "No signature generation is implemented.",
            "No private endpoint call is implemented.",
        )

        return KrakenPrivateRequestSignerShellResult(
            result_id=f"kraken_private_signer_{uuid4().hex}",
            signer_name=self.config.signer_name,
            operation=operation,
            status=KrakenPrivateRequestSignerShellStatus.BLOCKED,
            blocked=True,
            message="Operation blocked by disabled Kraken private request signer shell.",
            reasons=reasons,
            request_preview=request_preview,
            activation_policy_report=policy_result.safe_report(),
            secrets_included=False,
            secret_material_loaded=False,
            nonce_generated=False,
            signature_generated=False,
            network_call_made=False,
            private_endpoint_called=False,
            execution_allowed=False,
        )


def assert_kraken_private_request_signer_shell_report_is_safe(
    report: Mapping[str, Any],
) -> None:
    """Validate that the private signer shell report is safe to log."""

    if report.get("secrets_included") is not False:
        raise KrakenPrivateRequestSignerShellError("Private signer report includes secrets.")

    if report.get("secret_material_loaded") is not False:
        raise KrakenPrivateRequestSignerShellError(
            "Private signer report indicates secret material was loaded."
        )

    if report.get("nonce_generated") is not False:
        raise KrakenPrivateRequestSignerShellError(
            "Private signer report indicates nonce generation."
        )

    if report.get("signature_generated") is not False:
        raise KrakenPrivateRequestSignerShellError(
            "Private signer report indicates signature generation."
        )

    if report.get("network_call_made") is not False:
        raise KrakenPrivateRequestSignerShellError(
            "Private signer report indicates a network call."
        )

    if report.get("private_endpoint_called") is not False:
        raise KrakenPrivateRequestSignerShellError(
            "Private signer report indicates a private endpoint call."
        )

    if report.get("execution_allowed") is not False:
        raise KrakenPrivateRequestSignerShellError(
            "Private signer report must not allow execution."
        )



def _assert_no_secret_like_terms(value: Any) -> None:
    text = str(value).lower()

    forbidden_secret_terms = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "token=",
        "bearer ",
        "signed_request",
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise KrakenPrivateRequestSignerShellError(
                f"Unsafe secret/signing-like term detected: {term}"
            )


