Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-CheckedPython {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $Arguments
  )

  & python @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Python command failed with exit code ${LASTEXITCODE}: python $($Arguments -join ' ')"
  }
}

Write-Host "Slice 22C - Wire Disabled Signing Material Model into Signer Shell Review"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
  "tradingagents/execution/kraken_private_signing_material_model.py",
  "scripts/run_execution_safety_regression_suite.py",
  "scripts/test_execution_safety_regression_suite_runner.py",
  "docs/03_ROADMAP.md",
  "docs/10_EXECUTION_AND_RISK_CONTROLS.md",
  "docs/11_DECISION_LOG.md"
)

foreach ($File in $RequiredFiles) {
  if (-not (Test-Path -LiteralPath $File)) {
    throw "Required file not found: $File"
  }
}

$PythonPatch = @'
from pathlib import Path
import re

INTEGRATION_FILE = Path("tradingagents/execution/kraken_private_signing_material_review_integration.py")
TEST_FILE = Path("scripts/test_kraken_private_signing_material_review_integration.py")
SUITE_FILE = Path("scripts/run_execution_safety_regression_suite.py")
RUNNER_TEST_FILE = Path("scripts/test_execution_safety_regression_suite_runner.py")
DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")

NEW_TEST = "scripts/test_kraken_private_signing_material_review_integration.py"

