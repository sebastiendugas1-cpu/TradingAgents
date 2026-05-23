# Roadmap

## Slice-Based Development Rule

Each slice must be treated as a complete, testable block.

Each slice must define:

- Goal.
- Scope.
- Files changed.
- Full script or full function blocks.
- Test command.
- Expected result.
- Validation checklist.
- Commit message.

## Slice 1 — Project Documentation Foundation

Status: In progress.

Goal:

Create the core documentation structure that acts as the project source of truth.

Deliverables:

- `docs/00_PROJECT_VISION.md`
- `docs/01_SAFETY_RULES.md`
- `docs/02_ARCHITECTURE.md`
- `docs/03_ROADMAP.md`
- `docs/04_SLICE_WORKFLOW.md`
- `docs/05_DATA_SOURCES.md`
- `docs/06_TRADINGVIEW_PLAN.md`
- `docs/07_KRAKEN_PLAN.md`
- `docs/08_AGENT_DESIGN.md`
- `docs/09_BACKTESTING_AND_OPTIMIZATION.md`
- `docs/10_EXECUTION_AND_RISK_CONTROLS.md`
- `docs/11_DECISION_LOG.md`
- `docs/12_NEXT_CHAT_PROMPT.md`

Validation:

- Docs folder exists.
- All core docs exist.
- No source code changed.
- Git status shows documentation changes only.

Commit message:

```text
Add project foundation documentation
```

## Slice 2 — Project Audit Script

Goal:

Create a safe local audit script that reports project status.

Expected checks:

- Current Git branch.
- Python version.
- Conda environment.
- Editable package status.
- `.env` exists.
- API key presence without revealing secrets.
- Git status summary.

Expected command:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python scripts/project_audit.py
```

## Slice 3 — Asset Model and Symbol Normalization

Goal:

Create a common asset format for crypto and traditional assets.

Examples:

- `BTC/USD`
- `ETH/USD`
- `SOL/CAD`
- `AAPL`
- `SPY`

## Slice 4 — Kraken Public Market Data Adapter

Goal:

Fetch public Kraken data without private API keys.

No trading.

## Slice 5 — Local Data Cache

Goal:

Cache market data locally to reduce repeated API calls and support testing.

## Slice 6 — TradingView Integration Plan

Goal:

Document how TradingView alerts will enter the system.

## Slice 7 — TradingView Webhook Receiver

Goal:

Receive TradingView alerts safely.

No trading.

## Slice 8 — Modular Agent Decision Architecture

Status: Complete.

Goal:

Define structured outputs from specialized agents.

## Slice 9 — Strategy Scoring Engine

Status: Complete.

Goal:

Convert agent opinions into measurable trading decisions.

## Slice 10 — Backtesting Engine

Status: Complete.

Goal:

Evaluate strategies against historical data.

## Slice 11 — Paper Trading Engine

Status: Complete.

Goal:

Simulate live trading without real money using a safe paper account, fake balances, simulated fills, rejected orders, blocked orders, and P/L reporting.

## Slice 12A — Kraken Read-Only Safety Plan and Config Validator

Goal:

Read real account data with no trading permission.

## Slice 13 — Manual-Confirmation Trading

Goal:

System proposes trades, user approves manually.

Split into:

- Slice 13A — Manual-confirmation trading plan.
- Slice 13B — Trade proposal model.
- Slice 13C — Manual approval workflow.
- Slice 13D — Execution bridge, only after explicit approval and safety validation.

## Slice 14 — Restricted Live Trading

Goal:

Enable limited real order execution with strict risk controls.

## Slice 15 — Optimization and Tuning

Goal:

Use historical and paper-trading results to improve strategies.







## Slice 12B — Kraken Read-Only Mock Private Client

Goal:

Create a mock-only read-only Kraken private client interface before using real Kraken API keys.

Safety:

- No real Kraken private API calls.
- No real account access.
- No trading.
- No withdrawals.
- No funding actions.
- All execution-like methods must be explicitly blocked.

Validation:

- Mock balances can be read.
- Mock open orders can be read.
- Mock trade history can be read.
- Combined snapshot can be generated.
- `place_order`, `cancel_order`, `withdraw`, and funding actions are blocked.

## Slice 12C-1 — Kraken Read-Only Key Setup Guide and Environment Validator

Goal:

Validate local Kraken read-only credential configuration without calling Kraken private APIs.

Safety:

- No private Kraken requests.
- No balance access.
- No order access.
- No trading.
- No withdrawals.
- No secrets displayed in output.

Validation command:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python scripts/test_kraken_readonly_env_validator.py
```

