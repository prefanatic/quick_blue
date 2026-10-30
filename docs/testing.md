---
type: "Playbook"
title: "Verify repository changes"
description: "Select package, native and hardware checks and record precise evidence."
tags: ["development", "testing", "ci"]

sources: [{"id": "source1", "resource": "../.github/workflows/ci.yml"}, {"id": "source2", "resource": "../AGENTS.md"}, {"id": "source3", "resource": "../CONTRIBUTING.md"}, {"id": "source4", "resource": "../scripts/publish-packages.sh"}, {"id": "source5", "resource": "../scripts/windows-integration-test.sh"}, {"id": "site-tests", "resource": "../scripts/test_check_docs_site.py"}, {"id": "release-tests", "resource": "../scripts/test_publish_packages.py"}, {"id": "consumer-tests", "resource": "../scripts/test_check_linux_consumer.py"}, {"id": "maintenance-ci", "resource": "../.github/workflows/docs.yml"}, {"id": "linux-dev", "resource": "../quick_blue_linux/pubspec.yaml"}, {"id": "linux-generator", "resource": "../quick_blue_linux/ffigen.yaml"}]
---

# Verify repository changes

Run commands from the repository root unless a subshell below changes directory.
CI pins the primary and declared-minimum Flutter lanes to stable `3.47.7`
(framework `abaf9c523780a608bd46686fd5e53740a07077f8`, bundled Dart `3.13.5`).
The minimum lane independently uses fresh resolution, root analysis and
all six package test suites. The verification step uses an isolated pub cache and no
Flutter action cache; it proves Dart compatibility, not native or BLE behavior.

To reproduce locally, select an isolated Flutter `3.47.7` SDK (do not replace the
host SDK), then run:

```sh
export PATH="/absolute/path/to/flutter-3.47.7/bin:$PATH"
export PUB_CACHE="$PWD/.dart_tool/pub-cache-minimum"
flutter --version
flutter pub get
flutter pub deps --json
flutter analyze
for package in quick_blue quick_blue/example quick_blue_darwin quick_blue_linux quick_blue_platform_interface quick_blue_windows; do
  (cd "$package" && flutter test) || exit
done
```


Older Flutter versions are no longer supported. Keep both CI pins and Flutter
package constraints aligned when advancing this floor; standalone Dart 3.13
acceptance remains separate and must not gain a Flutter SDK dependency.
`scripts/test_flutter_support_policy.py` checks that both CI pins, Flutter package
floors and the external Flutter consumer recipe agree, and that standalone
package environments remain Flutter-free. It does not execute either SDK.
Linux's development-only ffigen pin remains `21.0.0` for reproducible generation;
no runtime dependency or generated binding is changed. On Fedora,

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

## Standalone package boundary

With a separately installed Dart 3.13 SDK, run:

```sh
python3 scripts/check-headless-consumer.py --dart /absolute/dart-sdk/bin/dart --flutter
```

The script retains an external matched-source fixture and fresh pub caches,
checks consumer graph roots and every resolved manifest for Flutter SDK
dependencies/constraints, saves exact dependency versions, then runs `dart
analyze` and `dart test` in isolated core, platform-interface and Linux copies.
`--flutter` additionally builds external Flutter consumers and verifies generated
Linux registration; omit it on a host without Flutter. It makes no source Git
commits, no pub-cache edits and no Bluetooth calls. Pure fake-clock tests retain
timer cleanup checks, while native `PlatformException` coverage stays in
`quick_blue/test/native_failure_reason_test.dart`. These are dependency/API and
translation checks, not hardware proof. The existing external Git-consumer CI
check remains separate and includes core at the same snapshot revision.

## ARM64 build and controlled runtime

The reproducible verifier is `scripts/check-arm64-consumer.py`;
its hermetic argv tests are `scripts/test_check_arm64_consumer.py`.

After the standalone verifier prints its retained fixture path, use the same
standalone SDK and its external `cli/` directory:

```sh
python3 scripts/check-arm64-consumer.py --dart /absolute/dart-sdk/bin/dart \
  --cli /absolute/retained-fixture/cli
```

This runs `dart compile exe --target-os=linux --target-arch=arm64` for the
operator CLI, fake flow and a loader-only FFI probe, then checks `file` and
`readelf -h -l -d`. It records `build/arm64-result.json`. Cross-build mode
explicitly records runtime as not executed. To exercise the artifacts without
radio access, additionally pass `--qemu /absolute/qemu-aarch64 --sysroot
/absolute/arm64-sysroot`. Provision these separately from trusted distribution
packages, retaining package versions and hashes. The sysroot must contain
`/lib/ld-linux-aarch64.so.1`, ARM64 glibc and its dependencies, and optional
`libbluetooth.so.3`; a merged-/usr distribution also needs its `/lib` link.
The script removes display and host loader variables and supplies guest library
search paths. It runs help, the fake flow and a glibc/libbluetooth symbol probe.
No Bluetooth socket, agent or system bus is opened by those runtime checks.

