$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 17D LIVE EXECUTION ACTIVATION POLICY ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\tradingagents\execution" | Out-Null
New-Item -ItemType Directory -Force ".\docs" | Out-Null
New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$policyPath = ".\tradingagents\execution\live_execution_activation_policy.py"
$docPath = ".\docs\16_LIVE_EXECUTION_ACTIVATION_POLICY.md"
$testPath = ".\scripts\test_live_execution_activation_policy.py"

$policyContent = @'
"""
Slice 17D live execution activation policy.

This module defines the plain-policy gate for any future live execution.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

This policy is stricter than a config check. It documents and validates the
required evidence before any future live-capable adapter can be considered.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from enum import Enum
from typing import Any, Mapping


class ActivationPolicyError(ValueError):
    """Raised when activation policy input is unsafe or invalid."""


class ActivationPolicyStatus(str, Enum):
    """Activation policy result status."""

    BLOCKED = "blocked"
    REVIEW_REQUIRED = "review_required"
    THEORETICALLY_READY = "theoretically_ready"


@dataclass(frozen=True)
class LiveExecutionActivationEvidence:
    """
    Evidence required before future live execution can even be considered.

    In Slice 17D this evidence is evaluated only. It does not activate anything.
    """

    kill_switch_off: bool = False
    live_trading_enabled: bool = False
    explicit_confirmation_valid: bool = False
    max_live_trade_value: str = "0"
    max_live_trade_value_currency: str = "CAD"
    readiness_report_passed: bool = False
    risk_gate_passed: bool = False
    manual_approval_recorded: bool = False
    audit_log_ready: bool = False
    adapter_capabilities_reviewed: bool = False
    adapter_reports_no_private_endpoint_call: bool = False
    operator_identity_recorded: bool = False
    emergency_shutdown_procedure_confirmed: bool = False
    regression_suite_passed: bool = False
    dry_run_preview_recorded: bool = False
    order_value_within_limit: bool = False
    notes: Mapping[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        parse_non_negative_decimal(
            self.max_live_trade_value,
            "max_live_trade_value",
        )

        currency = str(self.max_live_trade_value_currency or "").strip().upper()
        if currency != "CAD":
            raise ActivationPolicyError("max_live_trade_value_currency must be CAD.")

    def safe_report(self) -> dict[str, Any]:
        self.validate()

        return {
            "kill_switch_off": self.kill_switch_off,
            "live_trading_enabled": self.live_trading_enabled,
            "explicit_confirmation_valid": self.explicit_confirmation_valid,
            "max_live_trade_value": str(self.max_live_trade_value),
            "max_live_trade_value_currency": self.max_live_trade_value_currency,
            "readiness_report_passed": self.readiness_report_passed,
            "risk_gate_passed": self.risk_gate_passed,
            "manual_approval_recorded": self.manual_approval_recorded,
            "audit_log_ready": self.audit_log_ready,
            "adapter_capabilities_reviewed": self.adapter_capabilities_reviewed,
            "adapter_reports_no_private_endpoint_call": self.adapter_reports_no_private_endpoint_call,
            "operator_identity_recorded": self.operator_identity_recorded,
            "emergency_shutdown_procedure_confirmed": self.emergency_shutdown_procedure_confirmed,
            "regression_suite_passed": self.regression_suite_passed,
            "dry_run_preview_recorded": self.dry_run_preview_recorded,
            "order_value_within_limit": self.order_value_within_limit,
            "secrets_included": False,
            "private_endpoint_called": False,
        }


@dataclass(frozen=True)
class LiveExecutionActivationPolicyResult:
    """Safe-to-log activation policy result."""

    status: ActivationPolicyStatus
    blocked: bool
    theoretically_ready: bool
    reasons: tuple[str, ...]
    evidence_report: Mapping[str, Any]
    required_manual_statement: str
    emergency_shutdown_required: bool = True
    secrets_included: bool = False
    private_endpoint_called: bool = False

    def safe_report(self) -> dict[str, Any]:
        return {
            "status": self.status.value,
            "blocked": self.blocked,
            "theoretically_ready": self.theoretically_ready,
            "reason_count": len(self.reasons),
            "reasons": list(self.reasons),
            "evidence_report": dict(self.evidence_report),
            "required_manual_statement": self.required_manual_statement,
            "emergency_shutdown_required": self.emergency_shutdown_required,
            "secrets_included": False,
            "private_endpoint_called": False,
            "execution_enabled_by_policy": False,
        }


REQUIRED_MANUAL_STATEMENT = (
    "I understand this is live trading with real financial risk and I approve "
    "this specific reviewed command only."
)


def evaluate_live_execution_activation_policy(
    evidence: LiveExecutionActivationEvidence | None = None,
) -> LiveExecutionActivationPolicyResult:
    """
    Evaluate whether future live execution is theoretically ready.

    This function never enables execution. Even a theoretically ready result is
    still only a policy result.
    """

    current = evidence or LiveExecutionActivationEvidence()
    evidence_report = current.safe_report()

    reasons: list[str] = []

    if not current.kill_switch_off:
        reasons.append("Kill switch is not off.")
    if not current.live_trading_enabled:
        reasons.append("Live trading config is not enabled.")
    if not current.explicit_confirmation_valid:
        reasons.append("Explicit manual confirmation is missing or invalid.")

    max_value = parse_non_negative_decimal(
        current.max_live_trade_value,
        "max_live_trade_value",
    )
    if max_value <= Decimal("0"):
        reasons.append("Maximum live trade value must be greater than zero.")

    checks = (
        ("readiness_report_passed", current.readiness_report_passed),
        ("risk_gate_passed", current.risk_gate_passed),
        ("manual_approval_recorded", current.manual_approval_recorded),
        ("audit_log_ready", current.audit_log_ready),
        ("adapter_capabilities_reviewed", current.adapter_capabilities_reviewed),
        (
            "adapter_reports_no_private_endpoint_call",
            current.adapter_reports_no_private_endpoint_call,
        ),
        ("operator_identity_recorded", current.operator_identity_recorded),
        (
            "emergency_shutdown_procedure_confirmed",
            current.emergency_shutdown_procedure_confirmed,
        ),
        ("regression_suite_passed", current.regression_suite_passed),
        ("dry_run_preview_recorded", current.dry_run_preview_recorded),
        ("order_value_within_limit", current.order_value_within_limit),
    )

    for name, passed in checks:
        if not passed:
            reasons.append(f"Required activation evidence missing: {name}.")

    if reasons:
        return LiveExecutionActivationPolicyResult(
            status=ActivationPolicyStatus.BLOCKED,
            blocked=True,
            theoretically_ready=False,
            reasons=tuple(reasons),
            evidence_report=evidence_report,
            required_manual_statement=REQUIRED_MANUAL_STATEMENT,
            emergency_shutdown_required=True,
            secrets_included=False,
            private_endpoint_called=False,
        )

    return LiveExecutionActivationPolicyResult(
        status=ActivationPolicyStatus.THEORETICALLY_READY,
        blocked=True,
        theoretically_ready=True,
        reasons=(
            "All activation evidence is present, but Slice 17D still does not enable execution.",
        ),
        evidence_report=evidence_report,
        required_manual_statement=REQUIRED_MANUAL_STATEMENT,
        emergency_shutdown_required=True,
        secrets_included=False,
        private_endpoint_called=False,
    )


def build_theoretical_ready_evidence_for_tests() -> LiveExecutionActivationEvidence:
    """
    Build a complete evidence object for tests.

    This is not loaded from environment and does not enable anything.
    """

    return LiveExecutionActivationEvidence(
        kill_switch_off=True,
        live_trading_enabled=True,
        explicit_confirmation_valid=True,
        max_live_trade_value="10",
        max_live_trade_value_currency="CAD",
        readiness_report_passed=True,
        risk_gate_passed=True,
        manual_approval_recorded=True,
        audit_log_ready=True,
        adapter_capabilities_reviewed=True,
        adapter_reports_no_private_endpoint_call=True,
        operator_identity_recorded=True,
        emergency_shutdown_procedure_confirmed=True,
        regression_suite_passed=True,
        dry_run_preview_recorded=True,
        order_value_within_limit=True,
        notes={"source": "slice_17d_test"},
    )


def parse_non_negative_decimal(value: str | Decimal, field_name: str) -> Decimal:
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ActivationPolicyError(f"{field_name} must be a valid decimal number.") from exc

    if parsed < Decimal("0"):
        raise ActivationPolicyError(f"{field_name} cannot be negative.")

    return parsed


def assert_activation_policy_report_is_safe(report: Mapping[str, Any]) -> None:
    """Validate that an activation policy report is safe to log."""

    if report.get("secrets_included") is not False:
        raise ActivationPolicyError("Activation policy report must not include secrets.")

    if report.get("private_endpoint_called") is not False:
        raise ActivationPolicyError(
            "Activation policy report must not report private endpoint calls."
        )

    if report.get("execution_enabled_by_policy") is not False:
        raise ActivationPolicyError("Activation policy must not enable execution.")

    text = str(report).lower()
    forbidden_secret_terms = (
        "api_key",
        "api secret",
        "api_secret",
        "kraken_api_key",
        "kraken_api_secret",
        "password",
        "private key",
        "token=",
    )

    for term in forbidden_secret_terms:
        if term in text:
            raise ActivationPolicyError(f"Unsafe secret-like term detected: {term}")
'@

$docContent = @'
# Live Execution Activation Policy

Slice 17D defines the policy gate that must be satisfied before any future live execution work can be considered.

This document does not enable live trading.

## Current status

The system remains blocked by design.

No module in this slice:

- places orders
- cancels orders
- calls private execution endpoints
- enables live trading
- requires private account-changing permissions

## Required evidence before future live execution can be considered

All of these must be true before any future live-capable adapter can be reviewed:

| Evidence | Meaning |
|---|---|
| `kill_switch_off` | The operator intentionally moved the global kill switch out of blocking mode. |
| `live_trading_enabled` | The live trading config flag was intentionally enabled. |
| `explicit_confirmation_valid` | The required manual confirmation phrase was supplied. |
| `max_live_trade_value` | A positive CAD maximum was set. |
| `readiness_report_passed` | The manual readiness report passed. |
| `risk_gate_passed` | The risk gate approved the reviewed command. |
| `manual_approval_recorded` | A manual approval record exists for this exact command. |
| `audit_log_ready` | The local audit log is available and writable. |
| `adapter_capabilities_reviewed` | The adapter capability report was reviewed. |
| `adapter_reports_no_private_endpoint_call` | The adapter reports no private endpoint call before approval. |
| `operator_identity_recorded` | The operator identity is recorded in the review/audit trail. |
| `emergency_shutdown_procedure_confirmed` | The emergency shutdown procedure is known before execution. |
| `regression_suite_passed` | The master safety regression suite passed. |
| `dry_run_preview_recorded` | A dry-run preview exists for the exact command. |
| `order_value_within_limit` | The reviewed order value is inside the allowed CAD cap. |

## Required manual statement

The required statement is:

```text
I understand this is live trading with real financial risk and I approve this specific reviewed command only.
```

This statement is intentionally command-specific. It is not a blanket approval.

## Policy result meaning

A policy result can be:

| Status | Meaning |
|---|---|
| `blocked` | Required evidence is missing. |
| `review_required` | Reserved for future review workflows. |
| `theoretically_ready` | All evidence exists, but this policy still does not enable execution. |

Even `theoretically_ready` does not enable live execution in Slice 17D.

## Emergency shutdown rule

Before any future live-capable adapter can be reviewed:

1. The kill switch must be able to block execution immediately.
2. The operator must know how to disable live trading config.
3. The master safety regression suite must remain available.
4. A failed safety check must stop execution review.

## Slice 17D conclusion

This policy creates a strict gate before live execution work.

It remains documentation and validation only.
'@

$testContent = @'
"""
Validation script for Slice 17D.