Commit message:

```text
Add Kraken read-only environment validator
```

## Slice 12C-2 — Real Kraken Read-Only Client

Status: Complete when validation passes.

Goal:

Read balances, open orders, and recent trade history from Kraken using read-only credentials.

Forbidden:

- Place orders.
- Cancel orders.
- Withdraw funds.
- Funding operations.
- Trading permissions.

Validation command:

```powershell
D:; cd D:\Trading\TradingAgents; conda activate tradingagents; python .\scripts\test_kraken_real_readonly_client.py
```

Commit message:

```text
Add Kraken real read-only client
```

## Slice 13A — Manual-Confirmation Trading Plan

Status: Complete.

Goal:

Define the manual-confirmation workflow before any live execution code exists.

Deliverables:

- `docs/13_MANUAL_CONFIRMATION_TRADING_PLAN.md`

Rules:

- Planning only.
- No order placement.
- No Kraken trading permission.
- No cancellation.
- No withdrawals.
- No funding actions.

Commit message:

```text
Add manual-confirmation trading plan
```

## Slice 13D — Risk Gate Engine

Status: Complete.

Goal:

Create a hard safety gate that evaluates manually approved trade proposals before they can move to future dry-run/order-preview workflow.

Safety:

- No live trading.
- No order placement.
- No order cancellation.
- No funding actions.
- No withdrawals.

Commit message:

```text
Add risk gate engine
```

## Slice 13E — Kraken Order Preview / Dry-Run Model

Status: Complete.

Goal:

Create a Kraken-style order preview from an approved trade proposal that passed the risk gate.

Safety:

- No Kraken AddOrder call.
- No order cancellation.
- No live trading.
- No funding.
- No withdrawals.
- Dry-run-only payload generation.

Commit message:

```text
Add Kraken order preview dry-run model
```

## Slice 14A — Live Trading Kill Switch and Execution Safety Config

Status: Implemented pending validation.

Goal:
Create a global execution safety configuration that blocks all future live execution unless explicitly enabled.

Default safety state:
- `LIVE_TRADING_ENABLED=false`
- `KILL_SWITCH=true`
- `MAX_LIVE_TRADE_VALUE=0`

Scope:
- Configuration only.
- Validation only.
- No Kraken AddOrder call.
- No Kraken CancelOrder call.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/safety_config.py`
- `scripts/test_live_execution_safety_config.py`

Validation:
- Confirms live trading is disabled by default.
- Confirms kill switch is enabled by default.
- Confirms max live trade value is zero by default.
- Rejects unsafe settings.
- Rejects dangerous permission terms.
- Rejects dangerous executable action terms.
- Confirms safe reports do not expose secrets.

## Slice 14B — Disabled-by-Default Kraken Live Execution Client Skeleton

Status: Implemented pending validation.

Goal:
Create a disabled-by-default Kraken live execution client skeleton that is fully blocked by the Slice 14A safety config.

Scope:
- Create structured request models for future submit and cancel paths.
- Require `LiveExecutionSafetyConfig.assert_live_execution_allowed(...)` before any future executable action.
- Keep the client intentionally not implemented after the safety gate.
- Prove that default configuration blocks submit and cancel paths.
- Prove that no private Kraken execution endpoint call exists in this slice.

Files introduced:
- `tradingagents/execution/kraken_live_execution_client.py`
- `scripts/test_kraken_live_execution_client_skeleton.py`
- `scripts/create_slice_14b_kraken_live_execution_client_skeleton.ps1`

Still forbidden:
- No successful Kraken live order submission.
- No successful Kraken live order cancellation.
- No automatic live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Validation:
- Default safety config blocks submit and cancel paths.
- Kill switch blocks submit and cancel paths even when other settings look live-like.
- Even permissive test settings do not execute because live execution is intentionally not implemented.
- Private client test double is never called.
- Safe report excludes secrets.
- Client source contains no Kraken live execution endpoint names.

## Slice 14C — Live Execution Permission Preflight

Status: Implemented pending validation.

Goal:
Add a preflight validator that checks whether the environment and safety configuration are acceptable before any future live execution path can be considered.

Scope:
- Safety preflight only.
- Safe-to-log reporting only.
- No Kraken AddOrder call.
- No Kraken CancelOrder call.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/live_execution_preflight.py`
- `scripts/test_live_execution_permission_preflight.py`
- `scripts/create_slice_14c_live_execution_permission_preflight.ps1`

