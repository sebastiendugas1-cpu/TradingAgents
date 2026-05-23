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

## Slice 15C — Simulated Execution Package Audit Integration

Status: Implemented pending validation.

Goal:
Connect the Slice 15A manual live order simulation package to the Slice 15B execution audit log.

Scope:
- Builds a manual live order simulation package.
- Converts the package into a safe execution audit record.
- Writes the record to a local JSONL audit file.
- Reads the record back for validation.
- Redacts restricted account-permission terms from audit reasons.
- Does not place or cancel live orders.
- Does not call private execution endpoints.
- Does not require trading, funding, or withdrawal permissions.

Files introduced:
- `tradingagents/execution/simulated_execution_audit_integration.py`
- `scripts/test_simulated_execution_audit_integration.py`

Validation:
- Confirms default simulation package is written to audit log.
- Confirms permissive config still audits simulation-only behavior.
- Confirms dangerous environment terms are redacted in audit reasons.
- Confirms invalid order input cannot become a valid audit record.
- Confirms no secrets are printed.
- Confirms no private execution endpoint names are introduced.

## Slice 15D — Manual Execution Command Model

Status: Implemented pending validation.

Goal:
Create a formal non-executable command object for a future manually approved live execution path.

Scope:
- Adds a manual execution command model.
- Links command records to simulation package IDs.
- Links command records to execution audit IDs.
- Validates pair, side, order type, volume, limit price, status, and reason text.
- Provides safe-to-log command reports.
- Keeps commands non-executable by design.

Still forbidden:
- No Kraken AddOrder call.
- No Kraken CancelOrder call.
- No live trading.
- No funding.
- No withdrawals.
- No trading API permission requirement.

Files introduced:
- `tradingagents/execution/manual_execution_command.py`
- `scripts/test_manual_execution_command_model.py`
- `scripts/create_slice_15d_manual_execution_command_model.ps1`

Validation:
- Confirms valid command creation.
- Confirms command reports are safe to log.
- Confirms commands cannot execute.
- Confirms blocked command state.
- Confirms invalid command fields are rejected.
- Confirms sensitive-looking metadata is redacted.
- Confirms no private execution endpoint call was introduced.

## Slice 15E — Manual Execution Command Builder

Status: Implemented pending validation.

Goal:
Connect the simulation package, audit log, and manual execution command model into one safe builder.

Scope:
- Build a simulation-only package.
- Write/read a safe local audit record.
- Build a non-executable manual execution command linked to package ID and audit ID.
- Produce a safe-to-log build report.
- Keep commands blocked from live execution.

Still forbidden:
- No Kraken live order submission.
- No Kraken live order cancellation.
- No live trading.
- No funding.
- No withdrawals.
- No trading permission requirement.

## Slice 15F — Manual Execution Command Review CLI

Status: Implemented pending validation.

Goal:
Add a local command-line review tool that builds a non-executable manual execution command candidate from terminal arguments.

Scope:
- Accept pair, side, order type, volume, limit price, and audit file path.
- Build the simulation/audit/command-builder workflow.
- Print a safe human-readable or JSON review summary.
- Keep the result blocked and non-executable.
- No private execution endpoint call.
- No live trading action.
- No private account-changing permission requirement.

Files introduced:
- `tradingagents/execution/manual_execution_review_cli.py`
- `scripts/test_manual_execution_review_cli.py`
- `scripts/create_slice_15f_manual_execution_review_cli.ps1`

## Slice 15G — Manual Execution Review CLI Sample Runner

Status: Implemented pending validation.

Goal:
Add a simple sample runner for the manual execution review pipeline.

Scope:
- Create scripts/run_manual_execution_review_sample.py.
- Create scripts/test_manual_execution_review_sample.py.
- Use one fixed BTC/CAD sample command.
- Write a local JSONL audit record.
- Print a clean blocked / non-executable summary.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 15H — Manual Execution Review CLI Usage Guide

Status: Implemented pending validation.

Goal:
Document how to safely use the manual execution review CLI and sample runner.

Scope:
- Create docs/15_MANUAL_EXECUTION_REVIEW_CLI_USAGE.md.
- Create scripts/test_manual_execution_review_cli_usage_guide.py.
- Document sample runner commands.
- Document custom review commands.
- Document audit log location.
- Document blocked / non-executable output interpretation.

