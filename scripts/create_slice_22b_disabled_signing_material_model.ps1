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

Write-Host "Slice 22B - Add Disabled Private Request Signing Material Model"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
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

MODEL_FILE = Path("tradingagents/execution/kraken_private_signing_material_model.py")
TEST_FILE = Path("scripts/test_kraken_private_signing_material_model.py")
SUITE_FILE = Path("scripts/run_execution_safety_regression_suite.py")
RUNNER_TEST_FILE = Path("scripts/test_execution_safety_regression_suite_runner.py")
DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")

NEW_TEST = "scripts/test_kraken_private_signing_material_model.py"

MODEL_SOURCE = "\"\"\"Disabled Kraken private signing material model.\n\nThis module intentionally defines data-only structures for future private request\nsigning workflows. It does not read secrets, generate nonces, build signatures,\nor call private/network endpoints.\n\"\"\"\n\nfrom __future__ import annotations\n\nfrom dataclasses import dataclass\nfrom typing import Mapping, Tuple\n\n\n_DISABLED_REASON = (\n    \"Private request signing material is data-only and disabled. \"\n    \"No API secret reading, nonce generation, or signature generation is available.\"\n)\n\n\n@dataclass(frozen=True)\nclass DisabledKrakenPrivateSigningMaterial:\n    \"\"\"Data-only description of disabled future signing material.\n\n    The fields deliberately describe availability and required capabilities\n    without storing API keys, API secrets, nonces, or generated signatures.\n    \"\"\"\n\n    exchange: str = \"kraken\"\n    status: str = \"disabled\"\n    can_read_api_secret: bool = False\n    can_read_environment_secret: bool = False\n    can_generate_nonce: bool = False\n    can_generate_signature: bool = False\n    can_call_private_endpoint: bool = False\n    required_permissions: Tuple[str, ...] = ()\n\n    @property\n    def disabled_reason(self) -> str:\n        return _DISABLED_REASON\n\n    def as_review_payload(self) -> Mapping[str, object]:\n        \"\"\"Return an inert review payload with no sensitive material.\"\"\"\n\n        return {\n            \"exchange\": self.exchange,\n            \"status\": self.status,\n            \"can_read_api_secret\": self.can_read_api_secret,\n            \"can_read_environment_secret\": self.can_read_environment_secret,\n            \"can_generate_nonce\": self.can_generate_nonce,\n            \"can_generate_signature\": self.can_generate_signature,\n            \"can_call_private_endpoint\": self.can_call_private_endpoint,\n            \"required_permissions\": list(self.required_permissions),\n            \"disabled_reason\": self.disabled_reason,\n        }\n\n\ndef build_disabled_kraken_private_signing_material() -> DisabledKrakenPrivateSigningMaterial:\n    \"\"\"Build the disabled, data-only signing material model.\"\"\"\n\n    return DisabledKrakenPrivateSigningMaterial()\n"
TEST_SOURCE = "\"\"\"Slice 22B validation: disabled Kraken private signing material model.\"\"\"\n\nfrom __future__ import annotations\n\nfrom pathlib import Path\nimport sys\n\nREPO_ROOT = Path(__file__).resolve().parents[1]\nif str(REPO_ROOT) not in sys.path:\n    sys.path.insert(0, str(REPO_ROOT))\n\nfrom tradingagents.execution.kraken_private_signing_material_model import (\n    DisabledKrakenPrivateSigningMaterial,\n    build_disabled_kraken_private_signing_material,\n)\n\n\nFORBIDDEN_SOURCE_TOKENS = [\n    \"os.environ\",\n    \"getenv\",\n    \"hmac\",\n    \"hashlib\",\n    \"base64\",\n    \"urlopen\",\n    \"requests.\",\n    \"urllib.request\",\n    \"AddOrder\",\n    \"CancelOrder\",\n    \"Withdraw\",\n    \"Deposit\",\n]\n\n\ndef test_signing_material_is_disabled_and_data_only() -> None:\n    material = build_disabled_kraken_private_signing_material()\n\n    assert isinstance(material, DisabledKrakenPrivateSigningMaterial)\n    assert material.exchange == \"kraken\"\n    assert material.status == \"disabled\"\n    assert material.can_read_api_secret is False\n    assert material.can_read_environment_secret is False\n    assert material.can_generate_nonce is False\n    assert material.can_generate_signature is False\n    assert material.can_call_private_endpoint is False\n    assert material.required_permissions == ()\n    assert \"disabled\" in material.disabled_reason.lower()\n\n\ndef test_review_payload_contains_no_sensitive_or_executable_material() -> None:\n    payload = build_disabled_kraken_private_signing_material().as_review_payload()\n\n    assert payload[\"exchange\"] == \"kraken\"\n    assert payload[\"status\"] == \"disabled\"\n    assert payload[\"can_read_api_secret\"] is False\n    assert payload[\"can_read_environment_secret\"] is False\n    assert payload[\"can_generate_nonce\"] is False\n    assert payload[\"can_generate_signature\"] is False\n    assert payload[\"can_call_private_endpoint\"] is False\n    assert payload[\"required_permissions\"] == []\n\n    serialized = repr(payload).lower()\n    assert \"secret\" in serialized\n    assert \"api_key\" not in serialized\n    assert \"private_key\" not in serialized\n    assert \"signature_value\" not in serialized\n\n\ndef test_model_source_contains_no_secret_signing_or_network_implementation() -> None:\n    source_path = REPO_ROOT / \"tradingagents\" / \"execution\" / \"kraken_private_signing_material_model.py\"\n    source = source_path.read_text(encoding=\"utf-8\")\n\n    for forbidden in FORBIDDEN_SOURCE_TOKENS:\n        assert forbidden not in source\n\n    assert \"nonce\" in source\n    assert \"signature\" in source\n    assert \"can_generate_nonce: bool = False\" in source\n    assert \"can_generate_signature: bool = False\" in source\n    assert \"can_call_private_endpoint: bool = False\" in source\n\n\ndef main() -> None:\n    print(\"Slice 22B validation: Disabled Kraken Private Signing Material Model\")\n    print(\"=\" * 80)\n\n    test_signing_material_is_disabled_and_data_only()\n    print(\"[OK] signing material model is disabled and data-only\")\n\n    test_review_payload_contains_no_sensitive_or_executable_material()\n    print(\"[OK] review payload contains no sensitive or executable material\")\n\n    test_model_source_contains_no_secret_signing_or_network_implementation()\n    print(\"[OK] model source contains no secret, signing, or network implementation\")\n\n    print(\"=\" * 80)\n    print(\"[PASS] Slice 22B disabled signing material model validation passed.\")\n    print(\"[PASS] No API secret reading was introduced.\")\n    print(\"[PASS] No environment secret reading was introduced.\")\n    print(\"[PASS] No nonce generation was introduced.\")\n    print(\"[PASS] No HMAC/hashlib/base64 signing implementation was introduced.\")\n    print(\"[PASS] No private execution endpoint call was introduced.\")\n    print(\"[PASS] No private account-changing permission requirement was introduced.\")\n\n\nif __name__ == \"__main__\":\n    main()\n"
ROADMAP_BLOCK = "\n### Slice 22B - Add Disabled Private Request Signing Material Model\n\nValidated target:\n- Add a disabled, data-only Kraken private signing material model.\n- Add standalone validation for the disabled model.\n- Register the standalone validation in the master execution safety regression suite.\n- Increase expected master safety suite coverage from 26 tests to 27 tests.\n\nSafety posture:\n- No real order placement.\n- No real order cancellation.\n- No private endpoint calls.\n- No network calls in private execution code.\n- No API secret usage.\n- No environment secret reading.\n- No nonce generation.\n- No HMAC/hashlib/base64 signing implementation.\n- No live trading.\n- No private account-changing permission requirement.\n"
CONTROLS_BLOCK = "\n### Slice 22B control - disabled private signing material model\n\nA disabled, data-only Kraken private signing material model now exists for future review plumbing. It records that signing-related capabilities remain unavailable and blocked.\n\nThis slice does not activate private execution, does not read API secrets, does not read environment secrets, does not generate nonces, does not generate signatures, and does not introduce private endpoint or network calls.\n"
DECISIONS_BLOCK = "\n### Slice 22B decision - represent future signing material as disabled data only\n\nDecision:\n- Add an inert signing material model before any real signing implementation.\n\nReason:\n- Future private signing work needs explicit reviewable structure.\n- The first step should be data-only and disabled so safety tests can lock down the non-executable posture before any sensitive behavior exists.\n\nExpected result:\n- Master safety suite increases from 26 tests to 27 tests.\n- All 27 tests remain passing.\n- Safety guards continue to confirm that no secret reading, nonce generation, signing implementation, private endpoint call, or account-changing permission requirement was introduced.\n"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\ufeff", "")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\ufeff", ""), encoding="utf-8", newline="\n")


