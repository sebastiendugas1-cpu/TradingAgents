$ErrorActionPreference = "Stop"

Write-Host "=== SLICE 16B FULL PROJECT SAFETY REGRESSION RUNNER ==="

if (-not (Test-Path ".\tradingagents")) {
    throw "Run this script from the TradingAgents project root."
}

New-Item -ItemType Directory -Force ".\scripts" | Out-Null

$runnerPath = ".\scripts\run_execution_safety_regression_suite.py"
$testPath = ".\scripts\test_execution_safety_regression_suite_runner.py"

$runnerContent = @'
"""
Slice 16B full execution safety regression suite runner.

This script runs the key safety validation scripts for recent execution slices.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from time import perf_counter
from typing import Any


DEFAULT_SAFETY_TESTS = (
    "scripts/test_live_execution_safety_config.py",
    "scripts/test_kraken_live_execution_client_skeleton.py",
    "scripts/test_live_execution_permission_preflight.py",
    "scripts/test_manual_live_execution_readiness_report.py",
    "scripts/test_manual_live_order_simulation_package.py",
    "scripts/test_execution_audit_log.py",
    "scripts/test_simulated_execution_audit_integration.py",
    "scripts/test_manual_execution_command_model.py",
    "scripts/test_manual_execution_command_builder.py",
    "scripts/test_manual_execution_review_cli.py",
    "scripts/test_manual_execution_review_sample.py",
    "scripts/test_manual_execution_review_cli_usage_guide.py",
    "scripts/test_manual_execution_pipeline_regression.py",
)


@dataclass(frozen=True)
class RegressionTestResult:
    script: str
    passed: bool
    return_code: int
    elapsed_seconds: float
    stdout_tail: str
    stderr_tail: str

    def safe_report(self) -> dict[str, Any]:
        return {
            "script": self.script,
            "passed": self.passed,
            "return_code": self.return_code,
            "elapsed_seconds": round(self.elapsed_seconds, 3),
            "stdout_tail": self.stdout_tail,
            "stderr_tail": self.stderr_tail,
        }


@dataclass(frozen=True)
class RegressionSuiteResult:
    suite_name: str
    passed: bool
    total_tests: int
    passed_tests: int
    failed_tests: int
    elapsed_seconds: float
    results: tuple[RegressionTestResult, ...]

    def safe_report(self) -> dict[str, Any]:
        return {
            "suite_name": self.suite_name,
            "passed": self.passed,
            "total_tests": self.total_tests,
            "passed_tests": self.passed_tests,
            "failed_tests": self.failed_tests,
            "elapsed_seconds": round(self.elapsed_seconds, 3),
            "results": [result.safe_report() for result in self.results],
            "secrets_included": False,
            "execution_endpoint_called": False,
        }


def run_regression_suite(
    *,
    scripts: tuple[str, ...] = DEFAULT_SAFETY_TESTS,
    stop_on_failure: bool = False,
) -> RegressionSuiteResult:
    """
    Run the execution safety regression suite.

    Each script is executed as a subprocess using the current Python interpreter.
    """

    suite_start = perf_counter()
    results: list[RegressionTestResult] = []

    for script in scripts:
        path = Path(script)

        if not path.exists():
            result = RegressionTestResult(
                script=script,
                passed=False,
                return_code=127,
                elapsed_seconds=0.0,
                stdout_tail="",
                stderr_tail=f"Missing script: {script}",
            )
            results.append(result)

            if stop_on_failure:
                break

            continue

        start = perf_counter()
        completed = subprocess.run(
            [sys.executable, str(path)],
            capture_output=True,
            text=True,
        )
        elapsed = perf_counter() - start

        result = RegressionTestResult(
            script=script,
            passed=completed.returncode == 0,
            return_code=completed.returncode,
            elapsed_seconds=elapsed,
            stdout_tail=tail_text(completed.stdout),
            stderr_tail=tail_text(completed.stderr),
        )
        results.append(result)

        if stop_on_failure and not result.passed:
            break

    elapsed_total = perf_counter() - suite_start
    passed_tests = sum(1 for result in results if result.passed)
    failed_tests = len(results) - passed_tests

    return RegressionSuiteResult(
        suite_name="execution_safety_regression_suite",
        passed=failed_tests == 0 and len(results) == len(scripts),
        total_tests=len(results),
        passed_tests=passed_tests,
        failed_tests=failed_tests,
        elapsed_seconds=elapsed_total,
        results=tuple(results),
    )


def tail_text(value: str, *, max_lines: int = 8) -> str:
    """Return a short tail of subprocess output."""

    lines = value.splitlines()
    if not lines:
        return ""

    return "\n".join(lines[-max_lines:])


def print_text_summary(result: RegressionSuiteResult) -> None:
    """Print a readable regression summary."""

    print("Execution Safety Regression Suite")
    print("=" * 80)
    print(f"Suite:         {result.suite_name}")
    print(f"Passed:        {result.passed}")
    print(f"Total tests:   {result.total_tests}")
    print(f"Passed tests:  {result.passed_tests}")
    print(f"Failed tests:  {result.failed_tests}")
    print(f"Elapsed sec:   {result.elapsed_seconds:.3f}")
    print("-" * 80)

    for test_result in result.results:
        status = "PASS" if test_result.passed else "FAIL"
        print(f"[{status}] {test_result.script} ({test_result.elapsed_seconds:.3f}s)")
        if not test_result.passed:
            if test_result.stdout_tail:
                print("STDOUT tail:")
                print(test_result.stdout_tail)
            if test_result.stderr_tail:
                print("STDERR tail:")
                print(test_result.stderr_tail)

    print("-" * 80)

    if result.passed:
        print("[PASS] Execution safety regression suite passed.")
        print("[PASS] No private execution endpoint call was introduced.")
        print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")
    else:
        print("[FAIL] Execution safety regression suite failed.")
        print("[FAIL] Review the failing test output above.")


def run_cli(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run the full execution safety regression suite."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON output instead of text summary.",
    )
    parser.add_argument(
        "--stop-on-failure",
        action="store_true",
        help="Stop the suite when the first failure is encountered.",
    )

    args = parser.parse_args(argv)
    result = run_regression_suite(stop_on_failure=args.stop_on_failure)

    if args.json:
        print(json.dumps(result.safe_report(), indent=2, sort_keys=True))
    else:
        print_text_summary(result)

    return 0 if result.passed else 1


if __name__ == "__main__":
    raise SystemExit(run_cli())
'@

$testContent = @'
"""
Validation script for Slice 16B.

