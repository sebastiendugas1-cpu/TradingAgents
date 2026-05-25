"""Slice 22C validation: disabled signing material wired to signer review."""

from __future__ import annotations

from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tradingagents.execution.kraken_private_signing_material_review_integration import (
    build_disabled_signer_shell_review_with_signing_material,
)


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


def test_review_integration_attaches_disabled_signing_material() -> None:
    review = build_disabled_signer_shell_review_with_signing_material(
        signer_review={
            "status": "disabled",
            "source": "test signer review",
            "can_call_private_endpoint": False,
        }
    )

    assert review["status"] == "disabled"
    assert review["can_read_api_secret"] is False
    assert review["can_read_environment_secret"] is False
    assert review["can_generate_nonce"] is False
    assert review["can_generate_signature"] is False
    assert review["can_call_private_endpoint"] is False
    assert review["required_permissions"] == []

    assert review["signer_shell_review"]["status"] == "disabled"
    assert review["signing_material_review"]["exchange"] == "kraken"
    assert review["signing_material_review"]["status"] == "disabled"
    assert review["signing_material_review"]["can_read_api_secret"] is False
    assert review["signing_material_review"]["can_read_environment_secret"] is False
    assert review["signing_material_review"]["can_generate_nonce"] is False
    assert review["signing_material_review"]["can_generate_signature"] is False
    assert review["signing_material_review"]["can_call_private_endpoint"] is False


def test_review_integration_can_build_from_current_signer_shell() -> None:
    review = build_disabled_signer_shell_review_with_signing_material()

    assert review["status"] == "disabled"
    assert "signer_shell_review" in review
    assert "signing_material_review" in review
    assert review["signing_material_review"]["status"] == "disabled"
    assert review["can_call_private_endpoint"] is False


def test_review_integration_source_contains_no_secret_signing_or_network_implementation() -> None:
    source_path = (
        REPO_ROOT
        / "tradingagents"
        / "execution"
        / "kraken_private_signing_material_review_integration.py"
    )
    source = source_path.read_text(encoding="utf-8")

    for forbidden in FORBIDDEN_SOURCE_TOKENS:
        assert forbidden not in source

    assert "build_disabled_kraken_private_signing_material" in source
    assert "can_generate_nonce" in source
    assert "can_generate_signature" in source
    assert "can_call_private_endpoint" in source


def main() -> None:
    print("Slice 22C validation: Disabled Signing Material + Signer Shell Review Integration")
    print("=" * 80)

    test_review_integration_attaches_disabled_signing_material()
    print("[OK] disabled signing material attaches to explicit signer review")

    test_review_integration_can_build_from_current_signer_shell()
    print("[OK] disabled signing material attaches to current signer shell review path")

    test_review_integration_source_contains_no_secret_signing_or_network_implementation()
    print("[OK] integration source contains no secret, signing, or network implementation")

    print("=" * 80)
    print("[PASS] Slice 22C disabled signing material review integration validation passed.")
    print("[PASS] No API secret reading was introduced.")
    print("[PASS] No environment secret reading was introduced.")
    print("[PASS] No nonce generation was introduced.")
    print("[PASS] No HMAC/hashlib/base64 signing implementation was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
