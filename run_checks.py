#!/usr/bin/env python3
"""
Freegosy dev helper — runs flutter analyze then flutter test.
Run from the project root:  python run_checks.py
"""
import subprocess
import sys
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
FLUTTER = "flutter"  # assumes flutter is on PATH; change to full path if not

def run(label, cmd):
    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"{'='*60}\n")
    result = subprocess.run(cmd, cwd=ROOT, shell=False)
    return result.returncode

def main():
    steps = [
        ("flutter analyze", [FLUTTER, "analyze"]),
        ("flutter test",    [FLUTTER, "test"]),
    ]

    failed = []
    for label, cmd in steps:
        code = run(label, cmd)
        if code != 0:
            failed.append(label)
            print(f"\n❌  {label} exited with code {code}")
        else:
            print(f"\n✅  {label} passed")

    print(f"\n{'='*60}")
    if failed:
        print(f"  FAILED: {', '.join(failed)}")
        sys.exit(1)
    else:
        print("  All checks passed ✅")

if __name__ == "__main__":
    main()