This validates the live execution activation policy.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

from pathlib import Path

from tradingagents.execution.live_execution_activation_policy import (
    ActivationPolicyError,
    ActivationPolicyStatus,
    LiveExecutionActivationEvidence,
    assert_activation_policy_report_is_safe,
    build_theoretical_ready_evidence_for_tests,
    evaluate_live_execution_activation_policy,
)


def test_default_policy_is_blocked() -> None:
    result = evaluate_live_execution_activation_policy()
    report = result.safe_report()

    assert result.status == ActivationPolicyStatus.BLOCKED
    assert result.blocked is True
    assert result.theoretically_ready is False
    assert report["execution_enabled_by_policy"] is False
    assert report["secrets_included"] is False
    assert report["private_endpoint_called"] is False
    assert report["reason_count"] > 5

    assert_activation_policy_report_is_safe(report)

    print("[OK] default activation policy is blocked")


def test_theoretical_ready_policy_still_does_not_enable_execution() -> None:
    evidence = build_theoretical_ready_evidence_for_tests()
    result = evaluate_live_execution_activation_policy(evidence)
    report = result.safe_report()

    assert result.status == ActivationPolicyStatus.THEORETICALLY_READY
    assert result.blocked is True
    assert result.theoretically_ready is True
    assert report["execution_enabled_by_policy"] is False
    assert report["emergency_shutdown_required"] is True
    assert report["secrets_included"] is False
    assert report["private_endpoint_called"] is False

    assert_activation_policy_report_is_safe(report)

    print("[OK] theoretically ready policy still does not enable execution")


