#!/usr/bin/env python3
"""Verify a matched local snapshot outside the Flutter workspace, without commits.

Requires --dart pointing to a separately installed Dart 3.13 SDK. Fixtures and
fresh caches are retained outside the repository for inspectable evidence. No
source/pub-cache manifests are rewritten: pubspec_overrides.yaml opts copied
packages out of workspace resolution for package-local checks.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse

PACKAGES = ('quick_blue_core', 'quick_blue_platform_interface', 'quick_blue_linux_dart')


def run(args, cwd, env):
    print(f'[{cwd}] {" ".join(map(str, args))}', flush=True)
    result = subprocess.run(args, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with (cwd / 'validation.log').open('a') as log:
        log.write(f'$ {" ".join(map(str, args))}\n{result.stdout}\nexit={result.returncode}\n')
    print(result.stdout, flush=True)
    result.check_returncode()
    return result.stdout


def inspect_graph(consumer, snapshot, expected_root='headless_consumer'):
    graph = json.loads((consumer / '.dart_tool/package_graph.json').read_text())
    if graph['roots'] != [expected_root]:
        raise ValueError(f'Unexpected graph roots: {graph["roots"]}')
    config_path = consumer / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    manifests = {}
    for package in config['packages']:
        uri = urljoin(config_path.as_uri(), package['rootUri'])
        root = Path(unquote(urlparse(uri).path))
        if package['name'] in PACKAGES and root.resolve() != (snapshot / package['name']).resolve():
            raise ValueError(f'Repository packages must use the matched snapshot: {root}')
        text = (root / 'pubspec.yaml').read_text()
        if re.search(r'^flutter:\s*$', text, re.M) and re.search(r'^  plugin:', text, re.M):
            raise ValueError(f'Flutter plugin metadata: {root}')
        if re.search(r'^\s+sdk:\s*flutter\s*$', text, re.M) or re.search(
                r'^  flutter:\s*[^\s#].*$', text, re.M):
            raise ValueError(f'Flutter SDK dependency/constraint: {root}')
        manifests[package['name']] = {'root': str(root), 'pubspec': text}
    for name in (*PACKAGES, 'plugin_platform_interface', 'bluez', 'dbus'):
        if name not in manifests:
            raise ValueError(f'Missing required transitive package: {name}')
    (consumer / 'resolved-manifests.json').write_text(json.dumps(manifests, indent=2))
    return manifests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True, type=Path)
    parser.add_argument('--flutter', action='store_true', help='Also build/run external Flutter Linux consumers')
    args = parser.parse_args()
    dart = args.dart.resolve()
    root = Path(__file__).resolve().parent.parent
    fixture = Path(tempfile.mkdtemp(prefix='quick-blue-headless-'))
    print(f'Retained fixtures: {fixture}', flush=True)
    env = dict(os.environ, PUB_CACHE=str(fixture / 'pub-cache'))
    version = run([str(dart), '--version'], fixture, env)
    if not re.search(r'Dart SDK version: 3\.13\.', version):
        raise ValueError('Acceptance requires standalone Dart 3.13')
    if any((parent / 'bin/flutter').is_file() and (parent / 'packages/flutter_tools').is_dir()
           for parent in dart.parents):
        raise ValueError('Use a standalone SDK, not the Flutter SDK wrapper')
    snapshot = fixture / 'packages'
    names = PACKAGES
    hashes = {}
    for name in names:
        source = root / name
        target = snapshot / name
        target.mkdir(parents=True)
        for relative in ('lib', 'test', 'pubspec.yaml', 'analysis_options.yaml', 'linux', 'android', 'darwin', 'windows'):
            item = source / relative
            if item.is_dir():
                shutil.copytree(item, target / relative, ignore=shutil.ignore_patterns('build', '.dart_tool', '.gradle'))
            elif item.is_file():
                shutil.copy2(item, target / relative)
        for item in sorted(target.rglob('*')):
            if item.is_file():
                hashes[str(item.relative_to(snapshot))] = hashlib.sha256(item.read_bytes()).hexdigest()
    (fixture / 'source-hashes.json').write_text(json.dumps(hashes, indent=2))
    overrides = 'dependency_overrides:\n' + ''.join(
        f'  {name}:\n    path: {json.dumps(str(snapshot / name))}\n' for name in PACKAGES)

    for name in names:
        dependencies = {
            'quick_blue_core': ('quick_blue_platform_interface',),
            'quick_blue_platform_interface': (),
            'quick_blue_linux_dart': ('quick_blue_core', 'quick_blue_platform_interface'),
        }.get(name, ())
        local_overrides = ('dependency_overrides:\n' + ''.join(
            f'  {dependency}:\n    path: {json.dumps(str(snapshot / dependency))}\n'
            for dependency in dependencies)) if dependencies else ''
        (snapshot / name / 'pubspec_overrides.yaml').write_text('resolution: null\n' + local_overrides)
    consumer = fixture / 'consumer'
    (consumer / 'bin').mkdir(parents=True)
    (consumer / 'pubspec.yaml').write_text(
        'name: headless_consumer\npublish_to: none\nenvironment:\n  sdk: ^3.13.0\n'
        'dependencies:\n  quick_blue_core: ^0.5.0\n  quick_blue_linux_dart: ^0.5.0\n' + overrides)
    (consumer / 'bin/main.dart').write_text(
        "import 'package:quick_blue_core/quick_blue_core.dart';\n"
        "import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';\n"
        "void main() {\n  QuickBlueLinux.registerWith();\n"
        "  print(QuickBlue.device('synthetic-device').id);\n}\n")
    run([str(dart), 'pub', 'get'], consumer, env)
    deps = run([str(dart), 'pub', 'deps', '--json'], consumer, env)
    (consumer / 'dependencies.json').write_text(deps)
    inspect_graph(consumer, snapshot)
    run([str(dart), 'analyze'], consumer, env)
    run([str(dart), 'run', 'bin/main.dart'], consumer, env)
    for name in PACKAGES:
        package = snapshot / name
        run([str(dart), 'pub', 'get'], package, env)
        run([str(dart), 'analyze'], package, env)
        run([str(dart), 'test', '--reporter=expanded'], package, env)
    # Copy the public operator example outside the Flutter workspace as well.
    cli = fixture / 'cli'
    shutil.copytree(root / 'quick_blue_linux/example', cli,
                    ignore=shutil.ignore_patterns('.dart_tool', 'build', 'pubspec.lock', 'pubspec_overrides.yaml'))
    (cli / 'pubspec_overrides.yaml').write_text('resolution: null\n' + overrides)
    run([str(dart), 'pub', 'get'], cli, env)
    inspect_graph(cli, snapshot, 'quick_blue_linux_cli')
    run([str(dart), 'analyze'], cli, env)
    run([str(dart), 'test', '--reporter=expanded'], cli, env)
    (cli / 'build').mkdir(exist_ok=True)
    run([str(dart), 'compile', 'exe', 'bin/main.dart', '-o', 'build/ble_cli'], cli, env)
    headless_env = {key: value for key, value in env.items()
                    if key not in ('DISPLAY', 'WAYLAND_DISPLAY')}
    run([str(cli / 'build/ble_cli'), '--help'], cli, headless_env)
    run([str(dart), 'compile', 'exe', 'bin/fake_flow.dart', '-o', 'build/fake_flow'], cli, env)
    run([str(cli / 'build/fake_flow')], cli, headless_env)
    if args.flutter:
        run([sys.executable, str(root / 'scripts/check-linux-consumer.py')], fixture, env)
    print(f'PASS: standalone graph/package checks; evidence: {fixture}', flush=True)


if __name__ == '__main__':
    main()
