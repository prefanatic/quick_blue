"""Canonical whitespace normalization for Pigeon generated sources."""


import re


def normalize_text(text: str) -> str:
    normalized = re.sub(r'[ \t]+$', '', text, flags=re.MULTILINE)
    return normalized.rstrip('\n') + '\n' if normalized else ''


if __name__ == '__main__':
    from pathlib import Path
    import sys

    for filename in sys.argv[1:]:
        path = Path(filename)
        original = path.read_text()
        normalized = normalize_text(original)
        if normalized != original:
            path.write_text(normalized)
