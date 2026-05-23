# Next Chat Prompt

Use this prompt when starting a new chat for this project.

```text
We are working on the TradingAgents repo for a custom multi-asset / crypto trading agent project.

Local project path:
D:\Trading\TradingAgents

GitHub fork:
https://github.com/sebastiendugas1-cpu/TradingAgents

Active development branch:
crypto-dev

Current project status:
We are building the project in slices. The Markdown files in /docs are the source of truth.

Important docs:
- docs/00_PROJECT_VISION.md
- docs/01_SAFETY_RULES.md
- docs/02_ARCHITECTURE.md
- docs/03_ROADMAP.md
- docs/04_SLICE_WORKFLOW.md
- docs/11_DECISION_LOG.md

Development rules:
- Use full updated files or full function blocks.
- Avoid tiny partial snippets unless the change is very small.
- Every slice needs a goal, scope, test command, expected result, validation checklist, and commit message.
- No live trading yet.
- No Kraken trading keys yet.
- No withdrawal permission ever.
- TradingView is planned as a signal/alert layer.
- Kraken is planned as crypto market data and eventual execution platform.
- Start with analysis-only, then data, then backtesting, then paper trading, then read-only Kraken, then manual-confirmation trading, then restricted live trading.

User workflow:
The user runs local commands and captures terminal output with AutoHotkey into:
.chatGPT-output/output.txt

When debugging, ask the user to run commands and paste/upload the latest output.
```
