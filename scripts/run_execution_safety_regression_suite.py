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
    "scripts/test_execution_adapter_interface.py",
    "scripts/test_execution_adapter_command_integration.py",
    "scripts/test_live_execution_activation_policy.py",
    "scripts/test_kraken_live_adapter_skeleton.py",
    "scripts/test_kraken_private_order_request_translator.py",
    "scripts/test_kraken_order_translation_adapter_integration.py",
    "scripts/test_kraken_order_payload_review_cli.py",
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
        print("[PASS] No private account-changing permission requirement was introduced.")
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







