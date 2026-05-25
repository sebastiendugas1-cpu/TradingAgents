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

# Ensure this script can import the local package when it is run directly from
# the repository root or through a subprocess without PYTHONPATH preconfigured.
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import json
import subprocess
import importlib.util
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
    assert len(DEFAULT_SAFETY_TESTS) >= 25
    for script in DEFAULT_SAFETY_TESTS:
        assert Path(script).exists(), f"Missing regression test script: {script}"
    print("[OK] all default safety test scripts exist")
def test_default_safety_tests_include_private_request_signer_shell_test() -> None:
    assert "scripts/test_kraken_private_request_signer_shell.py" in DEFAULT_SAFETY_TESTS
    "scripts/test_kraken_private_signer_transport_integration.py"
    "scripts/test_kraken_private_signing_material_model.py"
    print("[OK] default safety tests include private request signer shell test")
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
