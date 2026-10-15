---
type: "Playbook"
title: "Verify repository changes"
description: "Select package, native and hardware checks and record precise evidence."
tags: ["development", "testing", "ci"]

sources: [{"id": "source1", "resource": "../.github/workflows/ci.yml"}, {"id": "source2", "resource": "../AGENTS.md"}, {"id": "source3", "resource": "../CONTRIBUTING.md"}, {"id": "source4", "resource": "../scripts/publish-packages.sh"}, {"id": "source5", "resource": "../scripts/windows-integration-test.sh"}, {"id": "site-tests", "resource": "../scripts/test_check_docs_site.py"}, {"id": "release-tests", "resource": "../scripts/test_publish_packages.py"}, {"id": "consumer-tests", "resource": "../scripts/test_check_linux_consumer.py"}, {"id": "maintenance-ci", "resource": "../.github/workflows/docs.yml"}, {"id": "linux-dev", "resource": "../quick_blue_linux/pubspec.yaml"}, {"id": "linux-generator", "resource": "../quick_blue_linux/ffigen.yaml"}]
---

# Verify repository changes

Run commands from the repository root unless a subshell below changes directory.
CI keeps the primary Flutter `3.47.6` pin and separately exercises the declared
minimum Flutter `3.44.2` / Dart `3.12.2` with fresh resolution, root analysis and
all six package test suites. The verification step uses an isolated pub cache and no
Flutter action cache; it proves Dart compatibility, not native or BLE behavior.

To reproduce locally, select an isolated Flutter `3.44.2` SDK (do not replace the
host SDK), then run:

```sh
export PATH="/absolute/path/to/flutter-3.44.2/bin:$PATH"
export PUB_CACHE="$PWD/.dart_tool/pub-cache-minimum"
flutter --version
flutter pub get
flutter pub deps --json
flutter analyze
for package in quick_blue quick_blue/example quick_blue_darwin quick_blue_linux quick_blue_platform_interface quick_blue_windows; do
  (cd "$package" && flutter test) || exit
done
```

Linux's development-only ffigen pin is `21.0.0`: version `22.0.0` pulls
`code_assets ^2.0.0` / `hooks ^2.2.0` / `record_use ^1.0.0`, requiring
`meta ^1.19.0`, while Flutter `3.44.2` pins `meta 1.18.0`. The minimum remains
unchanged; no runtime dependency or generated binding is changed. On Fedora,
regenerate with `dart run ffigen --config ffigen.yaml --compiler-opts
'-I/usr/lib/clang/22/include'` inside `quick_blue_linux` when libclang's bundled
resource headers are not found automatically. This host-specific include path
is not a portable default. Dependency resolution is time-dependent because the
workspace lockfile is ignored; retain the dependency snapshot with test evidence.

## Select checks