Safety:
- Documentation and validation only.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 16A — Manual Execution Pipeline End-to-End Regression Test

Status: Implemented pending validation.

Goal:
Add one regression test that validates the complete manual execution review pipeline.

Scope:
- Create scripts/test_manual_execution_pipeline_regression.py.
- Validate the fixed sample runner.
- Validate the custom manual execution review CLI.
- Validate local audit log write/read behavior.
- Validate the usage guide exists.
- Validate source files do not contain private execution endpoint names.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 16B — Full Project Safety Regression Runner

Status: Implemented pending validation.

Goal:
Create one master regression runner for the execution safety foundation.

Scope:
- Create scripts/run_execution_safety_regression_suite.py.
- Create scripts/test_execution_safety_regression_suite_runner.py.
- Run the recent execution safety validation scripts as subprocesses.
- Produce one safe PASS/FAIL summary.
- Support JSON output for automated review.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 17A — Live Execution Adapter Interface

Status: Implemented pending validation.

Goal:
Define the abstract interface boundary for future execution adapters.

Scope:
- Create 	radingagents/execution/execution_adapter.py.
- Create scripts/test_execution_adapter_interface.py.
- Define submit/cancel request models.
- Define execution result model.
- Define adapter capabilities model.
- Define execution adapter protocol.
- Add a mock adapter for validation.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 17B — Execution Adapter Integration with Manual Command Builder

Status: Implemented pending validation.

Goal:
Connect the manual execution command builder to the execution adapter interface using the mock adapter only.

Scope:
- Create 	radingagents/execution/execution_adapter_command_integration.py.
- Create scripts/test_execution_adapter_command_integration.py.
- Build a manual command from order intent.
- Build a submit request for the mock adapter.
- Route the request through MockExecutionAdapter.
- Produce a safe blocked integration report.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 17C — Add Adapter Tests to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the new execution adapter interface and adapter-command integration with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_execution_adapter_interface.py.
- Add scripts/test_execution_adapter_command_integration.py.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes adapter tests.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 17D — Live Execution Activation Policy

Status: Implemented pending validation.

Goal:
Define the strict policy gate for any future live execution activation.

Scope:
- Create 	radingagents/execution/live_execution_activation_policy.py.
- Create docs/16_LIVE_EXECUTION_ACTIVATION_POLICY.md.
- Create scripts/test_live_execution_activation_policy.py.
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

## Slice 17E — Add Activation Policy Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 17D activation policy with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_live_execution_activation_policy.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the activation policy test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 17F — Kraken Live Adapter Skeleton Behind Activation Policy

Status: Implemented pending validation.

Goal:
Create a disabled Kraken live adapter skeleton behind the execution adapter interface and activation policy.

Scope:
- Create 	radingagents/execution/kraken_live_adapter_skeleton.py.
- Create scripts/test_kraken_live_adapter_skeleton.py.
- Declare skeleton capabilities as disabled/future-live.
- Require activation policy evaluation.
- Block submit/cancel paths by default.
- Validate no private endpoint call exists.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 17G — Add Kraken Adapter Skeleton Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the disabled Kraken live adapter skeleton with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_live_adapter_skeleton.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the Kraken adapter skeleton test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 18A — Kraken Private Order Request Translator, No Endpoint Call

Status: Implemented pending validation.

Goal:
Translate safe manual execution commands into Kraken-style order payloads for review only.

Scope:
- Create 	radingagents/execution/kraken_private_order_request_translator.py.
- Create scripts/test_kraken_private_order_request_translator.py.
- Translate ManualExecutionCommand to a Kraken-style review payload.
- Translate SubmitOrderRequest to a Kraken-style review payload.
- Validate pair/side/order type/volume/price.
- Force payloads to alidate=true.
- Validate reports are safe to log.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 18B — Add Kraken Order Translator Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 18A Kraken private order request translator with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_private_order_request_translator.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the Kraken order translator test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 18C — Kraken Order Translator Integration with Adapter Skeleton

Status: Implemented pending validation.

Goal:
Connect the Kraken order request translator to the disabled Kraken live adapter skeleton.

