# Execution and Risk Controls

## Purpose

This file defines the controls required before order execution.

## Execution Modes

### Mode 1 — Analysis Only

No orders.

### Mode 2 — Paper Trading

Simulated orders only.

### Mode 3 — Manual Confirmation

System proposes orders, user approves manually.

### Mode 4 — Restricted Automation

System may place limited orders under strict controls.

## Required Risk Controls Before Live Trading

- Max trade size.
- Max daily loss.
- Max total exposure.
- Max open positions.
- Max open orders.
- Stop-loss requirement.
- Cooldown after losing trades.
- Kill switch.
- Manual override.
- Full audit log.

## Block Conditions

The system must block trades when:

- API key permissions are unsafe.
- Daily loss limit is reached.
- Trade size exceeds limit.
- Symbol is not approved.
- Strategy confidence is below threshold.
- Risk score is too high.
- Required market data is missing.
- User has not approved in manual-confirmation mode.

## Audit Log Requirement

Every proposed, blocked, simulated, or executed trade must be logged.

Log should include:

- Timestamp.
- Asset.
- Direction.
- Size.
- Price.
- Reason.
- Agent scores.
- Risk decision.
- Execution mode.
- Result.

## Manual-Confirmation Requirements

Before any future live order execution can exist, the system must implement manual-confirmation controls.

Required behavior:

- Create a trade proposal.
- Show the full risk summary.
- Require explicit user approval.
- Reject vague approval words.
- Log every proposed, blocked, rejected, approved, simulated, or executed trade.
- Never execute without explicit approval.
- Never store secrets in logs.

A valid approval should require a deliberate confirmation phrase such as:

```text
APPROVE
```

Manual-confirmation must be validated before restricted automation is considered.

## Slice 14A — Global Live Execution Safety Config

A global live execution safety config has been introduced.

Default behavior is intentionally restrictive:
- Live trading is disabled.
- Kill switch is enabled.
- Maximum live trade value is zero.

The config is implemented in:

`tradingagents/execution/safety_config.py`

Future live execution code must call the safety gate before any executable action is allowed.

Current restrictions:
- No live trading code exists in this slice.
- No Kraken AddOrder call exists in this slice.
- No Kraken CancelOrder call exists in this slice.
- No withdrawal code exists in this slice.
- No funding code exists in this slice.
- No trading permission is required for this slice.

The safety config provides a safe report that excludes secrets and raw credential values.

## Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton

A disabled-by-default Kraken live execution client skeleton has been introduced.

The client is implemented in:

`tradingagents/execution/kraken_live_execution_client.py`

Safety requirements:
- All future executable paths must pass through `LiveExecutionSafetyConfig.assert_live_execution_allowed(...)`.
- Default config blocks all submit/cancel paths.
- Kill switch blocks all submit/cancel paths.
- Even if a permissive test config is supplied, Slice 14B raises a not-implemented error instead of calling any private client.

Current restrictions:
- No real Kraken live execution endpoint call exists.
- No live order submission is implemented.
- No live cancellation is implemented.
- No withdrawal or funding behavior exists.
- No trading permission is required for validation.

## Slice 14C — Live Execution Permission Preflight

A live execution permission preflight layer has been introduced.

The preflight layer reports:
- Whether live trading is enabled.
- Whether the kill switch is active.
- The maximum configured live trade value.
- Whether explicit confirmation is present and valid.
- Whether dangerous funding/withdrawal environment terms were detected.

The preflight report is safe to log:
- It does not expose API keys.
- It does not expose API secrets.
- It does not expose token or password values.
- It records whether execution endpoints were called, which remains false in this slice.

Current restrictions remain unchanged:
- No Kraken AddOrder call exists in this slice.
- No Kraken CancelOrder call exists in this slice.
- No withdrawal code exists in this slice.
- No funding code exists in this slice.
- No trading permission is required for this slice.

## Slice 14D — Manual Live Execution Readiness Report

The project now includes a combined manual live execution readiness report.

The readiness report combines:
- Safety config status.
- Live execution preflight status.
- Disabled Kraken live execution client status.
- Risk gate readiness status.
- Manual approval readiness status.

