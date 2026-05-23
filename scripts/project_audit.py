# ============================ Project Audit Script ============================
"""
Project audit script for the TradingAgents crypto / multi-asset project.

Purpose:
- Confirm local environment health.
- Confirm Git branch/status.
- Confirm Python and Conda state.
- Confirm .env exists.
- Confirm API keys exist without revealing secrets.
- Confirm important folders/files exist.

Run from project root:

    python scripts/project_audit.py
"""

from __future__ import annotations

import importlib
import os
import platform
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = PROJECT_ROOT / ".env"

EXPECTED_DOCS = [
    "00_PROJECT_VISION.md",
    "01_SAFETY_RULES.md",
    "02_ARCHITECTURE.md",
    "03_ROADMAP.md",
    "04_SLICE_WORKFLOW.md",
    "05_DATA_SOURCES.md",
    "06_TRADINGVIEW_PLAN.md",
    "07_KRAKEN_PLAN.md",
    "08_AGENT_DESIGN.md",
    "09_BACKTESTING_AND_OPTIMIZATION.md",
    "10_EXECUTION_AND_RISK_CONTROLS.md",
    "11_DECISION_LOG.md",
    "12_NEXT_CHAT_PROMPT.md",
]

EXPECTED_ENV_KEYS = [
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "ANTHROPIC_API_KEY",
    "FINNHUB_API_KEY",
    "KRAKEN_API_KEY",
    "KRAKEN_API_SECRET",
]


def print_section(title: str) -> None:
    print()
    print("=" * 80)
    print(title)
    print("=" * 80)


def run_command(command: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd or PROJECT_ROOT),
            text=True,
            capture_output=True,
            check=False,
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except FileNotFoundError as exc:
        return 127, "", str(exc)


def mask_presence(value: str | None) -> str:
    if value is None or value.strip() == "":
        return "missing"

    cleaned = value.strip()

    if len(cleaned) <= 8:
        return "present"

    return "present"


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}

    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        values[key] = value

    return values


def check_git() -> None:
    print_section("GIT STATUS")

    code, branch, err = run_command(["git", "branch", "--show-current"])
    print(f"Current branch: {branch if branch else 'unknown'}")

    code, remotes, err = run_command(["git", "remote", "-v"])
    print()
    print("Remotes:")
    print(remotes if remotes else "No remotes found.")

    code, status, err = run_command(["git", "status", "--short"])
    print()
    print("Working tree:")
    print(status if status else "clean")

    code, log, err = run_command(["git", "log", "--oneline", "-3"])
    print()
    print("Recent commits:")
    print(log if log else "No commits found.")


def check_python() -> None:
    print_section("PYTHON / CONDA ENVIRONMENT")

    print(f"Python executable: {sys.executable}")
    print(f"Python version:    {sys.version.split()[0]}")
    print(f"Platform:          {platform.platform()}")

    conda_env = os.environ.get("CONDA_DEFAULT_ENV")
    print(f"Conda environment: {conda_env if conda_env else 'not detected'}")

    code, conda_version, err = run_command(["conda", "--version"])
    print(f"Conda version:     {conda_version if conda_version else 'not detected'}")


def check_imports() -> None:
    print_section("PACKAGE IMPORT CHECK")

    modules = [
        "tradingagents",
        "cli",
    ]

    for module_name in modules:
        try:
            module = importlib.import_module(module_name)
            location = getattr(module, "__file__", "built-in or namespace package")
            print(f"[OK] {module_name}: {location}")
        except Exception as exc:
            print(f"[FAIL] {module_name}: {exc}")


def check_env() -> None:
    print_section(".ENV / API KEY CHECK")

    print(f".env path: {ENV_FILE}")

    if not ENV_FILE.exists():
        print(".env exists: no")
        print("No API keys checked because .env is missing.")
        return

    print(".env exists: yes")

    env_values = load_env_file(ENV_FILE)

    print()
    print("Configured keys without revealing secrets:")

    for key in EXPECTED_ENV_KEYS:
        value = env_values.get(key) or os.environ.get(key)
        print(f"- {key}: {mask_presence(value)}")


def check_project_files() -> None:
    print_section("PROJECT FILE CHECK")

    paths = [
        PROJECT_ROOT / "README.md",
        PROJECT_ROOT / "pyproject.toml",
        PROJECT_ROOT / "requirements.txt",
        PROJECT_ROOT / ".gitignore",
        PROJECT_ROOT / "docs",
        PROJECT_ROOT / "scripts",
        PROJECT_ROOT / "tradingagents",
        PROJECT_ROOT / "cli",
    ]

    for path in paths:
        status = "exists" if path.exists() else "missing"
        print(f"- {path.relative_to(PROJECT_ROOT)}: {status}")

    print()
    print("Docs check:")

    docs_root = PROJECT_ROOT / "docs"

    for doc_name in EXPECTED_DOCS:
        doc_path = docs_root / doc_name
        status = "exists" if doc_path.exists() else "missing"
        print(f"- docs/{doc_name}: {status}")


def check_output_folders() -> None:
    print_section("LOCAL OUTPUT / IGNORED FOLDER CHECK")

    folders = [
        PROJECT_ROOT / ".chatGPT-output",
        PROJECT_ROOT / "reports",
    ]

    for folder in folders:
        status = "exists" if folder.exists() else "missing"
        print(f"- {folder.relative_to(PROJECT_ROOT)}: {status}")

    gitignore = PROJECT_ROOT / ".gitignore"

    if gitignore.exists():
        text = gitignore.read_text(encoding="utf-8", errors="replace")
        print()
        print(".gitignore protection:")
        print(f"- .chatGPT-output/: {'yes' if '.chatGPT-output/' in text else 'no'}")
        print(f"- reports/: {'yes' if 'reports/' in text else 'no'}")
        print(f"- .env: {'yes' if '.env' in text else 'check manually'}")


def main() -> int:
    print("TradingAgents Project Audit")
    print(f"Project root: {PROJECT_ROOT}")

    check_git()
    check_python()
    check_imports()
    check_env()
    check_project_files()
    check_output_folders()

    print_section("AUDIT COMPLETE")
    print("Review any missing/failed items above.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
