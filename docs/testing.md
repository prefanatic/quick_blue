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
| Release metadata | `scripts/publish-packages.sh --dry-run` |
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

## Linux L2CAP syscall characterization

Run the real channel control flow against scripted syscall wrappers, without
loading BlueZ or opening a Bluetooth socket:

```sh
(cd quick_blue_linux && flutter test test/l2cap_channel_test.dart \
  test/l2cap_harness_test.dart --reporter expanded)
(cd quick_blue_linux && flutter test --reporter expanded)
(cd quick_blue_linux && flutter analyze)
(cd quick_blue/example && flutter build linux --debug)
```

The [channel tests](https://github.com/prefanatic/quick_blue/blob/master/quick_blue_linux/test/l2cap_channel_test.dart) cover exact
bytes for success, partial sends, finite EINTR and EAGAIN, failed connect (including
the eight-attempt EINTR limit), send/receive closure and allocation/fd cleanup.
The only production seam added is an optional allocator defaulting to `calloc`;
the existing `Libc`/`LibBluetooth` injection supplies scripted calls. The counting
allocator delegates to real zeroed allocations; fd counts describe fake ownership,
not kernel descriptors. No socket behavior correction is included.

The [parent watchdog](https://github.com/prefanatic/quick_blue/blob/master/quick_blue_linux/test/l2cap_harness_test.dart) launches
separate Dart processes for persistent first-chunk EINVAL, send/recv EINTR,
always-readable receive and zero-byte send. It waits at most 15 seconds for the
armed record, observes for 500 ms, then sends SIGKILL and waits at most five seconds
for process exit/reaping. Cleanup also kills/reaps on assertion/startup failure.
JSON records include the actual exit code, elapsed time, syscall/ownership counters,
main-isolate heartbeat and an independent reporter-isolate heartbeat. Do not run
the child runner directly: its non-yielding cases cannot be stopped by Dart timers.
For a safely bounded single reproduction:

```sh
(cd quick_blue_linux && flutter test test/l2cap_harness_test.dart \
  --plain-name 'send-einval: watchdog termination is failure characterization' \
  --reporter expanded)
```

Retained [observations](https://github.com/prefanatic/quick_blue/blob/master/quick_blue_linux/test/evidence/l2cap/README.md) show
non-yielding send/receive loops, versus zero-send's responsive but non-completing
retry loop. SIGKILL is **failure characterization, never successful operation or
channel cleanup**: live allocations/fake fds in the last snapshot remain owned
until process termination, which does not execute channel finalizers. These tests
and the example build prove scripted control flow and compilation only, not a
working L2CAP peripheral, real syscalls, MTU negotiation or native readiness.

## Report evidence, not assumptions

Record the exact command, revision, host/device, executed scenarios, result and
any skips. If blocked, state the command attempted, the concrete blocker, and
what remains unverified. Unit mocks, stubs and CI builds do not replace a hardware
run. [Limitations](limitations.md) tracks known verification gaps.