For a reproducible emulator environment, use Dart 3.13.5, QEMU 10.0.13 and
Debian 13 ARM64 libraries. Emulator checks do not establish compatibility with
other distributions or physical hardware. Retain source hashes, package versions, ELF dependencies
and execution logs as CI or review artifacts. See
[ARM64 runtime requirements](platform-setup.md#arm64-linux-runtime) and
[hardware boundaries](limitations.md#headless-proof-boundaries).

## Fast checks

The standalone verifier also copies `quick_blue_linux/example` into an external
CLI fixture, checks its transitive manifests, analyzes/tests, compiles
`bin/main.dart` and `bin/fake_flow.dart`, and runs both without DISPLAY or
WAYLAND_DISPLAY (`--help` for the real CLI). The fake flow asserts operator
selection, advertisement/service-data retention, explicit pairing/write,
notification cancellation and final disconnect/close. CLI tests reject malformed
options before initialization and cover scan/security/pair/cleanup errors and
stop signals. Linux `test/pairing_failure_test.dart` injects rejected,
failed/canceled authentication and no-agent-style D-Bus errors through public
pairing. Neither check contacts hardware or provisions an agent. Run
[service-account/agent recipes](pairing.md#headless-linux-agent-lifecycle) only
with the intended host/peripheral authorization; documentation recipes are not
executed proof. ARM64 build/runtime and physical hardware remain separate.

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
site build. Tests cover OKF structure, site links, release metadata and consumer
construction. Headless graph/manifest tests reject Flutter SDK constraints,
mixed repository snapshots and workspace roots while permitting plugin metadata.
The external Git-consumer check isolates Flutter template bootstrap in a separate
Pub cache, since a cold SDK can populate it even for `flutter create --no-pub`.
The actual consumer cache must still be empty immediately before `pub get`;
fixtures model template-cache writes and continue rejecting a dirty consumer cache.
Site fixtures run the copied

validator in normal and optimized subprocesses, checking navigation coverage and
duplicates, rendered pages, anchors, missing targets, absolute/encoded project
prefix escapes, resolved dot-segment/encoded/relative traversal, file and directory
symlink escapes (where supported), valid parent-relative links and search assets.
Release fixtures check version/constraint drift,
malformed version values, dependency membership and usage errors before a logging
Dart stand-in can run.

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

## Native and generated boundaries

The external Git-consumer check (`python3 scripts/check-linux-consumer.py`)
isolates Flutter template bootstrap in a separate Pub cache: a cold SDK can
populate it even with `flutter create --no-pub`. The consumer cache must remain
empty immediately before dependency resolution; fixtures also reject a dirty
consumer cache. Each external consumer is analyzed and built for Linux.

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

Web uses a direct user-gesture chooser, not the native scan smoke. Run
`(cd quick_blue_web && flutter test --platform chrome)` for deterministic JS
interop simulation, then build and exercise the separate
[browser hardware entry point](web.md#safe-real-hardware-loop). Simulator tests,
browser builds and exported real-radio stage results are distinct evidence.
Missing hardware or expected payloads are BLOCKED, not successful skips.

The browser hardware UI also has Chrome-only validation regressions:

```sh
(cd quick_blue/example && flutter test test/web_hardware_ui_test.dart \
  --platform chrome --dart-define=QUICK_BLUE_SOURCE_SHA=ui-test-fixture)
```

These prove read-only defaults and blocked missing-profile/API outcomes, not
physical peripheral behavior. The six native/example suites above do not run
the web backend's browser-only contracts.

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
The `Libc`/`LibBluetooth` wrappers supply scripted calls. The counting
allocator delegates to real zeroed allocations; fd counts describe fake ownership,
not kernel descriptors.

The [parent watchdog](https://github.com/prefanatic/quick_blue/blob/master/quick_blue_linux/test/l2cap_harness_test.dart) launches
separate Dart processes for persistent first-chunk EINVAL, send/recv EINTR,
always-readable receive and zero-byte send. It waits at most 15 seconds for the
armed record, observes for 500 ms, then sends SIGKILL and waits at most five seconds
for process exit/reaping. Cleanup also kills/reaps on assertion/startup failure.
JSON records include the actual exit code, elapsed time, syscall/ownership counters,
main-isolate heartbeat and an independent reporter-isolate heartbeat. Do not run
the child runner directly: its non-yielding cases cannot be stopped by Dart timers.
The pure-Dart tests locate the package or workspace Pub configuration for child
processes, so the same watchdog runs in both workspace and isolated package checks.
Standalone tests reuse their running Dart executable even when its SDK is absent
from `PATH`; Flutter's test runner uses the Flutter toolchain's `dart` on `PATH`.
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

### Linux deterministic lifecycle matrix

These are checked-in regression assertions, not a record of a run on a particular
revision. Record actual commands, revision and results separately.

Run `dart test` in the isolated Linux copy created by the standalone consumer
check. `test/lifecycle_cleanup_test.dart` covers caller cancellation before
start, during lease acquisition and during native connect, delayed completion,
retry, permission denial, failed connect, acquired setup cleanup and double
close. `test/gatt_session_test.dart` covers failed/cleared discovery, retry,
stale opt-in bound handles rejecting before IO, late notification setup and
final-listener cleanup and overlapping retired-setup/retry claim ordering.
Delayed client StopNotify cleanup also serializes with clear/retry, including
native stop failures, so a retired release cannot disable the retry claim.
`test/notification_reconfiguration_test.dart` holds a second StartNotify through
public disconnect, with AlreadyExists/success/error replies and both replacement
orders; it asserts native claim release while a peer's claim and connection remain.
`test/notification_target_replacement_test.dart` replaces a characteristic with
the same UUID after cache invalidation. Settled/held setup, setup failure and
obsolete-target stop errors check actual current/old native ownership and public
disconnect completion while a peer retains the connection. Confirmation failure
also releases acquired ownership before any disconnect request; same-target controls
retain stable ownership through local watch replacement.
`test/notification_native_proxy_test.dart` uses real BlueZ characteristic/object
wrappers over a controlled D-Bus method boundary: same wrapper, fresh wrappers
over one object, and recreated objects at one path. It checks the native claim
at successful setup completion, confirmation after retirement, held confirmation
and failure, stop errors with side effects, and public disconnect ordering while
peer ownership remains. These are deterministic dispatch tests, not real bus or
hardware verification.
`test/scan_session_test.dart` checks failed-stop retries against the original
adapter and serialized old-stop/new-start, adapter replacement, pending-start/stop
and duplicate-stop orderings. Shared interface
`test/snapshot_security_retry_test.dart` invalidates bound handles during held
security recovery for read/write/notification operations and retains direct-ID
and still-valid recovery controls.
Adapter tests cover the same remote address on multiple adapters without foreign
native connect submissions. `test/adapter_lease_test.dart` integrates the real
D-Bus lease with fake bus/BlueZ clients: different adapters disconnect independently,
default clients retain the leased native device across cache replacement on
disconnect and close, failed detach preserves that target for retry, and
spontaneous release allows retry on a replacement without stale property events
detaching its ownership. Default/explicit clients on one adapter share final-owner
cleanup, and failed connect releases only its own lease. The late-unlock matrix
combines native disconnect events during pending teardown, successful and failed
unlock replies, cache replacement and public platform/facade retries. A no-event
failed-unlock case verifies facade retry completes rather than silently pending.
Five-second watchdogs and completion markers bound these integrated scenarios;
the independent adapter's connection and final lease cleanup are asserted.
Failed-cleanup/reconnect tests additionally assert the actual D-Bus Client name
is restored before success, same-adapter peer disconnect and close leave the
reconnected owner live, and final cleanup leaves no names. Controlled ownership
tests verify pending reattach cannot report success early and a failed reattach
remains retryable with the original identity.
`test/reattach_transition_test.dart` extends this to delayed native disconnect
events during pending Client-registration and final-unlock replies, peer
disconnect/close, duplicate initial and retry connects, registration rejection,
transport errors before/after name acquisition, and native-connect suspension.
Pending replies cannot report success; error paths remain retryable and successful
cleanup leaves no Client/Lock names. Ownership tests invoke detach synchronously
and in a microtask inside lease registration, checking same-client serialization,
intervening teardown and original-identity restoration without a waiter cycle.
The five-second scenario watchdog is a test bound, not a production abort timeout.
`test/src/connection_lease_test.dart` records shared
D-Bus owners and last-client serialization; adapter tests retain first-powered
defaults and missing/unpowered/removed explicit selections. Watchdogs bound
pending regression futures. None of these tests accesses Bluetooth hardware.

### Archive existing raw evidence before removal

Before removing existing tracked raw evidence, archive the originals durably,
read the stored attachment/artifact back and verify its hashes against the originals.
Keep artifact identifiers and concise provenance in the handoff. Preserve historical
completion records and useful running work. Storage location never relaxes tests,
acceptance criteria, hardware verification or publication proof boundaries.
