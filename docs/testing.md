---
type: "Playbook"
title: "Verify repository changes"
description: "Select package, native and hardware checks and record precise evidence."
tags: ["development", "testing", "ci"]

sources: [{"id": "source1", "resource": "../.github/workflows/ci.yml"}, {"id": "source2", "resource": "../AGENTS.md"}, {"id": "source3", "resource": "../CONTRIBUTING.md"}, {"id": "source4", "resource": "../scripts/publish-packages.sh"}, {"id": "source5", "resource": "../scripts/windows-integration-test.sh"}]
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

Console TCP 8006 and RDP TCP/UDP 3389 bind to `127.0.0.1` by default.
Non-loopback IPv4 `QUICK_BLUE_WINDOWS_BIND_ADDRESS` requires
`QUICK_BLUE_WINDOWS_ALLOW_REMOTE=1`. This exposes the guest console/RDP;
use trusted networks and appropriate access controls. IPv6 bind overrides
are unsupported; port overrides must be numeric.

Inspect actual production argv without Docker, downloads, resets, OEM writes
or USB discovery:

```sh
scripts/windows-integration-test.sh --dry-run | tr '\0' '\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_windows_launch.py -v
bash -n scripts/windows-integration-test.sh
```

Dry-run stdout is NUL-separated argv including `docker` and the image, not a
shell command to evaluate. Spaces/quotes remain inside arguments; colon-containing
host paths are unsupported by Docker's `-v` syntax. USB previews require explicit
bus/device coordinates and do not check nodes or permissions. Tests prove Linux
argument construction only, not VM boot, reachability, passthrough or guest execution.
The guest currently reuses a present Flutter executable without comparing cached
channel metadata against the request. These tests neither validate nor correct
that Windows-only behavior; changing the request does not guarantee cached SDK
replacement.

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
