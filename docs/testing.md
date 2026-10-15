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
site build. The suite includes 13 OKF tests, 15 built-site tests, four release
metadata tests and five consumer-construction tests.
Seven additional headless graph/manifest tests reject Flutter SDK constraints,
mixed repository snapshots and workspace roots while permitting plugin metadata. Site fixtures run the copied
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

Run `dart test` in the isolated Linux copy created by the standalone consumer
check. `test/lifecycle_cleanup_test.dart` covers caller cancellation before
start, during lease acquisition and during native connect, delayed completion,
retry, permission denial, failed connect, acquired setup cleanup and double
close. `test/gatt_session_test.dart` covers failed/cleared discovery, retry,
stale opt-in bound handles rejecting before IO, late notification setup and
final-listener cleanup and overlapping retired-setup/retry claim ordering.
Delayed client StopNotify cleanup also serializes with clear/retry, including
native stop failures, so a retired release cannot disable the retry claim.
Adapter tests cover the same remote address on multiple adapters without foreign
native connect submissions. `test/src/connection_lease_test.dart` records shared
D-Bus owners and last-client serialization; adapter tests retain first-powered
defaults and missing/unpowered/removed explicit selections. Watchdogs bound
pending regression futures. None of these tests accesses Bluetooth hardware.

Before removing existing tracked raw evidence, archive the originals durably,
read the stored attachment/artifact back and verify its hashes against the originals.
Keep artifact identifiers and concise provenance in the handoff. Preserve historical
completion records and useful running work. Storage location never relaxes tests,
acceptance criteria, hardware verification or publication proof boundaries.