Default result:
- Live execution remains blocked.
- The report is safe to log.
- No secrets are printed.
- No Kraken execution endpoints are called.
- No trading, funding, or withdrawal permission is required.

This slice is still a safety/reporting slice only. It does not enable live trading.


## Slice 15A — Manual Live Order Simulation Package

Slice 15A connects the manual execution pipeline into a safe simulation package.

The package combines:
- order intent validation
- live execution readiness reporting
- dry-run preview representation
- a final simulation-only boundary

This slice remains blocked by design.

Current restrictions:
- No live order placement.
- No live order cancellation.
- No private execution endpoint calls.
- No funding behavior.
- No withdrawal behavior.
- No trading API permission requirement.

The output is safe to log and does not include secrets.

## Slice 15B — Execution Audit Log

An execution audit log layer has been introduced.

Purpose:
- Record every future simulated or live execution decision.
- Preserve package ID, pair, side, order type, volume, price, readiness status, risk status, approval status, preview status, final status, and reasons.
- Store records in append-only JSONL format.
- Redact secret-like metadata before writing.

Current restrictions:
- No private execution endpoint call exists in this slice.
- No order placement exists in this slice.
- No order cancellation exists in this slice.
- No funding or withdrawal behavior exists in this slice.
- No trading permission is required for this slice.

Default local audit output path:

`.chatGPT-output/execution_audit/execution_audit.jsonl`

This path is intended for local ignored output, not committed project state.

## Slice 15C — Simulated Execution Package Audit Integration

Slice 15C connects the simulation package to local audit logging.

The integration performs this safe flow:

`manual order simulation package -> execution audit record -> local JSONL audit file -> read-back validation`

Current restrictions:
- No live order placement.
- No live order cancellation.
- No private execution endpoint calls.
- No funding behavior.
- No withdrawal behavior.
- No trading API permission requirement.

Audit records are local-only and written to ignored output locations unless a test supplies a temporary path.

## Slice 15D — Manual Execution Command Model

Slice 15D adds a non-executable command model for future manual live execution.

The command model links together:
- a command ID
- a simulation package ID
- an execution audit record ID
- pair
- side
- order type
- volume
- limit price
- command status
- reasons
- safe metadata

Command statuses:
- `draft`
- `blocked`
- `ready_for_review`
- `approved_for_future_execution`

Important safety behavior:
- A command object cannot execute anything.
- Even an `approved_for_future_execution` command remains non-executable in this slice.
- Reports are safe to log.
- Sensitive-looking metadata is redacted.
- Funding, withdrawal, and transfer terms are rejected from command reason text.

This slice does not add private execution endpoint calls and does not require trading permissions.

## Slice 15E — Manual Execution Command Builder

The manual execution command builder connects the safe simulation and audit layers with the command model.

The builder:
- Creates a simulation package.
- Writes a local JSONL audit record.
- Creates a manual command candidate linked to the simulation package and audit record.
- Produces a safe-to-log report.
- Remains non-executable by design.

This slice does not introduce live exchange execution.

## Slice 15F — Manual Execution Command Review CLI

Slice 15F introduces a local CLI review tool for manual execution command candidates.

The CLI:
- Builds the existing simulation package.
- Writes the local audit record.
- Builds the manual execution command candidate.
- Prints a safe review summary.
- Clearly reports that the command is blocked and non-executable.

This slice does not add private execution endpoint calls or live trading actions.

## Slice 15G — Manual Execution Review Sample Runner

A sample runner has been added for the manual execution review pipeline.

The sample runner:
- Builds a known-safe BTC/CAD review sample.
- Writes a local JSONL audit record.
- Prints a blocked and non-executable review summary.
- Confirms execution is not allowed.

The sample runner remains non-executable and does not call private execution endpoints.

## Slice 15H — Manual Execution Review CLI Usage Guide

The manual execution review CLI now has a usage guide.

The guide documents:
- how to run the fixed sample
- how to run a custom review
- how to read blocked / non-executable output
- where local audit logs are written
- what remains forbidden before future live execution work

This slice is documentation and validation only.

## Slice 16A — Manual Execution Pipeline Regression Test

A regression test now validates the full manual execution review pipeline.

The regression test checks:
- sample runner output
- custom CLI output
- audit log write/read behavior
- blocked / non-executable status
- safe source wording
- usage guide presence

