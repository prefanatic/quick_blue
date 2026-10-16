#!/usr/bin/env python3
"""Cross-build a retained headless fixture; optionally execute under user-mode QEMU.

First run check-headless-consumer.py with a standalone SDK. Pass its retained
cli directory here. QEMU needs an ARM64 glibc sysroot; no bus/radio is accessed.
Cross-build alone is not runtime proof, and emulation is not hardware proof.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess


def run(args, cwd, env):
    print('$ ' + ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), cwd=cwd, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=180)
    print(result.stdout, end='', flush=True)
    result.check_returncode()
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', required=True, type=Path)
    parser.add_argument('--cli', required=True, type=Path)
    parser.add_argument('--qemu', type=Path)
    parser.add_argument('--sysroot', type=Path)
    args = parser.parse_args()
    if bool(args.qemu) != bool(args.sysroot):
        parser.error('--qemu and --sysroot must be supplied together')
    dart, cli = args.dart.resolve(), args.cli.resolve()
    if not (cli / 'resolved-manifests.json').is_file():
        parser.error('--cli must be the externally verified retained CLI fixture')
    env = {k: v for k, v in os.environ.items()
           if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'LD_PRELOAD', 'LD_LIBRARY_PATH')}
    version = run([dart, '--version'], cli, env)
    if 'Dart SDK version: 3.13.' not in version:
        parser.error('use the standalone Dart 3.13 SDK used for the fixture')
    build = cli / 'build'
    build.mkdir(exist_ok=True)
    # A loader-only probe: deliberately no Bluetooth socket, D-Bus or agent.
    probe = build / 'native_libraries.dart'
    probe.write_text("import 'dart:ffi';\nvoid main() {\n"
                     "  final libc = DynamicLibrary.open('libc.so.6');\n"
                     "  for (final symbol in ['socket', 'connect', 'close', 'fcntl', '__errno_location']) {\n"
                     "    libc.lookup<Void>(symbol);\n  }\n"
                     "  final bluetooth = DynamicLibrary.open('libbluetooth.so.3');\n"
                     "  bluetooth.lookup<Void>('str2ba');\n"
                     "  print('PASS: glibc and optional libbluetooth loader/symbols only');\n}\n")
    for source, output in [('bin/main.dart', 'ble_cli-arm64'),
                           ('bin/fake_flow.dart', 'fake_flow-arm64'),
                           ('build/native_libraries.dart', 'native_libraries-arm64')]:
        artifact = build / output
        run([dart, 'compile', 'exe', '--target-os=linux', '--target-arch=arm64',
             source, '-o', artifact], cli, env)
        run(['file', artifact], cli, env)
        header = run(['readelf', '-h', artifact], cli, env)
        if 'AArch64' not in header:
            raise ValueError('Expected AArch64 ELF')
        run(['readelf', '-l', '-d', artifact], cli, env)
    result = {'architecture': 'AArch64', 'runtime': 'not executed',
              'hardware': 'not executed', 'sdk': version.strip()}
    if args.qemu:
        qemu, sysroot = args.qemu.resolve(), args.sysroot.resolve()
        run([qemu, '--version'], cli, env)
        # -E sets the guest environment, not the host emulator's loader path.
        libraries = ':'.join(str(sysroot / p) for p in
                             ('usr/lib/aarch64-linux-gnu', 'lib/aarch64-linux-gnu', 'usr/lib64', 'lib64'))
        prefix = [qemu, '-L', sysroot, '-E', 'LD_LIBRARY_PATH=' + libraries]
        run([*prefix, build / 'ble_cli-arm64', '--help'], cli, env)
        run([*prefix, build / 'fake_flow-arm64'], cli, env)
        run([*prefix, build / 'native_libraries-arm64'], cli, env)
        result['runtime'] = 'QEMU help, fake flow and loader-only probe passed'
    (build / 'arm64-result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