Validation confirms:
- Default preflight blocks live execution.
- Kill switch blocks preflight.
- Zero max live trade value blocks preflight.
- Missing explicit confirmation blocks preflight.
- Dangerous funding/withdrawal environment terms are detected.
- Secret values are not printed in the report.
- No Kraken execution endpoint call is introduced.

## Slice 14D — Manual Live Execution Readiness Report

Status: Implemented pending validation.

Goal:
Create a final readiness report that combines all safety layers before any future manual live execution can be considered.

Scope:
- Report safety configuration status.
- Report live execution preflight status.
- Report disabled Kraken execution client status.
- Report risk gate readiness status.
- Report manual approval readiness status.
- Produce a safe-to-log readiness report.
- Keep default state blocked.
- Do not call Kraken execution endpoints.
- Do not place or cancel orders.
- Do not require trading, funding, or withdrawal permissions.

Files introduced:
- `tradingagents/execution/manual_live_execution_readiness.py`
- `scripts/test_manual_live_execution_readiness_report.py`

Validation:
- Confirms default readiness is blocked.
- Confirms readiness assertion fails safely by default.
- Confirms permissive config remains blocked by the disabled client skeleton.
- Confirms risk gate and manual approval readiness are reported.
- Confirms safe report does not expose secrets.
- Confirms no execution endpoint names are present in readiness source.


## Slice 15A — Manual Live Order Simulation Package

Status: Implemented pending validation.

Goal:
Connect the existing safety and manual-execution layers into one safe end-to-end simulation package.

Scope:
- Builds a manual live order simulation package.
- Validates order intent.
- Includes manual live execution readiness status.
- Includes dry-run preview representation.
- Keeps the final result blocked by design.
- Does not place or cancel live orders.
- Does not call private execution endpoints.
- Does not require trading, funding, or withdrawal permissions.

Files introduced:
- `tradingagents/execution/manual_live_order_simulation_package.py`
- `scripts/test_manual_live_order_simulation_package.py`

Validation:
- Confirms default package is blocked.
- Confirms permissive config remains simulation-only.
- Confirms invalid order input is captured.
- Confirms dangerous environment terms keep the package blocked.
- Confirms no secrets are printed.
- Confirms no private execution endpoint names are introduced.

## Slice 15B — Execution Audit Log

Status: Implemented pending validation.

Goal:
Create a local append-only audit log model for every future simulated or live execution decision.

Scope:
- Audit record model.
- JSONL audit writer.
- Secret-like metadata redaction.
- Validation script.
- No private execution endpoint calls.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/execution_audit_log.py`
- `scripts/test_execution_audit_log.py`
- `scripts/create_slice_15b_execution_audit_log.ps1`

Validation:
- Confirms audit records can be created safely.
- Confirms JSONL records can be written and read.
- Confirms secret-like metadata is redacted.
- Confirms unsafe or malformed records are rejected.
- Confirms no private execution endpoint names are introduced.
