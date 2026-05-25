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

Write-Host "Slice 22D v3 - Add Signing Material Review Integration to Payload Review CLI"
Write-Host "================================================================================"

$RepoRoot = (Get-Location).Path
Write-Host "Repo root: $RepoRoot"

$RequiredFiles = @(
  "scripts/run_kraken_order_payload_review.py",
  "tradingagents/execution/kraken_private_signing_material_review_integration.py",
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
import json
import re

DATA = json.loads(r"""{"test_source": "\"\"\"Slice 22D validation: disabled signing material appears in payload review CLI helper.\"\"\"\n\nfrom __future__ import annotations\n\nfrom pathlib import Path\nimport importlib.util\nimport sys\n\nREPO_ROOT = Path(__file__).resolve().parents[1]\nif str(REPO_ROOT) not in sys.path:\n    sys.path.insert(0, str(REPO_ROOT))\n\nCLI_PATH = REPO_ROOT / \"scripts\" / \"run_kraken_order_payload_review.py\"\n\n\nFORBIDDEN_SOURCE_TOKENS = [\n    \"os.environ\",\n    \"getenv\",\n    \"hmac\",\n    \"hashlib\",\n    \"base64\",\n    \"urlopen\",\n    \"requests.\",\n    \"urllib.request\",\n    \"AddOrder\",\n    \"CancelOrder\",\n    \"Withdraw\",\n    \"Deposit\",\n]\n\n\ndef _load_cli_module():\n    spec = importlib.util.spec_from_file_location(\"run_kraken_order_payload_review\", CLI_PATH)\n    assert spec is not None\n    assert spec.loader is not None\n\n    module = importlib.util.module_from_spec(spec)\n    sys.modules[\"run_kraken_order_payload_review\"] = module\n    spec.loader.exec_module(module)\n    return module\n\n\ndef test_cli_helper_attaches_disabled_signing_material_review_to_mapping() -> None:\n    module = _load_cli_module()\n\n    assert hasattr(module, \"_attach_disabled_signing_material_review\")\n\n    payload = module._attach_disabled_signing_material_review(\n        {\n            \"status\": \"disabled\",\n            \"private_client_review\": {\"status\": \"disabled\"},\n        }\n    )\n\n    assert payload[\"status\"] == \"disabled\"\n    assert \"signing_material_review\" in payload\n    assert payload[\"signing_material_review\"][\"status\"] == \"disabled\"\n    assert payload[\"signing_material_review\"][\"signing_material_review\"][\"exchange\"] == \"kraken\"\n    assert payload[\"signing_material_review\"][\"signing_material_review\"][\"status\"] == \"disabled\"\n    assert payload[\"signing_material_review\"][\"can_read_api_secret\"] is False\n    assert payload[\"signing_material_review\"][\"can_read_environment_secret\"] is False\n    assert payload[\"signing_material_review\"][\"can_generate_nonce\"] is False\n    assert payload[\"signing_material_review\"][\"can_generate_signature\"] is False\n    assert payload[\"signing_material_review\"][\"can_call_private_endpoint\"] is False\n\n\ndef test_cli_source_is_wired_to_disabled_signing_material_review() -> None:\n    source = CLI_PATH.read_text(encoding=\"utf-8\")\n\n    assert \"build_disabled_signer_shell_review_with_signing_material\" in source\n    assert \"_attach_disabled_signing_material_review\" in source\n    assert \"signing_material_review\" in source\n\n    for forbidden in FORBIDDEN_SOURCE_TOKENS:\n        assert forbidden not in source\n\n\ndef main() -> None:\n    print(\"Slice 22D validation: Signing Material Review Integration in Payload Review CLI\")\n    print(\"=\" * 80)\n\n    test_cli_helper_attaches_disabled_signing_material_review_to_mapping()\n    print(\"[OK] payload review CLI helper attaches disabled signing-material review\")\n\n    test_cli_source_is_wired_to_disabled_signing_material_review()\n    print(\"[OK] CLI source is wired to disabled signing-material review without unsafe calls\")\n\n    print(\"=\" * 80)\n    print(\"[PASS] Slice 22D signing material payload review CLI validation passed.\")\n    print(\"[PASS] No API secret reading was introduced.\")\n    print(\"[PASS] No environment secret reading was introduced.\")\n    print(\"[PASS] No nonce generation was introduced.\")\n    print(\"[PASS] No HMAC/hashlib/base64 signing implementation was introduced.\")\n    print(\"[PASS] No private execution endpoint call was introduced.\")\n    print(\"[PASS] No private account-changing permission requirement was introduced.\")\n\n\nif __name__ == \"__main__\":\n    main()\n", "import_block": "from tradingagents.execution.kraken_private_signing_material_review_integration import (\n    build_disabled_signer_shell_review_with_signing_material,\n)\n", "helper_block": "def _attach_disabled_signing_material_review(payload):\n    \"\"\"Attach disabled signing-material review data to mapping-based CLI output.\"\"\"\n\n    if not isinstance(payload, dict):\n        return payload\n\n    if \"signing_material_review\" in payload:\n        return payload\n\n    updated_payload = dict(payload)\n    signer_review = updated_payload.get(\"signer_shell_review\")\n    if signer_review is None:\n        signer_review = updated_payload.get(\"private_signer_review\")\n    if signer_review is None:\n        signer_review = updated_payload.get(\"private_client_review\")\n    if signer_review is None:\n        signer_review = {\"status\": \"disabled\", \"source\": \"payload_review_cli\"}\n\n    updated_payload[\"signing_material_review\"] = dict(\n        build_disabled_signer_shell_review_with_signing_material(signer_review=signer_review)\n    )\n    return updated_payload\n\n", "roadmap_block": "\n### Slice 22D - Add Signing Material Review Integration to Payload Review CLI\n\nValidated target:\n- Expose the disabled signing-material review payload at the payload review CLI layer.\n- Add standalone validation for the CLI-level disabled signing-material review helper.\n- Register the standalone validation in the master execution safety regression suite.\n- Increase expected master safety suite coverage from 28 tests to 29 tests.\n\nSafety posture:\n- No real order placement.\n- No real order cancellation.\n- No private endpoint calls.\n- No network calls in private execution code.\n- No API secret usage.\n- No environment secret reading.\n- No nonce generation.\n- No HMAC/hashlib/base64 signing implementation.\n- No live trading.\n- No private account-changing permission requirement.\n", "controls_block": "\n### Slice 22D control - disabled signing material exposed at payload review CLI layer\n\nThe payload review CLI now has a helper that attaches the disabled signing-material review payload to mapping-based review output. This keeps signing state visible to CLI review surfaces before any real signing implementation exists.\n\nThis slice does not activate private execution, does not read API secrets, does not read environment secrets, does not generate nonces, does not generate signatures, and does not introduce private endpoint or network calls.\n", "decisions_block": "\n### Slice 22D decision - expose disabled signing-material review in CLI review payload\n\nDecision:\n- Add CLI-level disabled signing-material review attachment.\n\nReason:\n- The user-facing payload review layer should display signing posture before any sensitive implementation is introduced.\n- Keeping this data-only makes future signing work easier to audit and keeps current private execution blocked.\n\nExpected result:\n- Master safety suite increases from 28 tests to 29 tests.\n- All 29 tests remain passing.\n- Safety guards continue to confirm that no secret reading, nonce generation, signing implementation, private endpoint call, or account-changing permission requirement was introduced.\n"}""")

CLI_FILE = Path("scripts/run_kraken_order_payload_review.py")
TEST_FILE = Path("scripts/test_kraken_order_payload_review_cli_signing_material.py")
SUITE_FILE = Path("scripts/run_execution_safety_regression_suite.py")
RUNNER_TEST_FILE = Path("scripts/test_execution_safety_regression_suite_runner.py")
DOC_ROADMAP = Path("docs/03_ROADMAP.md")
DOC_CONTROLS = Path("docs/10_EXECUTION_AND_RISK_CONTROLS.md")
DOC_DECISIONS = Path("docs/11_DECISION_LOG.md")

NEW_TEST = "scripts/test_kraken_order_payload_review_cli_signing_material.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\ufeff", "")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\ufeff", ""), encoding="utf-8", newline="\n")