def insert_test_path_after_anchor(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_private_signer_transport_integration.py",
        "scripts/test_kraken_private_request_signer_shell.py",
        "scripts/test_kraken_private_client_transport_integration.py",
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
        (r"(EXPECTED_TEST_COUNT\s*=\s*)26\b", r"\g<1>27"),
        (r"(expected_test_count\s*=\s*)26\b", r"\g<1>27"),
        (r"(EXPECTED_TOTAL_TESTS\s*=\s*)26\b", r"\g<1>27"),
        (r"(expected_total_tests\s*=\s*)26\b", r"\g<1>27"),
        (r"(TOTAL_TESTS\s*=\s*)26\b", r"\g<1>27"),
        (r"(total_tests\s*=\s*)26\b", r"\g<1>27"),
        (r"(assert\s+len\([^)]+\)\s*==\s*)26\b", r"\g<1>27"),
        (r"(assert\s+[^=\n]+\.total_tests\s*==\s*)26\b", r"\g<1>27"),
        (r"(Total tests:\s*)26\b", r"\g<1>27"),
        (r"(Passed tests:\s*)26\b", r"\g<1>27"),
        (r"(Passed:\s*)26\b", r"\g<1>27"),
    ]

    updated = text
    for pattern, repl in replacements:
        updated = re.sub(pattern, repl, updated)

    return updated


