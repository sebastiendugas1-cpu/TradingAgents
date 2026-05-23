# Slice Workflow

## Purpose

This file defines how every development slice must be handled.

The goal is to avoid vague requests such as:

```text
Make a big block of code.
```

Instead, every slice must be treated as a complete, testable, documented block.

## Required Slice Format

Each slice must include:

```text
Slice Number:
Slice Name:
Goal:
Scope:
Files Changed:
Do Not Change:
Deliverables:
Test Command:
Expected Result:
Validation Checklist:
Commit Message:
```

## Standard Development Flow

1. Define the slice in the roadmap.
2. Confirm the branch.
3. Implement the full block.
4. Run the test command.
5. Capture terminal output using the AutoHotkey capture workflow.
6. Debug if needed.
7. Validate checklist.
8. Commit in GitHub Desktop.
9. Push to GitHub fork.
10. Update the decision log.

## Preferred Code Delivery Style

The user prefers:

- Full updated files when possible.
- Full updated function blocks when replacing functions.
- No tiny line-only patches unless the change is very small.
- Clear file placement instructions.
- Clear test commands.
- Clear expected output.

## Branch Strategy

Primary branches:

```text
main       = stable fork copy
crypto-dev = active development branch
```

Future feature branches may use:

```text
feature/slice-02-project-audit
feature/slice-03-asset-normalization
feature/slice-04-kraken-public-data
```

## Testing Rule

A slice is not complete until it has:

- Code or docs delivered.
- Test command run.
- Output reviewed.
- Validation checklist passed.
- Git commit created.
- Push completed if appropriate.

## Safety Rule

No live trading code is allowed unless the slice explicitly belongs to the restricted live trading phase and all previous safety layers are complete.
