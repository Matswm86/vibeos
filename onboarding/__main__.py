"""VibeOS Onboarding Agent — entry point.

Usage:
    python3 -m onboarding              # default (gemma3:4b)
    python3 -m onboarding --model qwen3:4b
"""

import argparse
import sys

from .agent import check_ollama, check_model, DEFAULT_MODEL
from .flow import run_onboarding

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BOLD = "\033[1m"
NC = "\033[0m"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="VibeOS onboarding agent — guided first-boot experience",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Ollama model to use (default: {DEFAULT_MODEL})",
    )
    args = parser.parse_args()

    # Pre-flight checks
    if not check_ollama():
        print(f"{RED}[!] Ollama is not running.{NC}")
        print(f"    Start it with: {BOLD}ollama serve{NC}")
        print(f"    Then re-run:   {BOLD}python3 -m onboarding{NC}")
        sys.exit(1)

    if not check_model(args.model):
        print(f"{YELLOW}[!] Model '{args.model}' not found locally.{NC}")
        print(f"    Pulling it now...")
        import subprocess
        result = subprocess.run(["ollama", "pull", args.model])
        if result.returncode != 0:
            print(f"{RED}[!] Failed to pull model. Check your internet connection.{NC}")
            sys.exit(1)

    print(f"\n{GREEN}{BOLD}")
    print("  ╔══════════════════════════════════════════╗")
    print("  ║          VibeOS Onboarding Agent         ║")
    print(f"  ║       powered by {args.model:<22s} ║")
    print("  ╚══════════════════════════════════════════╝")
    print(f"{NC}")

    try:
        run_onboarding(model=args.model)
    except KeyboardInterrupt:
        print(f"\n\n{YELLOW}Onboarding interrupted. Run again anytime:{NC}")
        print(f"  {BOLD}cd {sys.path[0]} && python3 -m onboarding{NC}\n")
        sys.exit(130)


if __name__ == "__main__":
    main()