Choose the narrowest check that proves the change, then broaden for shared or
platform-specific surfaces. Prose-only changes use the full
[documentation validation chain](maintenance.md#validation-commands) and source
review; they do not require hardware execution. Platform implementation changes
require affected package tests plus a matching platform build or smoke test when
available. Use platform builds or the example app for Android, iOS, macOS,
Windows and Linux behavior that unit tests cannot cover.

## Fast checks

```sh
flutter pub get
flutter analyze
(cd quick_blue_platform_interface && flutter test)
git diff --check
```

Format touched, non-generated Dart files with `dart format`. Do not format generated
bindings; update them only through the owning generator. The CI format gate excludes generated
Dart bindings. Run `flutter analyze` and `flutter test` in affected packages:
`quick_blue`, `quick_blue_platform_interface`, `quick_blue_darwin`,
`quick_blue_linux`, `quick_blue_windows`, and `quick_blue/example`.
Shared API/model changes require platform-interface and affected facade tests.
Example changes require `(cd quick_blue/example && flutter analyze && flutter test)`.

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

## Bond-wait timeout reproduction

`evidence/bond-wait-baseline-regression.dart.txt` is executable regression
source, not an execution log. In a disposable checkout, copy it into the owning
package so its relative fake-platform import resolves:

```sh
cp evidence/bond-wait-baseline-regression.dart.txt \
  quick_blue_platform_interface/test/bond_wait_external_timeout_test.dart
(cd quick_blue_platform_interface && flutter test \
  test/bond_wait_external_timeout_test.dart --reporter expanded)
```

This deliberately checks that external `Future.timeout` releases the underlying
bond observer and is expected to fail: timing out the wrapper future does not
cancel observation. Use the built-in `waitForBondState(timeout: ...)` or
cancellation token instead; `test/bond_state_wait_test.dart` exercises their
cleanup. Neither path cancels OS pairing. Do not add this failing reproduction
to the normal package suite.

## Dart adapter contracts

Run the checked-in parameterized wrapper harness and Linux fake-dependency
cases from the repository root:

```sh
for package in quick_blue quick_blue_darwin quick_blue_windows quick_blue_linux; do
  (cd "$package" && flutter test test/adapter_contract_test.dart --reporter expanded)
done
(cd quick_blue_windows && flutter test ../evidence/adapter-contracts/windows-read-boundary/read_boundary_test.dart --reporter expanded)
```

The package suites automatically discover the adapter contract tests.
The extra Windows boundary test requires the explicit command above.
Cases cover read/event ordering, service identity, typed errors,
notification claim setup/teardown, capability gates, legacy service-less routing
and snapshot-bound submission. Shared fixtures exist only for matching Dart
wrapper contracts; Linux uses fake BlueZ/lease dependencies.

Windows exposes a void host read and inherits event-only fallback: an early
matching notification can satisfy the read, while a wrong-service event cannot,
even after host success. This is characterization, not direct-result correlation
proof or a native/schema repair. Linux service-less lookup deliberately rejects
ambiguous native routing, and Linux setup-error coverage does not assert stream
done settlement. Harness teardown releases owned subscriptions/claims; it does
not prove a public plugin-wide dispose API.

The executable specifications are `test/adapter_contract_test.dart` in each
package and the shared wrapper fixture
`quick_blue/test/test_support/adapter_contract_harness.dart`.
The harness is verification-only; notification settlement and Darwin L2CAP
corrections are separately scoped dependencies, not fixes made by these tests.
Fake messengers and fake BlueZ establish Dart translation/event contracts only:
not real D-Bus, native ordering, Apple/WinRT runtime or BLE hardware behavior.

## Native and generated boundaries

| Change | Check |
| --- | --- |
| Pigeon schema | Run `dart run pigeon --input pigeons/messages.dart` inside each changed owning package; inspect generated diff |
| Darwin source | `./quick_blue_darwin/darwin/quick_blue_darwin/type_check/run.sh` |
| Darwin ownership/restoration helpers | `swift test` inside the corresponding `connection_ownership` / `restoration_summary` directories |
| Android Kotlin | `(cd quick_blue/example/android && ./gradlew :quick_blue:testDebugUnitTest)` |
| Windows ownership | Native CMake/CTest target on Windows (CI `build-windows`) |
| Linux external Git consumers | `python3 scripts/check-linux-consumer.py` (isolated consumers, initially empty Pub caches; requires Flutter Linux tools, Git and Pub network access, not BLE hardware) |
| Release metadata | `scripts/publish-packages.sh --dry-run`; CI also checks the current-version changelog heading |
| Documentation | [Maintenance checks](maintenance.md), source review, and site build when configured |

Darwin's Linux type-check harness uses signature-faithful stubs; it does not prove
CoreBluetooth behavior on hardware. Pigeon schemas are the source of truth;
regenerate outputs after schema changes, keep channel/API changes aligned across
Dart and native bindings, and inspect the resulting `git diff`. Inspection is
allowed; hand-editing generated `messages.g.*` files is not.

Each source is `pigeons/messages.dart` relative to its owning package:

| Owning package | Generated outputs (package-relative) |
| --- | --- |
| `quick_blue` | `lib/src/messages.g.dart`, `android/src/main/kotlin/com/example/quick_blue/Messages.g.kt` |
| `quick_blue_darwin` | `lib/src/messages.g.dart`, `darwin/quick_blue_darwin/Sources/quick_blue_darwin/Messages.g.swift` |
| `quick_blue_windows` | `lib/src/messages.g.dart`, `windows/messages.g.h`, `windows/messages.g.cpp` |

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

Tests need Bluetooth permission, powered-on hardware and nearby advertisements
or explicit smoke-test defines. Supply [test defines](example-options.md) for a known device. An advertisement-only
profile does not satisfy GATT verification. Writes are opt-in and require a safe
peripheral command. Missing Bluetooth on a supported smoke target must fail.

The smoke test skips unsupported platforms and an empty candidate set (even with
explicit target inputs). With candidates, exhausted flows fail for an explicit
target (device/name/profile/service expectations or write request), but skip for
untargeted discovery. See `quick_blue/example/integration_test/ble_smoke_test.dart`
lines 80–127 and 184–199 for exact target criteria.
A skip is not verification; inspect executed scenarios, not just the exit code.

Physical-device multi-engine recipes (replace placeholders):

```sh
flutter test integration_test/android_multi_engine_test.dart -d ANDROID_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_ID'
flutter test integration_test/ios_multi_engine_test.dart -d IOS_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID='SERVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'
```

For the advertisement-only recipe and switching, stress and benchmark
selection, see [example workflows](example-app.md). Focused UI and benchmark
recipes from `quick_blue/example` (replace placeholders):

```sh
flutter test integration_test/ble_ui_switch_test.dart -d macos
flutter test integration_test/ble_characteristic_benchmark_test.dart -d macos \
  --dart-define=QUICK_BLUE_BENCHMARK_DEVICE_ID='DEVICE_ID' \
  --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID='SERVICE_UUID' \
  --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'
```

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

The watchdog assertions characterize
non-yielding send/receive loops, versus zero-send's responsive but non-completing
retry loop. SIGKILL is **failure characterization, never successful operation or
channel cleanup**: live allocations/fake fds in the last snapshot remain owned
until process termination, which does not execute channel finalizers. These tests
and the example build prove scripted control flow and compilation only, not a
working L2CAP peripheral, real syscalls, MTU negotiation or native readiness.

## Report evidence, not assumptions

CI selects readiness checks for `**/CHANGELOG.md` and release pubspec changes.
Documentation validation, maintenance-tool tests and the clean site build belong
to the Documentation workflow and its explicit path filters. Hosted iOS/macOS/Windows
builds explicitly disabled by `SKIP_HOSTED_PLATFORM_BUILDS` remain unverified.

Record the exact command, revision, host/device, executed scenarios, result and
any skips. If blocked, state the command attempted, the concrete blocker, and
what remains unverified. Unit mocks, stubs and CI builds do not replace a hardware
run. [Limitations](limitations.md) tracks known verification gaps.

### Store reproducibility separately from raw execution records

Keep regression tests, reusable fixtures, reproduction scripts/harnesses and
concise behavior/proof-boundary documentation in Git. Store raw test/build/analyzer
logs, red/green transcripts, screenshots, generated reports, evidence archives and
machine-specific dumps in durable Kanban attachments or CI artifacts, not Git.
Scratch paths alone are not preservation. Exceptions require justified executable
test inputs or curated stable baselines, not an unfiltered execution dump.

Before removing existing tracked raw evidence, archive the originals durably,
read the stored attachment/artifact back and verify its hashes against the originals.
Keep artifact identifiers and concise provenance in the handoff. Preserve historical
completion records and useful running work. Storage location never relaxes tests,
acceptance criteria, hardware verification or publication proof boundaries.