def expect_error(label: str, func) -> None:
    try:
        func()
    except ActivationPolicyError as exc:
        print(f"[OK] {label}: blocked safely ({exc})")
        return

    raise AssertionError(f"{label}: expected ActivationPolicyError")


def test_invalid_policy_inputs_are_rejected() -> None:
    expect_error(
        "negative max value rejected",
        lambda: LiveExecutionActivationEvidence(
            max_live_trade_value="-1",
        ).safe_report(),
    )

    expect_error(
        "non-numeric max value rejected",
        lambda: LiveExecutionActivationEvidence(
            max_live_trade_value="not-a-number",
        ).safe_report(),
    )

    expect_error(
        "non-CAD currency rejected",
        lambda: LiveExecutionActivationEvidence(
            max_live_trade_value="10",
            max_live_trade_value_currency="USD",
        ).safe_report(),
    )


def test_policy_document_exists() -> None:
    path = Path("docs/16_LIVE_EXECUTION_ACTIVATION_POLICY.md")
    assert path.exists()
    text = path.read_text(encoding="utf-8")

    required_phrases = (
        "Live Execution Activation Policy",
        "Required evidence before future live execution can be considered",
        "Required manual statement",
        "Emergency shutdown rule",
        "theoretically_ready",
        "does not enable live execution",
    )

    for phrase in required_phrases:
        assert phrase in text

    print("[OK] activation policy document exists")