INTEGRATION_SOURCE = "\"\"\"Disabled signing-material review integration for the Kraken signer shell.\n\nThis module attaches the disabled signing-material review payload to the signer\nshell review surface. It is intentionally data-only and blocked.\n\"\"\"\n\nfrom __future__ import annotations\n\nfrom dataclasses import asdict, is_dataclass\nimport inspect\nfrom typing import Any, Mapping\n\nfrom tradingagents.execution.kraken_private_signing_material_model import (\n    build_disabled_kraken_private_signing_material,\n)\n\n\n_SIGNER_SHELL_BUILDER_NAMES = (\n    \"build_disabled_kraken_private_request_signer_shell\",\n    \"build_disabled_kraken_private_request_signer\",\n    \"build_disabled_private_request_signer_shell\",\n    \"build_disabled_private_request_signer\",\n)\n\n\ndef _to_review_payload(value: Any) -> Mapping[str, object]:\n    if isinstance(value, Mapping):\n        return dict(value)\n\n    if hasattr(value, \"as_review_payload\"):\n        payload = value.as_review_payload()\n        if isinstance(payload, Mapping):\n            return dict(payload)\n\n    if is_dataclass(value):\n        return asdict(value)\n\n    return {\n        \"status\": \"disabled\",\n        \"review_object_type\": type(value).__name__,\n        \"review_object_repr\": repr(value),\n    }\n\n\ndef _build_signer_shell_review_snapshot() -> Mapping[str, object]:\n    from tradingagents.execution import kraken_private_request_signer_shell as signer_shell\n\n    for builder_name in _SIGNER_SHELL_BUILDER_NAMES:\n        builder = getattr(signer_shell, builder_name, None)\n        if builder is None or not callable(builder):\n            continue\n\n        signature = inspect.signature(builder)\n        required_parameters = [\n            parameter\n            for parameter in signature.parameters.values()\n            if parameter.default is inspect.Parameter.empty\n            and parameter.kind\n            in (\n                inspect.Parameter.POSITIONAL_ONLY,\n                inspect.Parameter.POSITIONAL_OR_KEYWORD,\n                inspect.Parameter.KEYWORD_ONLY,\n            )\n        ]\n\n        if required_parameters:\n            continue\n\n        return _to_review_payload(builder())\n\n    return {\n        \"status\": \"disabled\",\n        \"review_object_type\": \"kraken_private_request_signer_shell\",\n        \"review_object_repr\": \"No zero-argument signer shell builder was available.\",\n    }\n\n\ndef build_disabled_signer_shell_review_with_signing_material(\n    signer_review: Mapping[str, object] | None = None,\n) -> Mapping[str, object]:\n    \"\"\"Return a disabled review payload with signing material attached.\"\"\"\n\n    base_review = dict(signer_review or _build_signer_shell_review_snapshot())\n    signing_material = build_disabled_kraken_private_signing_material().as_review_payload()\n\n    return {\n        \"status\": \"disabled\",\n        \"signer_shell_review\": base_review,\n        \"signing_material_review\": dict(signing_material),\n        \"can_read_api_secret\": False,\n        \"can_read_environment_secret\": False,\n        \"can_generate_nonce\": False,\n        \"can_generate_signature\": False,\n        \"can_call_private_endpoint\": False,\n        \"required_permissions\": [],\n    }\n"
TEST_SOURCE = "\"\"\"Slice 22C validation: disabled signing material wired to signer review.\"\"\"\n\nfrom __future__ import annotations\n\nfrom pathlib import Path\nimport sys\n\nREPO_ROOT = Path(__file__).resolve().parents[1]\nif str(REPO_ROOT) not in sys.path:\n    sys.path.insert(0, str(REPO_ROOT))\n\nfrom tradingagents.execution.kraken_private_signing_material_review_integration import (\n    build_disabled_signer_shell_review_with_signing_material,\n)\n\n\nFORBIDDEN_SOURCE_TOKENS = [\n    \"os.environ\",\n    \"getenv\",\n    \"hmac\",\n    \"hashlib\",\n    \"base64\",\n    \"urlopen\",\n    \"requests.\",\n    \"urllib.request\",\n    \"AddOrder\",\n    \"CancelOrder\",\n    \"Withdraw\",\n    \"Deposit\",\n]\n\n\ndef test_review_integration_attaches_disabled_signing_material() -> None:\n    review = build_disabled_signer_shell_review_with_signing_material(\n        signer_review={\n            \"status\": \"disabled\",\n            \"source\": \"test signer review\",\n            \"can_call_private_endpoint\": False,\n        }\n    )\n\n    assert review[\"status\"] == \"disabled\"\n    assert review[\"can_read_api_secret\"] is False\n    assert review[\"can_read_environment_secret\"] is False\n    assert review[\"can_generate_nonce\"] is False\n    assert review[\"can_generate_signature\"] is False\n    assert review[\"can_call_private_endpoint\"] is False\n    assert review[\"required_permissions\"] == []\n\n    assert review[\"signer_shell_review\"][\"status\"] == \"disabled\"\n    assert review[\"signing_material_review\"][\"exchange\"] == \"kraken\"\n    assert review[\"signing_material_review\"][\"status\"] == \"disabled\"\n    assert review[\"signing_material_review\"][\"can_read_api_secret\"] is False\n    assert review[\"signing_material_review\"][\"can_read_environment_secret\"] is False\n    assert review[\"signing_material_review\"][\"can_generate_nonce\"] is False\n    assert review[\"signing_material_review\"][\"can_generate_signature\"] is False\n    assert review[\"signing_material_review\"][\"can_call_private_endpoint\"] is False\n\n\ndef test_review_integration_can_build_from_current_signer_shell() -> None:\n    review = build_disabled_signer_shell_review_with_signing_material()\n\n    assert review[\"status\"] == \"disabled\"\n    assert \"signer_shell_review\" in review\n    assert \"signing_material_review\" in review\n    assert review[\"signing_material_review\"][\"status\"] == \"disabled\"\n    assert review[\"can_call_private_endpoint\"] is False\n\n\ndef test_review_integration_source_contains_no_secret_signing_or_network_implementation() -> None:\n    source_path = (\n        REPO_ROOT\n        / \"tradingagents\"\n        / \"execution\"\n        / \"kraken_private_signing_material_review_integration.py\"\n    )\n    source = source_path.read_text(encoding=\"utf-8\")\n\n    for forbidden in FORBIDDEN_SOURCE_TOKENS:\n        assert forbidden not in source\n\n    assert \"build_disabled_kraken_private_signing_material\" in source\n    assert \"can_generate_nonce\" in source\n    assert \"can_generate_signature\" in source\n    assert \"can_call_private_endpoint\" in source\n\n\ndef main() -> None:\n    print(\"Slice 22C validation: Disabled Signing Material + Signer Shell Review Integration\")\n    print(\"=\" * 80)\n\n    test_review_integration_attaches_disabled_signing_material()\n    print(\"[OK] disabled signing material attaches to explicit signer review\")\n\n    test_review_integration_can_build_from_current_signer_shell()\n    print(\"[OK] disabled signing material attaches to current signer shell review path\")\n\n    test_review_integration_source_contains_no_secret_signing_or_network_implementation()\n    print(\"[OK] integration source contains no secret, signing, or network implementation\")\n\n    print(\"=\" * 80)\n    print(\"[PASS] Slice 22C disabled signing material review integration validation passed.\")\n    print(\"[PASS] No API secret reading was introduced.\")\n    print(\"[PASS] No environment secret reading was introduced.\")\n    print(\"[PASS] No nonce generation was introduced.\")\n    print(\"[PASS] No HMAC/hashlib/base64 signing implementation was introduced.\")\n    print(\"[PASS] No private execution endpoint call was introduced.\")\n    print(\"[PASS] No private account-changing permission requirement was introduced.\")\n\n\nif __name__ == \"__main__\":\n    main()\n"
ROADMAP_BLOCK = "\n### Slice 22C - Wire Disabled Signing Material Model into Signer Shell Review\n\nValidated target:\n- Add a disabled signing-material review integration layer.\n- Attach the disabled signing-material payload to the private request signer shell review surface.\n- Add standalone validation for the disabled review integration.\n- Register the standalone validation in the master execution safety regression suite.\n- Increase expected master safety suite coverage from 27 tests to 28 tests.\n\nSafety posture:\n- No real order placement.\n- No real order cancellation.\n- No private endpoint calls.\n- No network calls in private execution code.\n- No API secret usage.\n- No environment secret reading.\n- No nonce generation.\n- No HMAC/hashlib/base64 signing implementation.\n- No live trading.\n- No private account-changing permission requirement.\n"
CONTROLS_BLOCK = "\n### Slice 22C control - disabled signing material wired into signer shell review\n\nThe disabled signing-material model is now attached to the signer shell review surface through a data-only review integration layer.\n\nThis slice does not activate private execution, does not read API secrets, does not read environment secrets, does not generate nonces, does not generate signatures, and does not introduce private endpoint or network calls.\n"
DECISIONS_BLOCK = "\n### Slice 22C decision - wire disabled signing material into review flow before real signing\n\nDecision:\n- Wire the disabled signing-material model into a signer-shell review integration layer.\n\nReason:\n- Signing-related state should become visible in review output before any sensitive behavior exists.\n- This preserves auditability and allows tests to lock the disabled posture before future implementation slices.\n\nExpected result:\n- Master safety suite increases from 27 tests to 28 tests.\n- All 28 tests remain passing.\n- Safety guards continue to confirm that no secret reading, nonce generation, signing implementation, private endpoint call, or account-changing permission requirement was introduced.\n"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\ufeff", "")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\ufeff", ""), encoding="utf-8", newline="\n")


