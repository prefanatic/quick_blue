#!/usr/bin/env python3
"""Require the shared package version's exact heading in the main changelog."""
import argparse
from pathlib import Path
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        manifest = (args.root / 'quick_blue_platform_interface/pubspec.yaml').read_text()
        versions = re.findall(r'^version: ([^\s]+)\s*$', manifest, re.MULTILINE)
        if len(versions) != 1:
            raise ValueError('Expected exactly one package version')
        version = versions[0]
        changelog = (args.root / 'quick_blue/CHANGELOG.md').read_text()
        if not re.search(r'^## \[' + re.escape(version) + r'\](?:\s|$)', changelog, re.MULTILINE):
            raise ValueError(f'quick_blue/CHANGELOG.md has no ## [{version}] heading')
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 65
    print(f'Changelog covers {version}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