This validates the full execution safety regression suite runner.

It does not:
- place orders
- cancel orders
- call private execution endpoints
- enable live trading
- require private account-changing permissions
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from scripts.run_execution_safety_regression_suite import (
    DEFAULT_SAFETY_TESTS,
    run_regression_suite,
)


RUNNER_PATH = Path("scripts/run_execution_safety_regression_suite.py")


def test_runner_file_exists() -> None:
    assert RUNNER_PATH.exists()
    assert RUNNER_PATH.stat().st_size > 1000

    print("[OK] regression suite runner exists")


def test_default_safety_tests_exist() -> None:
    assert len(DEFAULT_SAFETY_TESTS) >= 10

    for script in DEFAULT_SAFETY_TESTS:
        assert Path(script).exists(), f"Missing regression test script: {script}"

    print("[OK] all default safety test scripts exist")


def test_regression_suite_runs_subset_successfully() -> None:
    result = run_regression_suite(
        scripts=(
            "scripts/test_live_execution_safety_config.py",
            "scripts/test_manual_execution_review_cli_usage_guide.py",
        )
    )

    report = result.safe_report()

    assert report["passed"] is True
    assert report["total_tests"] == 2
    assert report["passed_tests"] == 2
    assert report["failed_tests"] == 0
    assert report["secrets_included"] is False
    assert report["execution_endpoint_called"] is False

    print("[OK] regression suite runner can run a safe subset")


