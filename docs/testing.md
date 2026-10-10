---
type: "Playbook"
title: "Verify repository changes"
description: "Select package, native and hardware checks and record precise evidence."
tags: ["development", "testing", "ci"]

sources: [{"id": "source1", "resource": "../.github/workflows/ci.yml"}, {"id": "source2", "resource": "../AGENTS.md"}, {"id": "source3", "resource": "../CONTRIBUTING.md"}, {"id": "source4", "resource": "../scripts/publish-packages.sh"}, {"id": "source5", "resource": "../scripts/windows-integration-test.sh"}, {"id": "site-tests", "resource": "../scripts/test_check_docs_site.py"}, {"id": "release-tests", "resource": "../scripts/test_publish_packages.py"}, {"id": "consumer-tests", "resource": "../scripts/test_check_linux_consumer.py"}, {"id": "maintenance-ci", "resource": "../.github/workflows/docs.yml"}]
---

# Verify repository changes

Run commands from the repository root unless a subshell below changes directory.
CI pins Flutter `3.47.6`; package minimum versions are not the CI version.

## Fast checks

```sh
flutter pub get
flutter analyze
(cd quick_blue_platform_interface && flutter test)
git diff --check
```

Format touched Dart files with `dart format`. The CI format gate excludes generated
Dart bindings. Run `flutter analyze` and `flutter test` in affected packages:
`quick_blue`, `quick_blue_platform_interface`, `quick_blue_darwin`,
`quick_blue_linux`, `quick_blue_windows`, and `quick_blue/example`.
Shared API/model changes require platform-interface and affected facade tests.

## Maintenance-tool regressions

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 -O -m unittest discover -s scripts -p 'test_*.py'
```

The Documentation workflow runs these tests alongside OKF validation and a clean
site build. The suite includes 13 OKF tests, 15 built-site tests, four release
metadata tests and five consumer-construction tests. Site fixtures run the copied
validator in normal and optimized subprocesses, checking navigation coverage and
duplicates, rendered pages, anchors, missing targets, absolute/encoded project
prefix escapes, resolved dot-segment/encoded/relative traversal, file and directory
symlink escapes (where supported), valid parent-relative links and search assets.
Release fixtures check version/constraint drift,
malformed version values, dependency membership and usage errors before a logging
Dart stand-in can run. Bash itself has no Python optimization mode.

Consumer fixtures mock command execution and synthesize package graphs/configs;
they check Git dependency quoting/overrides, isolated roots and dependencies,
transitive bluez, cache locations and the initially empty cache. They never invoke
Flutter or Git. Their printed PASS lines are not actual build evidence. Release
fixtures never publish; no fixture needs network or a VM. Explicit validation
failures remain enabled under `-O`.

These tests prove only executed maintenance-tool success/failure behavior, not
semantic documentation correctness, external deployment, package publication or
native/hardware behavior. Real consumer builds remain a separate check using
`python3 scripts/check-linux-consumer.py`; see [maintenance](maintenance.md) for
the real documentation validation chain.

## Native and generated boundaries

| Change | Check |
| --- | --- |
| Pigeon schema | Run `dart run pigeon --input pigeons/messages.dart` inside each changed owning package; inspect generated diff |
| Darwin source | `./quick_blue_darwin/darwin/quick_blue_darwin/type_check/run.sh` |
| Darwin ownership/restoration helpers | `swift test` inside the corresponding `connection_ownership` / `restoration_summary` directories |
| Android Kotlin | `(cd quick_blue/example/android && ./gradlew :quick_blue:testDebugUnitTest)` |
| Windows ownership | Native CMake/CTest target on Windows (CI `build-windows`) |
| Release metadata | `scripts/publish-packages.sh --dry-run` and `python3 scripts/check-changelog-coverage.py` |
| Workflow selection/policy | Docs-venv Python: `-m unittest discover -s scripts -p 'test_workflow_readiness.py' -v` |
| Documentation | [Maintenance checks](maintenance.md), source review, and site build when configured |

Darwin's Linux type-check harness uses signature-faithful stubs; it does not prove
CoreBluetooth behavior on hardware. Pigeon sources live in `quick_blue/pigeons`,
`quick_blue_darwin/pigeons`, and `quick_blue_windows/pigeons`; do not hand-edit
`messages.g.*` outputs.

## Hardware BLE smoke

Required for scan, connect, discovery, read/write, notification, switching or
platform Bluetooth changes when the matching host/hardware is available.
From `quick_blue/example`:

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d macos
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux
```

Supply [test defines](example-options.md) for a known device. An advertisement-only
profile does not satisfy GATT verification. Writes are opt-in and require a safe
peripheral command. Missing Bluetooth on a supported smoke target must fail.

Physical-device multi-engine recipes (replace placeholders):

```sh
flutter test integration_test/android_multi_engine_test.dart -d ANDROID_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_ID'
flutter test integration_test/ios_multi_engine_test.dart -d IOS_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID='SERVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'
```

For switching, stress and benchmark selection, see [example workflows](example-app.md).

## Windows VM

Repository-root recipe: replace these example USB IDs with your adapter IDs.

```sh
QUICK_BLUE_WINDOWS_USB_VENDOR_ID=0x0bda \
QUICK_BLUE_WINDOWS_USB_PRODUCT_ID=0x8771 \
  scripts/windows-integration-test.sh
```

Dockur persists `.dart_tool/dockur_windows/`; the guest caches its checkout at
`C:\quick_blue_workspace\quick_blue`. `QUICK_BLUE_WINDOWS_CLEAN_WORKTREE=1`
refreshes checkout without reinstalling Windows. `QUICK_BLUE_WINDOWS_RESET=1`
rebuilds the VM disk; do not use it for routine reruns.

## Report evidence, not assumptions

CI selects readiness checks for `**/CHANGELOG.md` and release pubspec changes.
Source/configuration changes selected by `validate` also run cheap canonical OKF
validation and readiness fixtures. Docs-only changes remain owned by the
Documentation workflow, including its site build.

Fixtures read real workflow filters, conditions and matrices. The local glob
evaluator supports only the current literal/`*`/`**` subset, fails on unsupported
patterns, and does not prove exact dorny/GitHub execution semantics. Its aggregate
policy treats selected failures as FAIL, cancellations or unexpected skips as
UNRESOLVED (rerun required), and condition-false skips as neutral. Changes-job
failures cannot produce an all-skip pass. This is a local policy fixture, not an
aggregate CI job or branch-protection enforcement. Hosted iOS/macOS/Windows
builds explicitly disabled by `SKIP_HOSTED_PLATFORM_BUILDS` remain unverified.

Record the exact command, revision, host/device, executed scenarios, result and
any skips. If blocked, state the command attempted, the concrete blocker, and
what remains unverified. Unit mocks, stubs and CI builds do not replace a hardware
run. [Limitations](limitations.md) tracks known verification gaps.