def insert_test_path_after_anchor(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_private_signing_material_model.py",
        "scripts/test_kraken_private_signer_transport_integration.py",
        "scripts/test_kraken_private_request_signer_shell.py",
    ]

    for anchor in anchors:
        if anchor not in text:
            continue

        lines = text.splitlines()
        out = []
        inserted = False

        for line in lines:
            out.append(line)
            if (not inserted) and anchor in line:
                indent = line[: len(line) - len(line.lstrip())]
                quote = '"' if '"' in line else "'"
                comma = "," if line.rstrip().endswith(",") else ""
                out.append(f"{indent}{quote}{new_test}{quote}{comma}")
                inserted = True

        if inserted:
            return "\n".join(out) + "\n"

    raise RuntimeError(f"Could not find suite anchor to insert {new_test}")


def update_expected_counts(text: str) -> str:
    replacements = [
        (r"(EXPECTED_TEST_COUNT\s*=\s*)27\b", r"\g<1>28"),
        (r"(expected_test_count\s*=\s*)27\b", r"\g<1>28"),
        (r"(EXPECTED_TOTAL_TESTS\s*=\s*)27\b", r"\g<1>28"),
        (r"(expected_total_tests\s*=\s*)27\b", r"\g<1>28"),
        (r"(TOTAL_TESTS\s*=\s*)27\b", r"\g<1>28"),
        (r"(total_tests\s*=\s*)27\b", r"\g<1>28"),
        (r"(assert\s+len\([^)]+\)\s*==\s*)27\b", r"\g<1>28"),
        (r"(assert\s+[^=\n]+\.total_tests\s*==\s*)27\b", r"\g<1>28"),
        (r"(Total tests:\s*)27\b", r"\g<1>28"),
        (r"(Passed tests:\s*)27\b", r"\g<1>28"),
        (r"(Passed:\s*)27\b", r"\g<1>28"),
    ]

    updated = text
    for pattern, repl in replacements:
        updated = re.sub(pattern, repl, updated)

    return updated