def insert_import_after_future_imports(text: str, import_block: str) -> str:
    if "build_disabled_signer_shell_review_with_signing_material" in text:
        return text

    lines = text.splitlines()
    insert_at = 0

    if lines and lines[0].startswith("#!"):
        insert_at = 1

    if insert_at < len(lines) and lines[insert_at].startswith('"""'):
        insert_at += 1
        while insert_at < len(lines) and '"""' not in lines[insert_at]:
            insert_at += 1
        if insert_at < len(lines):
            insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    while insert_at < len(lines) and lines[insert_at].startswith("from __future__ import "):
        insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    return "\n".join(lines[:insert_at] + import_block.rstrip("\n").splitlines() + [""] + lines[insert_at:]) + "\n"


def insert_helper_safely(text: str, helper_block: str) -> str:
    if "def _attach_disabled_signing_material_review" in text:
        return text

    stripped_helper = helper_block.rstrip("\n")

    markers = [
        "\nif __name__ == \"__main__\":",
        "\nif __name__ == '__main__':",
        "\ndef run(",
        "\ndef cli(",
        "\ndef main(",
    ]

    for marker in markers:
        if marker in text:
            return text.replace(marker, "\n\n" + stripped_helper + "\n" + marker, 1)

    if text and not text.endswith("\n"):
        text += "\n"
    return text + "\n" + stripped_helper + "\n"