def insert_test_path_in_runner_test(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_private_signer_transport_integration.py",
        "scripts/test_kraken_private_request_signer_shell.py",
        "scripts/test_kraken_private_client_transport_integration.py",
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


write(MODEL_FILE, MODEL_SOURCE)
write(TEST_FILE, TEST_SOURCE)

suite_text = read(SUITE_FILE)
suite_text = insert_test_path_after_anchor(suite_text, NEW_TEST)
write(SUITE_FILE, suite_text)

runner_text = read(RUNNER_TEST_FILE)
runner_text = update_expected_counts(runner_text)
runner_text = insert_test_path_in_runner_test(runner_text, NEW_TEST)
write(RUNNER_TEST_FILE, runner_text)

append_once(DOC_ROADMAP, "Slice 22B - Add Disabled Private Request Signing Material Model", ROADMAP_BLOCK)
append_once(DOC_CONTROLS, "Slice 22B control - disabled private signing material model", CONTROLS_BLOCK)
append_once(DOC_DECISIONS, "Slice 22B decision - represent future signing material as disabled data only", DECISIONS_BLOCK)

print("[PASS] Slice 22B patch applied.")
print("[PASS] Disabled signing material model added.")
print("[PASS] Standalone validation added.")
print("[PASS] Master safety suite updated to include the new validation.")
print("[PASS] Roadmap, controls, and decision log updated.")

'@

$TempPatch = Join-Path $env:TEMP "apply_slice_22b_patch.py"
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
Write-Host "Running Slice 22B validation..."
Invoke-CheckedPython -Arguments @(".\scripts\test_kraken_private_signing_material_model.py")
Invoke-CheckedPython -Arguments @(".\scripts\test_execution_safety_regression_suite_runner.py")
Invoke-CheckedPython -Arguments @(".\scripts\run_execution_safety_regression_suite.py")

Write-Host ""
Write-Host "Checking working tree..."
git status --short
if ($LASTEXITCODE -ne 0) {
  throw "git status failed with exit code ${LASTEXITCODE}"
}

Write-Host ""
Write-Host "[PASS] Slice 22B creation and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Add disabled private signing material model"
Read-Host "Press Enter to close..."