def insert_test_path_in_runner_test(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_private_signing_material_model.py",
        "scripts/test_kraken_private_signer_transport_integration.py",
        "scripts/test_kraken_private_request_signer_shell.py",
    ]

    for anchor in anchors:
        if anchor not in text:
            continue

        lines = text.splitlines()
        out = []
        inserted = False

        for line in lines:
            out.append(line)
            if (not inserted) and anchor in line:
                indent = line[: len(line) - len(line.lstrip())]
                quote = '"' if '"' in line else "'"
                comma = "," if line.rstrip().endswith(",") else ""
                out.append(f"{indent}{quote}{new_test}{quote}{comma}")
                inserted = True

        if inserted:
            return "\n".join(out) + "\n"

    return text


def append_once(path: Path, marker: str, block: str) -> None:
    text = read(path)
    if marker in text:
        return

    if text and not text.endswith("\n"):
        text += "\n"

    text += "\n" + block.strip() + "\n"
    write(path, text)


write(INTEGRATION_FILE, INTEGRATION_SOURCE)
write(TEST_FILE, TEST_SOURCE)

suite_text = read(SUITE_FILE)
suite_text = insert_test_path_after_anchor(suite_text, NEW_TEST)
write(SUITE_FILE, suite_text)

runner_text = read(RUNNER_TEST_FILE)
runner_text = update_expected_counts(runner_text)
runner_text = insert_test_path_in_runner_test(runner_text, NEW_TEST)
write(RUNNER_TEST_FILE, runner_text)

append_once(DOC_ROADMAP, "Slice 22C - Wire Disabled Signing Material Model into Signer Shell Review", ROADMAP_BLOCK)
append_once(DOC_CONTROLS, "Slice 22C control - disabled signing material wired into signer shell review", CONTROLS_BLOCK)
append_once(DOC_DECISIONS, "Slice 22C decision - wire disabled signing material into review flow before real signing", DECISIONS_BLOCK)

print("[PASS] Slice 22C patch applied.")
print("[PASS] Disabled signing-material review integration added.")
print("[PASS] Standalone validation added.")
print("[PASS] Master safety suite updated to include the new validation.")
print("[PASS] Roadmap, controls, and decision log updated.")

'@

$TempPatch = Join-Path $env:TEMP "apply_slice_22c_patch.py"
Set-Content -LiteralPath $TempPatch -Value $PythonPatch -Encoding UTF8

try {
  Invoke-CheckedPython -Arguments @($TempPatch)
}
finally {
  if (Test-Path -LiteralPath $TempPatch) {
    Remove-Item -LiteralPath $TempPatch -Force
  }
}

Write-Host ""
Write-Host "Running Slice 22C validation..."
Invoke-CheckedPython -Arguments @(".\scripts\test_kraken_private_signing_material_review_integration.py")
Invoke-CheckedPython -Arguments @(".\scripts\test_execution_safety_regression_suite_runner.py")
Invoke-CheckedPython -Arguments @(".\scripts\run_execution_safety_regression_suite.py")

Write-Host ""
Write-Host "Checking working tree..."
git status --short
if ($LASTEXITCODE -ne 0) {
  throw "git status failed with exit code ${LASTEXITCODE}"
}

Write-Host ""
Write-Host "[PASS] Slice 22C creation and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Wire disabled signing material into signer review"
Read-Host "Press Enter to close..."
