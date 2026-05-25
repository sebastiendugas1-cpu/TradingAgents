# High-Level Project Architecture Checkpoint

### Slice 22F - High-Level Project Source-of-Truth Architecture Checkpoint

Checkpoint after Slice 22E:

- Latest validated TradingAgents commit: `68880df Add execution safety state checkpoint`
- Branch: `crypto-dev`
- Master execution safety regression suite: 29 tests passing / 0 failing
- Local repo currently being worked: `D:\Trading\TradingAgents`
- TradingAgents role: research/decision brain template and controlled execution-safety development branch
- crypto-trading-agent role: Kraken safety/execution/reconciliation shell and broader project source-of-truth repo
- Current execution state: disabled Kraken private execution review chain only
- Current signing state: disabled/data-only review plumbing only
- Payload review CLI: can expose disabled signing-material review state
- Private signer shell: disabled and non-executable
- Private transport shell: disabled and non-networking
- Private client shell: disabled and non-executable

Hard safety boundaries still in force:

- Do not introduce real order placement.
- Do not introduce real order cancellation.
- Do not introduce private endpoint calls.
- Do not introduce network calls in private execution code.
- Do not introduce API secret usage.
- Do not introduce environment secret reading.
- Do not introduce nonce generation.
- Do not introduce HMAC/hashlib/base64 signing implementation.
- Do not introduce live trading.
- Do not introduce private account-changing permission requirements.

Architecture decision preserved:

- TradingAgents is not becoming the unchecked live-trading engine.
- TradingAgents is being used to develop and test the decision/review/safety chain in isolated, safety-gated slices.
- The broader `crypto-trading-agent` project remains the intended Kraken safety/execution/reconciliation shell.
- Before transferring or applying this work to `crypto-trading-agent`, confirm the current source-of-truth file in that repo and reconcile this checkpoint with it.

Recommended next step:

- Either continue with disabled/data-only review plumbing in TradingAgents, or switch to the `crypto-trading-agent` repo and update its high-level source-of-truth architecture document with this validated TradingAgents checkpoint.
