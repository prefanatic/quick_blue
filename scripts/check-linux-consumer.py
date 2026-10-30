#!/usr/bin/env python3
"""Build external Git consumers with fresh pub caches, never workspace resolves.

Run from any directory with Python 3, Git, Flutter and the Linux build toolchain.
The disposable Git snapshot includes tracked working-tree contents, so local
changes are tested without committing them to the source repository. All runs
retain their fixture directory for inspection and negative-control replay.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


PACKAGES = (
    "quick_blue",
    "quick_blue_core",
    "quick_blue_platform_interface",
    "quick_blue_darwin",
    "quick_blue_linux",
    "quick_blue_linux_dart",
    "quick_blue_windows",
)


def run(*args, cwd, env=None):
    print(f"[{cwd.name}] {' '.join(args)}", flush=True)
    subprocess.run(args, cwd=cwd, env=env, check=True)


def git_dependency(package, url, revision):
    return (
        f"  {package}:\n"
        "    git:\n"
        f"      url: {json.dumps(url)}\n"
        f"      ref: {revision}\n"
        f"      path: {package}\n"
    )


def check_consumer(package, snapshot, revision, fixture):
    consumer = fixture / f"consumer_{package}"
    cache = fixture / f"cache_{package}"
    cache.mkdir()
    # A cold Flutter SDK can populate Pub's cache while creating templates even
    # with --no-pub. Keep that bootstrap separate from the empty consumer cache.
    template_cache = fixture / f"template_cache_{package}"
    template_cache.mkdir()
    env = dict(os.environ, PUB_CACHE=str(cache))
    run(
        "flutter", "create", "--empty", "--no-pub", "--platforms=linux",
        "--project-name=linux_consumer", str(consumer), cwd=fixture,
        env=dict(env, PUB_CACHE=str(template_cache)),
    )
    if any(cache.iterdir()):
        raise ValueError("Consumer cache must be empty before pub get")
    # Flutter templates can seed a lockfile even with --no-pub. Do not let that
    # or the template's flutter_lints include influence this minimal consumer.
    (consumer / "pubspec.lock").unlink(missing_ok=True)
    (consumer / "analysis_options.yaml").write_text("{}\n")
    # No workspace membership, path dependency, or direct hosted runtime deps.
    manifest = (
        "name: linux_consumer\npublish_to: none\n"
        "environment:\n  sdk: ^3.13.5\n  flutter: '>=3.47.7'\n"
        "dependencies:\n  flutter:\n    sdk: flutter\n"
        + git_dependency(package, snapshot.as_uri(), revision)
        + "dependency_overrides:\n"
    )
    overrides = (
        [name for name in PACKAGES if name != package]
        if package == "quick_blue" else ["quick_blue_core", "quick_blue_platform_interface", "quick_blue_linux_dart"]
    )
    for name in overrides:
        manifest += git_dependency(name, snapshot.as_uri(), revision)
    (consumer / "pubspec.yaml").write_text(manifest)
    (consumer / "lib" / "main.dart").write_text(
        "import 'dart:io';\n"
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:quick_blue_core/quick_blue_core.dart' as core;\n"
        "import 'package:quick_blue_linux/quick_blue_linux.dart' as legacy;\n"
        "import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart' as backend;\n"
        "import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';\n"
        + ("import 'package:quick_blue/quick_blue.dart' as facade;\n" if package == "quick_blue" else "")
        + "Future<void> main() async {\n"
        "  WidgetsFlutterBinding.ensureInitialized();\n"
        "  try {\n"
        "    final installed = QuickBluePlatform.instance;\n"
        "    if (installed is! backend.QuickBlueLinux || "
        "legacy.QuickBlueLinux != backend.QuickBlueLinux) {\n"
        "      throw StateError('Generated registration did not install the shared backend');\n"
        "    }\n"
        "    if (!identical(core.QuickBlue.bluetoothStateStream, installed.bluetoothStateStream)) {\n"
        "      throw StateError('Core singleton differs from registered backend');\n"
        "    }\n"
        + ("    if (!identical(facade.QuickBlue.bluetoothStateStream, installed.bluetoothStateStream)) {\n"
           "      throw StateError('Flutter facade singleton differs');\n    }\n" if package == "quick_blue" else "")
        + "    await installed.capabilities();\n"
        "    await installed.close();\n"
        "    print('PASS: generated auto-registration and shared backend identity');\n"
        "    exit(0);\n"
        "  } catch (error, stack) { stderr.writeln('$error\\n$stack'); exit(1); }\n"
        "}\n"
    )
    run("flutter", "pub", "get", cwd=consumer, env=env)
    graph = json.loads((consumer / ".dart_tool" / "package_graph.json").read_text())
    if graph["roots"] != ["linux_consumer"]:
        raise ValueError("Must resolve outside the workspace")
    nodes = {node["name"]: node for node in graph["packages"]}
    if nodes["linux_consumer"]["dependencies"] != ["flutter", package]:
        raise ValueError(f"Consumer dependencies must be flutter and {package}")
    if "quick_blue_linux_dart" not in nodes["quick_blue_linux"]["dependencies"]:
        raise ValueError("quick_blue_linux must depend on quick_blue_linux_dart")
    if "bluez" not in nodes["quick_blue_linux_dart"]["dependencies"]:
        raise ValueError("quick_blue_linux_dart dependencies must include bluez")
    if "bluez" not in nodes:
        raise ValueError("bluez must resolve transitively")
    config = json.loads((consumer / ".dart_tool" / "package_config.json").read_text())
    for node in config["packages"]:
        if node["name"] in PACKAGES or node["name"] == "bluez":
            if not node["rootUri"].startswith(cache.as_uri() + "/"):
                raise ValueError(f"Package must resolve inside fixture cache: {node}")
    run("flutter", "analyze", "--no-pub", cwd=consumer, env=env)
    run("flutter", "build", "linux", "--debug", "--no-pub", cwd=consumer, env=env)
    binaries = list((consumer / "build/linux").glob("*/debug/bundle/linux_consumer"))
    if len(binaries) != 1:
        raise ValueError(f"Expected one Linux executable, got {binaries}")
    run("timeout", "60", "xvfb-run", "-a", str(binaries[0]), cwd=consumer, env=env)
    print(f"PASS: {package} installs and builds with transitive bluez", flush=True)


def main():
    root = Path(__file__).resolve().parent.parent
    fixture = Path(tempfile.mkdtemp(prefix="quick-blue-linux-consumer-"))
    print(f"Consumer fixtures: {fixture}", flush=True)
    try:
        snapshot = fixture / "repository"
        snapshot.mkdir()
        tracked = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
        ).decode().split("\0")
        for relative in filter(None, tracked):
            source = root / relative
            target = snapshot / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        run("git", "init", "--quiet", cwd=snapshot)
        run("git", "add", ".", cwd=snapshot)
        run(
            "git", "-c", "user.name=Consumer fixture", "-c",
            "user.email=consumer@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "--quiet", "-m", "consumer fixture", cwd=snapshot,
        )
        revision = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=snapshot, text=True
        ).strip()
        for package in ("quick_blue_linux", "quick_blue"):
            check_consumer(package, snapshot, revision, fixture)
    except BaseException:
        print(f"Failed fixtures retained at {fixture}", flush=True)
        raise
    else:
        print(f"Passed fixtures retained at {fixture}", flush=True)


if __name__ == "__main__":
    main()
