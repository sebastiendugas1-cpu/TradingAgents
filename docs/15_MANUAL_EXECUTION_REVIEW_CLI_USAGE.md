# Manual Execution Review CLI Usage Guide

Slice 15H documents how to safely use the manual execution review pipeline.

This guide covers:

- the fixed sample runner
- the custom manual execution review CLI
- where local audit logs are written
- how to interpret blocked / non-executable output
- what is still forbidden
- what must happen before any future live execution work

## Current safety status

The manual execution review tools are intentionally non-executable.

They do not:

- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions

The review tools only create safe local review data and local audit records.

## Run the fixed sample

From the project root:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python .\scripts\run_manual_execution_review_sample.py; Read-Host "Press Enter to close..."
```

Expected behavior:

- prints a manual execution review sample
- marks the command as blocked
- marks the command as non-executable
- writes a local JSONL audit record under `reports/`
- does not call private execution endpoints

## Run the fixed sample as JSON

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python .\scripts\run_manual_execution_review_sample.py --json; Read-Host "Press Enter to close..."
```

Use JSON mode when you want to inspect the output as structured data.

## Run a custom manual execution review

Example:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python -m tradingagents.execution.manual_execution_review_cli --pair BTC/CAD --side buy --order-type limit --volume 0.000085168 --limit-price 100000 --audit-file-path reports/manual_execution_review.jsonl; Read-Host "Press Enter to close..."
```

This creates a blocked non-executable review for a custom order intent.

## Run a custom manual execution review as JSON

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python -m tradingagents.execution.manual_execution_review_cli --pair SOL/CAD --side buy --order-type limit --volume 0.1 --limit-price 200 --audit-file-path reports/manual_execution_review.jsonl --json; Read-Host "Press Enter to close..."
```

## Audit log location

By default, local review tools write JSONL audit records under:

```text
reports/
```

The `reports/` folder is local output and should remain ignored by Git.

Each audit record is intended for local review and later reconciliation.

## How to interpret the output

Important fields:

| Field | Meaning |
|---|---|
| `blocked` | Must be `true` in the current phase. |
| `non_executable` | Must be `true` in the current phase. |
| `execution_allowed` | Must be `false` in the current phase. |
| `command_status` | Shows the command review state, normally `blocked`. |
| `final_status` | Should clearly state that the command is blocked from live execution. |
| `audit_id` | ID of the local audit record. |
| `command_id` | ID of the non-executable command candidate. |
| `package_id` | ID of the simulation package. |
| `secrets_included` | Must be `false`. |
| `execution_endpoint_called` | Must be `false`. |

## What is still forbidden

The current system must not:

- place a real order
- cancel a real order
- enable automatic live execution
- use private account-changing permissions
- remove the global kill switch
- bypass manual review
- bypass the risk gate
- bypass audit logging

## What must happen before future live execution work

Before any future live execution slice is considered, the project must still preserve:

- global safety config
- kill switch
- max live trade value cap
- live execution preflight
- manual readiness report
- manual approval workflow
- risk gate
- dry-run / preview layer
- local audit log
- manual execution command model
- explicit user review

## Slice 15H conclusion

The current manual execution review pipeline is useful for local testing and review.

It remains blocked and non-executable by design.