def test_source_contains_no_private_execution_endpoint_names() -> None:
    source_paths = (
        Path("tradingagents/execution/live_execution_activation_policy.py"),
        Path("docs/16_LIVE_EXECUTION_ACTIVATION_POLICY.md"),
    )

    forbidden_terms = (
        "addorder",
        "cancelorder",
        "withdraw",
        "withdrawal",
        "deposit",
        "funding",
        "tradebalance",
        "ledgers",
    )

    for path in source_paths:
        source = path.read_text(encoding="utf-8").lower()
        for term in forbidden_terms:
            assert term not in source, f"Forbidden term {term!r} found in {path}"

    print("[OK] activation policy source contains no private execution endpoint names")


def main() -> None:
    print("Slice 17D validation: Live Execution Activation Policy")
    print("=" * 80)

    test_default_policy_is_blocked()
    test_theoretical_ready_policy_still_does_not_enable_execution()
    test_invalid_policy_inputs_are_rejected()
    test_policy_document_exists()
    test_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 17D live execution activation policy validation passed.")
    print("[PASS] Activation policy remains blocked and does not enable execution.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $policyPath -Value $policyContent -Encoding UTF8
Write-Host "[WRITTEN] $policyPath"

Set-Content -Path $docPath -Value $docContent -Encoding UTF8
Write-Host "[WRITTEN] $docPath"

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
## Slice 17D — Live Execution Activation Policy

Status: Implemented pending validation.

Goal:
Define the strict policy gate for any future live execution activation.

Scope:
- Create `tradingagents/execution/live_execution_activation_policy.py`.
- Create `docs/16_LIVE_EXECUTION_ACTIVATION_POLICY.md`.
- Create `scripts/test_live_execution_activation_policy.py`.
- Define required evidence before future live execution can be considered.
- Define required manual statement.
- Define emergency shutdown requirements.
- Validate that policy remains non-executing.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
## Slice 17D — Live Execution Activation Policy

A strict activation policy has been added before any future live-capable adapter work.

The policy requires:
- kill switch state review
- live trading config review
- explicit manual confirmation
- positive CAD cap
- readiness report
- risk gate
- manual approval record
- audit log readiness
- adapter capability review
- operator identity record
- emergency shutdown confirmation
- master regression suite pass
- dry-run preview record
- order value within limit

This slice does not enable execution.
"@

$decisionBlock = @"
## Slice 17D Decision — Define Activation Policy Before Live-Capable Adapter Work

Decision:
Add a formal activation policy before adding any live-capable adapter implementation.

Reason:
The project is now near the live execution boundary. A strict policy gate must exist before any future implementation can be reviewed.

Result:
The project now has a tested policy module and document that define required evidence, manual statement, and shutdown expectations without enabling execution.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 17D — Live Execution Activation Policy" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 17D — Live Execution Activation Policy" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 17D Decision — Define Activation Policy Before Live-Capable Adapter Work" -Block $decisionBlock

python -m py_compile $policyPath
python -m py_compile $testPath

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 17D FILES ==="
Get-Item `
    ".\tradingagents\execution\live_execution_activation_policy.py", `
    ".\docs\16_LIVE_EXECUTION_ACTIVATION_POLICY.md", `
    ".\scripts\test_live_execution_activation_policy.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 17D script completed."
