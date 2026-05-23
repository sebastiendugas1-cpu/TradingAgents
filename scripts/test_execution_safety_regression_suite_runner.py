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

import importlib.util
import sys

_RUNNER_PATH = Path("scripts/run_execution_safety_regression_suite.py")
_SPEC = importlib.util.spec_from_file_location("run_execution_safety_regression_suite", _RUNNER_PATH)

if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("Could not load regression suite runner module.")

_RUNNER_MODULE = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _RUNNER_MODULE
_SPEC.loader.exec_module(_RUNNER_MODULE)

DEFAULT_SAFETY_TESTS = _RUNNER_MODULE.DEFAULT_SAFETY_TESTS
run_regression_suite = _RUNNER_MODULE.run_regression_suite


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