This protects the safe manual-review workflow from accidental breakage in future slices.

## Slice 16B — Full Project Safety Regression Runner

A master safety regression runner has been added.

The runner validates the recent execution safety foundation:
- live execution safety config
- disabled live execution client skeleton
- permission preflight
- readiness report
- simulation package
- audit log
- command model
- command builder
- review CLI
- sample runner
- usage guide
- manual execution pipeline regression

This gives the project one command to verify the safety foundation before future execution-adjacent work.

## Slice 17A — Live Execution Adapter Interface

The project now has an execution adapter interface boundary.

The interface defines:
- submit request model
- cancel request model
- execution result model
- capabilities declaration
- adapter protocol
- mock adapter

The mock adapter remains blocked and simulation-only. This slice does not add any real exchange execution call.

## Slice 17B — Execution Adapter + Command Builder Integration

The manual execution command builder is now connected to the execution adapter interface through the mock adapter only.

This integration proves:
- the command builder can produce a command candidate
- the adapter request model can wrap that command
- the mock adapter returns a blocked/non-live result
- the full report is safe to log

This slice does not add any real exchange execution call.

## Slice 17C — Adapter Tests Added to Safety Regression Suite

The master execution safety regression suite now includes:
- execution adapter interface validation
- execution adapter command integration validation

This ensures future safety-suite runs protect the adapter boundary and mock adapter integration.

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

## Slice 17E — Activation Policy Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- live execution activation policy validation

This ensures future safety-suite runs protect the policy gate before live-capable adapter work continues.

## Slice 17F — Kraken Live Adapter Skeleton Behind Activation Policy

A disabled Kraken live adapter skeleton has been added behind:
- the execution adapter interface
- the activation policy
- default blocking behavior

The skeleton:
- declares future-live capabilities
- remains disabled
- blocks submit/cancel requests
- reports no private endpoint calls
- includes no real exchange execution call

## Slice 17G — Kraken Adapter Skeleton Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- disabled Kraken live adapter skeleton validation

This ensures future safety-suite runs protect the Kraken adapter skeleton before more live-adjacent work continues.

## Slice 18A — Kraken Private Order Request Translator

A Kraken-style order request translator has been added for review-only payload generation.

The translator:
- accepts safe command/request objects
- validates trading pair, side, order type, volume, and price
- creates a Kraken-style payload with validate=true
- produces safe reports
- does not call Kraken
- does not enable execution

## Slice 18B — Kraken Order Translator Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- Kraken private order request translator validation

This ensures future safety-suite runs protect the review-only Kraken order payload translator before more live-adjacent work continues.

## Slice 18C — Kraken Order Translator + Adapter Skeleton Integration

The Kraken-style order payload translator now integrates with the disabled Kraken live adapter skeleton.

The integration:
- builds a command candidate
- builds a submit request
- creates a validate=true Kraken-style review payload
- routes through the disabled skeleton
- returns a blocked safe report
- does not call Kraken

## Slice 18D — Kraken Translator Adapter Integration Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- Kraken order translator adapter integration validation

This ensures future safety-suite runs protect the validate=true payload translation and disabled adapter routing path.

## Slice 18E — Kraken Order Payload Review CLI

A CLI has been added to review Kraken-style validate=true payloads.

The CLI:
- accepts pair, side, order type, volume, and optional limit price
- creates a review-only Kraken-style payload
- routes through the disabled adapter skeleton
- prints blocked safe output
- supports JSON mode
- does not call Kraken

## Slice 18F — Kraken Payload Review CLI Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- Kraken order payload review CLI validation

This ensures future safety-suite runs protect the human-readable payload review workflow before private-client shell work begins.

## Slice 19A — Disabled Kraken Private Client Shell

A disabled Kraken private client shell has been added.

The shell:
- has no network transport
- has no private endpoint implementation
- blocks submit/cancel/status preview methods
- requires activation policy evaluation
- reports no private endpoint calls
- does not enable execution

## Slice 19B — Kraken Private Client Shell Test Added to Safety Regression Suite

The master execution safety regression suite now includes:
- disabled Kraken private client shell validation

This ensures future safety-suite runs protect the private client boundary before any private-client implementation work continues.
