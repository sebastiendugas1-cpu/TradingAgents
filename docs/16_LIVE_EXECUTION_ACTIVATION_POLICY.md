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
