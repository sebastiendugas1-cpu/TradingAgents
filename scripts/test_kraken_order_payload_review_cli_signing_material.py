"""Slice 22D validation: disabled signing material appears in payload review CLI helper."""

from __future__ import annotations

from pathlib import Path
import importlib.util
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

CLI_PATH = REPO_ROOT / "scripts" / "run_kraken_order_payload_review.py"


FORBIDDEN_SOURCE_TOKENS = [
    "os.environ",
    "getenv",
    "hmac",
    "hashlib",
    "base64",
    "urlopen",
    "requests.",
    "urllib.request",
    "AddOrder",
    "CancelOrder",
    "Withdraw",
    "Deposit",
]


def _load_cli_module():
    spec = importlib.util.spec_from_file_location("run_kraken_order_payload_review", CLI_PATH)
    assert spec is not None
    assert spec.loader is not None

    module = importlib.util.module_from_spec(spec)
    sys.modules["run_kraken_order_payload_review"] = module
    spec.loader.exec_module(module)
    return module


def test_cli_helper_attaches_disabled_signing_material_review_to_mapping() -> None:
    module = _load_cli_module()

    assert hasattr(module, "_attach_disabled_signing_material_review")

    payload = module._attach_disabled_signing_material_review(
        {
            "status": "disabled",
            "private_client_review": {"status": "disabled"},
        }
    )

    assert payload["status"] == "disabled"
    assert "signing_material_review" in payload
    assert payload["signing_material_review"]["status"] == "disabled"
    assert payload["signing_material_review"]["signing_material_review"]["exchange"] == "kraken"
    assert payload["signing_material_review"]["signing_material_review"]["status"] == "disabled"
    assert payload["signing_material_review"]["can_read_api_secret"] is False
    assert payload["signing_material_review"]["can_read_environment_secret"] is False
    assert payload["signing_material_review"]["can_generate_nonce"] is False
    assert payload["signing_material_review"]["can_generate_signature"] is False
    assert payload["signing_material_review"]["can_call_private_endpoint"] is False


def test_cli_source_is_wired_to_disabled_signing_material_review() -> None:
    source = CLI_PATH.read_text(encoding="utf-8")

    assert "build_disabled_signer_shell_review_with_signing_material" in source
    assert "_attach_disabled_signing_material_review" in source
    assert "signing_material_review" in source

    for forbidden in FORBIDDEN_SOURCE_TOKENS:
        assert forbidden not in source


def main() -> None:
    print("Slice 22D validation: Signing Material Review Integration in Payload Review CLI")
    print("=" * 80)

    test_cli_helper_attaches_disabled_signing_material_review_to_mapping()
    print("[OK] payload review CLI helper attaches disabled signing-material review")

    test_cli_source_is_wired_to_disabled_signing_material_review()
    print("[OK] CLI source is wired to disabled signing-material review without unsafe calls")

    print("=" * 80)
    print("[PASS] Slice 22D signing material payload review CLI validation passed.")
    print("[PASS] No API secret reading was introduced.")
    print("[PASS] No environment secret reading was introduced.")
    print("[PASS] No nonce generation was introduced.")
    print("[PASS] No HMAC/hashlib/base64 signing implementation was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