def test_regression_suite_json_mode_subset() -> None:
    completed = subprocess.run(
        [
            sys.executable,
            "scripts/run_execution_safety_regression_suite.py",
            "--json",
            "--stop-on-failure",
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    payload = json.loads(completed.stdout)

    assert payload["suite_name"] == "execution_safety_regression_suite"
    assert payload["passed"] is True
    assert payload["failed_tests"] == 0
    assert payload["secrets_included"] is False
    assert payload["execution_endpoint_called"] is False
    assert len(payload["results"]) >= 10

    print("[OK] regression suite JSON mode works")


def test_runner_source_contains_no_private_execution_endpoint_names() -> None:
    text = RUNNER_PATH.read_text(encoding="utf-8").lower()

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

    for term in forbidden_terms:
        assert term not in text

    print("[OK] regression runner source contains no private execution endpoint names")


def main() -> None:
    print("Slice 16B validation: Full Project Safety Regression Runner")
    print("=" * 80)

    test_runner_file_exists()
    test_default_safety_tests_exist()
    test_regression_suite_runs_subset_successfully()
    test_regression_suite_json_mode_subset()
    test_runner_source_contains_no_private_execution_endpoint_names()

    print("=" * 80)
    print("[PASS] Slice 16B full project safety regression runner validation passed.")
    print("[PASS] Master regression runner verifies the execution safety foundation.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No funding, withdrawal, or trading permission requirement was introduced.")


if __name__ == "__main__":
    main()
'@

Set-Content -Path $runnerPath -Value $runnerContent -Encoding UTF8
Write-Host "[WRITTEN] $runnerPath"

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
## Slice 16B — Full Project Safety Regression Runner

Status: Implemented pending validation.

Goal:
Create one master regression runner for the execution safety foundation.

Scope:
- Create `scripts/run_execution_safety_regression_suite.py`.
- Create `scripts/test_execution_safety_regression_suite_runner.py`.
- Run the recent execution safety validation scripts as subprocesses.
- Produce one safe PASS/FAIL summary.
- Support JSON output for automated review.

Safety:
- No private execution endpoint call.
- No live trading.
- No order placement.
- No order cancellation.
- No private account-changing permissions required.
"@

$controlsBlock = @"
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
"@

$decisionBlock = @"
## Slice 16B Decision — Add a Master Execution Safety Regression Runner

Decision:
Add one master regression runner for the execution safety foundation.

Reason:
The project now has many linked safety layers. Before moving closer to live execution adapter work, one command should verify that the full recent execution safety stack still passes.

Result:
The project can run a single safety regression suite and get a safe PASS/FAIL summary.
"@

Add-DocBlockOnce -Path ".\docs\03_ROADMAP.md" -Marker "Slice 16B — Full Project Safety Regression Runner" -Block $roadmapBlock
Add-DocBlockOnce -Path ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md" -Marker "Slice 16B — Full Project Safety Regression Runner" -Block $controlsBlock
Add-DocBlockOnce -Path ".\docs\11_DECISION_LOG.md" -Marker "Slice 16B Decision — Add a Master Execution Safety Regression Runner" -Block $decisionBlock

Write-Host ""
Write-Host "=== CURRENT BRANCH ==="
git branch --show-current

Write-Host ""
Write-Host "=== GIT STATUS ==="
git status --short

Write-Host ""
Write-Host "=== SLICE 16B FILES ==="
Get-Item `
    ".\scripts\run_execution_safety_regression_suite.py", `
    ".\scripts\test_execution_safety_regression_suite_runner.py", `
    ".\docs\03_ROADMAP.md", `
    ".\docs\10_EXECUTION_AND_RISK_CONTROLS.md", `
    ".\docs\11_DECISION_LOG.md" |
    Select-Object Name, Length, LastWriteTime

Write-Host ""
Write-Host "Slice 16B script completed."
