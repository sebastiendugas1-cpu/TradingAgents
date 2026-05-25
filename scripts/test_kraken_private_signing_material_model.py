"""Slice 22B validation: disabled Kraken private signing material model."""

from __future__ import annotations

from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tradingagents.execution.kraken_private_signing_material_model import (
    DisabledKrakenPrivateSigningMaterial,
    build_disabled_kraken_private_signing_material,
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


def test_signing_material_is_disabled_and_data_only() -> None:
    material = build_disabled_kraken_private_signing_material()

    assert isinstance(material, DisabledKrakenPrivateSigningMaterial)
    assert material.exchange == "kraken"
    assert material.status == "disabled"
    assert material.can_read_api_secret is False
    assert material.can_read_environment_secret is False
    assert material.can_generate_nonce is False
    assert material.can_generate_signature is False
    assert material.can_call_private_endpoint is False
    assert material.required_permissions == ()
    assert "disabled" in material.disabled_reason.lower()


def test_review_payload_contains_no_sensitive_or_executable_material() -> None:
    payload = build_disabled_kraken_private_signing_material().as_review_payload()

    assert payload["exchange"] == "kraken"
    assert payload["status"] == "disabled"
    assert payload["can_read_api_secret"] is False
    assert payload["can_read_environment_secret"] is False
    assert payload["can_generate_nonce"] is False
    assert payload["can_generate_signature"] is False
    assert payload["can_call_private_endpoint"] is False
    assert payload["required_permissions"] == []

    serialized = repr(payload).lower()
    assert "secret" in serialized
    assert "api_key" not in serialized
    assert "private_key" not in serialized
    assert "signature_value" not in serialized


def test_model_source_contains_no_secret_signing_or_network_implementation() -> None:
    source_path = REPO_ROOT / "tradingagents" / "execution" / "kraken_private_signing_material_model.py"
    source = source_path.read_text(encoding="utf-8")

    for forbidden in FORBIDDEN_SOURCE_TOKENS:
        assert forbidden not in source

    assert "nonce" in source
    assert "signature" in source
    assert "can_generate_nonce: bool = False" in source
    assert "can_generate_signature: bool = False" in source
    assert "can_call_private_endpoint: bool = False" in source


def main() -> None:
    print("Slice 22B validation: Disabled Kraken Private Signing Material Model")
    print("=" * 80)

    test_signing_material_is_disabled_and_data_only()
    print("[OK] signing material model is disabled and data-only")

    test_review_payload_contains_no_sensitive_or_executable_material()
    print("[OK] review payload contains no sensitive or executable material")

    test_model_source_contains_no_secret_signing_or_network_implementation()
    print("[OK] model source contains no secret, signing, or network implementation")

    print("=" * 80)
    print("[PASS] Slice 22B disabled signing material model validation passed.")
    print("[PASS] No API secret reading was introduced.")
    print("[PASS] No environment secret reading was introduced.")
    print("[PASS] No nonce generation was introduced.")
    print("[PASS] No HMAC/hashlib/base64 signing implementation was introduced.")
    print("[PASS] No private execution endpoint call was introduced.")
    print("[PASS] No private account-changing permission requirement was introduced.")


if __name__ == "__main__":
    main()