Scope:
- Create 	radingagents/execution/kraken_order_translation_adapter_integration.py.
- Create scripts/test_kraken_order_translation_adapter_integration.py.
- Build manual command candidates from order intent.
- Build SubmitOrderRequest.
- Translate to Kraken-style validate=true review payload.
- Route through disabled KrakenLiveAdapterSkeleton.
- Return a blocked safe integration report.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 18D — Add Kraken Translator Adapter Integration Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 18C Kraken order translator adapter integration with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_order_translation_adapter_integration.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the Kraken translator adapter integration test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 18E — Kraken Order Payload Review CLI

Status: Implemented pending validation.

Goal:
Add a human-readable CLI for reviewing Kraken-style validate=true order payloads.

Scope:
- Create scripts/run_kraken_order_payload_review.py.
- Create scripts/test_kraken_order_payload_review_cli.py.
- Build command candidates from CLI arguments.
- Translate to Kraken-style validate=true payload.
- Route through disabled Kraken adapter skeleton.
- Print text or JSON safe review output.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 18F — Add Kraken Payload Review CLI Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 18E Kraken order payload review CLI with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_order_payload_review_cli.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the payload review CLI test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 19A — Disabled Kraken Private Client Shell

Status: Implemented pending validation.

Goal:
Create a disabled private client shell for future Kraken private operations.

Scope:
- Create 	radingagents/execution/kraken_private_client_shell.py.
- Create scripts/test_kraken_private_client_shell.py.
- Define safe config and result models.
- Define blocked submit preview, cancel preview, and status preview methods.
- Require activation policy evaluation.
- Validate that no private endpoint call exists.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 19B — Add Kraken Private Client Shell Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 19A disabled Kraken private client shell with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_private_client_shell.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the private client shell test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 19C — Private Client Shell Integration with Payload Review CLI

Status: Implemented pending validation.

Goal:
Connect the Kraken payload review path to the disabled Kraken private client shell.

Scope:
- Create 	radingagents/execution/kraken_payload_review_private_client_integration.py.
- Create scripts/test_kraken_payload_review_private_client_integration.py.
- Build Kraken-style validate=true payload review.
- Route payload into KrakenPrivateClientShell.submit_private_order_preview.
- Return a blocked safe integration report.
- Validate that no private endpoint call exists.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 19D — Add Payload Review Private Client Integration Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 19C payload review private client integration with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_payload_review_private_client_integration.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master safety suite includes the payload review private client integration test.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 19E — Add Private Client Result to Payload Review CLI

Status: Implemented pending validation.

Goal:
Extend the Kraken payload review CLI so it shows the disabled private client shell preview result.

Scope:
- Update scripts/run_kraken_order_payload_review.py.
- Update scripts/test_kraken_order_payload_review_cli.py.
- Route the CLI review path through the Slice 19C private client integration.
- Include private_client_report in text and JSON output.
- Validate the private client report remains blocked and safe.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 20A — Disabled Kraken Private Transport Shell

Status: Implemented pending validation.

Goal:
Create a disabled private transport shell for future Kraken private HTTP request handling.

Scope:
- Create 	radingagents/execution/kraken_private_transport_shell.py.
- Create scripts/test_kraken_private_transport_shell.py.
- Define safe config, preview request, and result models.
- Define a blocked preview private request method.
- Require activation policy evaluation.
- Validate that no network or private endpoint call exists.

Safety:
- No network call.
- No request signing.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 20B — Add Disabled Kraken Private Transport Shell Test to Master Safety Regression Suite

Status: Implemented pending validation.

Goal:
Protect the Slice 20A disabled Kraken private transport shell with the master safety regression suite.

Scope:
- Update scripts/run_execution_safety_regression_suite.py.
- Add scripts/test_kraken_private_transport_shell.py to the default safety suite.
- Update scripts/test_execution_safety_regression_suite_runner.py.
- Validate that the master suite includes the disabled private transport shell test.

Safety:
- No network call.
- No request signing.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.

## Slice 20C — Private Client Shell to Transport Shell Integration

Status: Implemented pending validation.

Goal:
Connect the disabled Kraken private client shell boundary to the disabled Kraken private transport shell boundary.

Scope:
- Create 	radingagents/execution/kraken_private_client_transport_integration.py.
- Create scripts/test_kraken_private_client_transport_integration.py.
- Route a safe payload preview through the disabled transport shell.
- Preserve blocked, non-executable behavior.
- Validate that no network or private endpoint call exists.

Safety:
- No network call.
- No request signing.
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
