$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 21A DISABLED KRAKEN PRIVATE REQUEST SIGNER SHELL ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$signerPath = ".\tradingagents\execution\kraken_private_request_signer_shell.py"
$testPath = ".\scripts\test_kraken_private_request_signer_shell.py"

$signerContent = @'
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

    _assert_no_secret_like_terms(report)


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
        "signature",
        "signed_request",
        "secret_material",
        "nonce",
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise KrakenPrivateRequestSignerShellError(
                f"Unsafe secret/signing-like term detected: {term}"
            )
'@

$testContent = @'
"""
Validation script for Slice 21A.

This validates the disabled Kraken private request signer shell.

It does not:
- use API secrets
- read environment secrets
- generate a nonce
- compute HMAC signatures
- compute hashlib digests for signing
- sign private requests
- send network traffic
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.kraken_private_request_signer_shell import (
    KrakenPrivateRequestSignerShell,
    KrakenPrivateRequestSignerShellConfig,
    KrakenPrivateRequestSignerShellError,
    KrakenPrivateRequestSignerShellStatus,
    KrakenPrivateSigningPreviewRequest,
    assert_kraken_private_request_signer_shell_report_is_safe,
)
from tradingagents.execution.live_execution_activation_policy import (
    build_theoretical_ready_evidence_for_tests,
)


def make_request() -> KrakenPrivateSigningPreviewRequest:
    return KrakenPrivateSigningPreviewRequest(
        method_name="private_order_preview",
        path_name="private_order_preview_path",
        payload_preview={
            "pair": "XBT/CAD",
            "type": "buy",
            "ordertype": "limit",
            "volume": "0.000085168",
            "price": "100000",
            "validate": True,
        },
        metadata={"source": "slice_21a_test"},
    )


def test_signer_capabilities_are_disabled() -> None:
    signer = KrakenPrivateRequestSignerShell()
    report = signer.safe_report()
    capabilities = report["capabilities"]

    assert report["enabled"] is False
    assert report["dry_run_only"] is True
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False

    assert capabilities["can_load_secret_material"] is False
    assert capabilities["can_generate_nonce"] is False
    assert capabilities["can_generate_signature"] is False
    assert capabilities["can_sign_private_requests"] is False
    assert capabilities["can_send_network_requests"] is False
    assert capabilities["can_call_private_endpoints"] is False

    assert signer.secret_material_loaded is False
    assert signer.nonce_generated is False
    assert signer.signature_generated is False
    assert signer.network_call_made is False
    assert signer.private_endpoint_called is False

    assert_kraken_private_request_signer_shell_report_is_safe(report)

    print("[OK] private request signer shell capabilities are disabled")


def test_preview_sign_private_request_blocks() -> None:
    signer = KrakenPrivateRequestSignerShell()
    result = signer.preview_sign_private_request(make_request())
    report = result.safe_report()

    assert result.status == KrakenPrivateRequestSignerShellStatus.BLOCKED
    assert report["blocked"] is True
    assert report["operation"] == "preview_sign_private_request"
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False

    request_preview = report["request_preview"]
    assert request_preview["signed"] is False
    assert request_preview["nonce_generated"] is False
    assert request_preview["signature_generated"] is False
    assert request_preview["secret_material_loaded"] is False
    assert request_preview["sent"] is False

    assert signer.secret_material_loaded is False
    assert signer.nonce_generated is False
    assert signer.signature_generated is False
    assert signer.network_call_made is False
    assert signer.private_endpoint_called is False

    assert any("disabled in Slice 21A" in reason for reason in result.reasons)

    assert_kraken_private_request_signer_shell_report_is_safe(report)

    print("[OK] preview sign private request blocks")


def test_theoretical_ready_policy_still_blocks() -> None:
    signer = KrakenPrivateRequestSignerShell(
        activation_evidence=build_theoretical_ready_evidence_for_tests()
    )

    result = signer.preview_sign_private_request(make_request())
    report = result.safe_report()

    assert report["blocked"] is True
    assert report["secret_material_loaded"] is False
    assert report["nonce_generated"] is False
    assert report["signature_generated"] is False
    assert report["network_call_made"] is False
    assert report["private_endpoint_called"] is False
    assert report["secrets_included"] is False
    assert report["execution_allowed"] is False
    assert any("disabled in Slice 21A" in reason for reason in result.reasons)

    print("[OK] theoretical ready policy still blocks signer shell")


def expect_error(label: str, func) -> None:
    try:
        func()
    except KrakenPrivateRequestSignerShellError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected KrakenPrivateRequestSignerShellError")


def test_invalid_inputs_are_rejected() -> None:
    expect_error(
        "secret-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_secret_material=True,
            )
        ),
    )

    expect_error(
        "nonce-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_nonce_generation=True,
            )
        ),
    )

    expect_error(
        "signature-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_signature_generation=True,
            )
        ),
    )

    expect_error(
        "private-endpoint-capable config rejected",
        lambda: KrakenPrivateRequestSignerShell(
            config=KrakenPrivateRequestSignerShellConfig(
                allow_private_endpoint_calls=True,
            )
        ),
    )

    expect_error(
        "missing method name rejected",
        lambda: KrakenPrivateRequestSignerShell().preview_sign_private_request(
            KrakenPrivateSigningPreviewRequest(
                method_name="",
                path_name="private_order_preview_path",
            )
        ),
    )

    expect_error(
        "secret-like payload rejected",
        lambda: KrakenPrivateRequestSignerShell().preview_sign_private_request(
            KrakenPrivateSigningPreviewRequest(
                method_name="private_order_preview",
                path_name="private_order_preview_path",
                payload_preview={"api_secret": "not-allowed"},
            )
        ),
    )

    expect_error(
        "wrong request type rejected",
        lambda: KrakenPrivateRequestSignerShell().preview_sign_private_request(
            object(),  # type: ignore[arg-type]
        ),
    )


def test_source_contains_no_signing_network_or_private_execution_endpoint_names() -> None:
    source = Path(
        "tradingagents/execution/kraken_private_request_signer_shell.py"
    ).read_text(encoding="utf-8").lower()

    forbidden_terms = (
        "import hmac",
        "import hashlib",
        "import base64",
        "import os",
        "hmac.",
        "hashlib.",
        "base64.",
        "os.environ",
        "time.time(",
        "requests.get(",
        "requests.post(",
        "requests.session(",
        "httpx.get(",
        "httpx.post(",
        "httpx.client(",
        "urllib.request",
        "addorder",
        "cancelorder",
        "withdraw",
        "withdrawal",
        "deposit",
        "funding",
        "tradebalance",
        "ledgers",
    )

    for term in forbidden_terms:
        assert term not in source

    print("[OK] private request signer shell source contains no signing/network/private endpoint calls")


def main() -> None:
    print("Slice 21A validation: Disabled Kraken Private Request Signer Shell")
    print("=" * 80)

    test_signer_capabilities_are_disabled()
    test_preview_sign_private_request_blocks()
    test_theoretical_ready_policy_still_blocks()
    test_invalid_inputs_are_rejected()
    test_source_contains_no_signing_network_or_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 21A disabled Kraken private request signer shell validation passed.")
    print("[PASS] Private signer shell remains disabled and blocked.")
    print("[PASS] No secret material usage was introduced.")
    print("[PASS] No nonce or signature generation was introduced.")
    print("[PASS] No network call was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $signerPath -Value $signerContent -Encoding UTF8
Write-Host "[WRITTEN] $signerPath"

Set-Content -Path $testPath -Value $testContent -Encoding UTF8
Write-Host "[WRITTEN] $testPath"

function Add-DocBlockOnce {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if (-not (Test-Path $Path)) {
        throw "Missing doc file: $Path"
    }

    $existing = Get-Content $Path -Raw

    if ($existing -notlike "*$Marker*") {
        Add-Content -Path $Path -Value "`n$Block" -Encoding UTF8
        Write-Host "[UPDATED] $Path"
    } else {
        Write-Host "[SKIPPED] $Path already contains $Marker"
    }
}

$roadmapBlock = @"
## Slice 21A — Disabled Kraken Private Request Signer Shell

Status: Implemented pending validation.

Goal:
Create a disabled private request signer shell for future Kraken private request signing.

Scope:
- Create `tradingagents/execution/kraken_private_request_signer_shell.py`.
- Create `scripts/test_kraken_private_request_signer_shell.py`.
- Define safe config, signing preview request, and result models.
- Define a blocked signing preview method.
- Require activation policy evaluation.
- Validate that no secret, nonce, signature, network, or private endpoint behavior exists.

Safety:
- No API secret usage.
- No environment secret reading.
- No nonce generation.
- No signature generation.
- No HMAC or digest signing implementation.
- No network call.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 21A — Disabled Kraken Private Request Signer Shell

A disabled Kraken private request signer shell has been added.

The shell:
- has no API secret
- reads no environment secrets
- has no nonce generator
- has no HMAC or digest signing implementation
- blocks signing previews
- requires activation policy evaluation
- reports no secret, nonce, signature, network, or private endpoint behavior
"@

$decisionBlock = @"
## Slice 21A Decision — Add Disabled Private Request Signer Shell Before Any Signing Code

Decision:
Add a disabled Kraken private request signer shell before any future request signing implementation.

Reason:
The system needs a safe signer boundary before any code that could use secrets, generate nonces, or create signatures can be considered.

Result:
The project now has a tested disabled private signer shell with blocked preview methods and no signing behavior.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 21A — Disabled Kraken Private Request Signer Shell" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 21A — Disabled Kraken Private Request Signer Shell" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 21A Decision — Add Disabled Private Request Signer Shell Before Any Signing Code" -Block $decisionBlock

python -m py_compile $signerPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 21A FILES ==="
Get-Item `
    ".\tradingagents\execution\kraken_private_request_signer_shell.py", `
    ".\scripts\test_kraken_private_request_signer_shell.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 21A script completed."
