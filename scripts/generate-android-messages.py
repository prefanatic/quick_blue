#!/usr/bin/env python3
"""Regenerate Android Pigeon outputs, then normalize generator whitespace.

Pigeon 29 emits space-only lines in EventChannel boilerplate. This mechanical
post-generation step keeps git diff --check clean without hand-editing output.
Run from the repository root: python3 scripts/generate-android-messages.py
"""

from pathlib import Path
import subprocess


root = Path(__file__).resolve().parents[1]
package = root / "quick_blue"
subprocess.run(
    ["dart", "run", "pigeon", "--input", "pigeons/messages.dart"],
    cwd=package,
    check=True,
)
outputs = (
    package / "lib/src/messages.g.dart",
    package / "android/src/main/kotlin/com/example/quick_blue/Messages.g.kt",
)
for output in outputs:
    text = output.read_text()
    output.write_text("\n".join(line.rstrip() for line in text.splitlines()) + "\n")