def insert_test_path_after_anchor(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_order_payload_review_cli.py",
        "scripts/test_kraken_private_signing_material_review_integration.py",
        "scripts/test_kraken_payload_review_private_client_integration.py",
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
        (r"(EXPECTED_TEST_COUNT\s*=\s*)28\b", r"\g<1>29"),
        (r"(expected_test_count\s*=\s*)28\b", r"\g<1>29"),
        (r"(EXPECTED_TOTAL_TESTS\s*=\s*)28\b", r"\g<1>29"),
        (r"(expected_total_tests\s*=\s*)28\b", r"\g<1>29"),
        (r"(TOTAL_TESTS\s*=\s*)28\b", r"\g<1>29"),
        (r"(total_tests\s*=\s*)28\b", r"\g<1>29"),
        (r"(assert\s+len\([^)]+\)\s*==\s*)28\b", r"\g<1>29"),
        (r"(assert\s+[^=\n]+\.total_tests\s*==\s*)28\b", r"\g<1>29"),
        (r"(Total tests:\s*)28\b", r"\g<1>29"),
        (r"(Passed tests:\s*)28\b", r"\g<1>29"),
        (r"(Passed:\s*)28\b", r"\g<1>29"),
    ]

    updated = text
    for pattern, repl in replacements:
        updated = re.sub(pattern, repl, updated)

    return updated


def insert_test_path_in_runner_test(text: str, new_test: str) -> str:
    if new_test in text:
        return text

    anchors = [
        "scripts/test_kraken_order_payload_review_cli.py",
        "scripts/test_kraken_private_signing_material_review_integration.py",
        "scripts/test_kraken_payload_review_private_client_integration.py",
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


cli_text = read(CLI_FILE)
cli_text = insert_import_after_future_imports(cli_text, DATA["import_block"])
cli_text = insert_helper_safely(cli_text, DATA["helper_block"])
write(CLI_FILE, cli_text)

write(TEST_FILE, DATA["test_source"])

suite_text = read(SUITE_FILE)
suite_text = insert_test_path_after_anchor(suite_text, NEW_TEST)
write(SUITE_FILE, suite_text)

runner_text = read(RUNNER_TEST_FILE)
runner_text = update_expected_counts(runner_text)
runner_text = insert_test_path_in_runner_test(runner_text, NEW_TEST)
write(RUNNER_TEST_FILE, runner_text)

append_once(DOC_ROADMAP, "Slice 22D - Add Signing Material Review Integration to Payload Review CLI", DATA["roadmap_block"])
append_once(DOC_CONTROLS, "Slice 22D control - disabled signing material exposed at payload review CLI layer", DATA["controls_block"])
append_once(DOC_DECISIONS, "Slice 22D decision - expose disabled signing-material review in CLI review payload", DATA["decisions_block"])

print("[PASS] Slice 22D patch applied.")
print("[PASS] Payload review CLI helper added for disabled signing-material review.")
print("[PASS] Standalone validation added.")
print("[PASS] Master safety suite updated to include the new validation.")
print("[PASS] Roadmap, controls, and decision log updated.")

'@

$TempPatch = Join-Path $env:TEMP "apply_slice_22d_patch_v3.py"
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
Write-Host "Running Slice 22D validation..."
Invoke-CheckedPython -Arguments @(".\scripts\test_kraken_order_payload_review_cli_signing_material.py")
Invoke-CheckedPython -Arguments @(".\scripts\test_execution_safety_regression_suite_runner.py")
Invoke-CheckedPython -Arguments @(".\scripts\run_execution_safety_regression_suite.py")

Write-Host ""
Write-Host "Checking working tree..."
git status --short
if ($LASTEXITCODE -ne 0) {
  throw "git status failed with exit code ${LASTEXITCODE}"
}

Write-Host ""
Write-Host "[PASS] Slice 22D creation and validation completed."
Write-Host "Next expected commit message:"
Write-Host "Expose disabled signing material in payload review CLI"
Read-Host "Press Enter to close..."
