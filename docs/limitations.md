---
type: "Reference"
title: "Known boundaries and pitfalls"
description: "Distinguish implemented support from runtime readiness and hardware evidence."
tags: ["limitations", "platforms"]

sources: [{"id": "source1", "resource": "../quick_blue_linux/lib/quick_blue_linux.dart"}, {"id": "source2", "resource": "../quick_blue_windows/lib/src/quick_blue_windows.dart"}, {"id": "source3", "resource": "../quick_blue_darwin/test/quick_blue_darwin_test.dart"}, {"id": "source4", "resource": "../quick_blue/example/integration_test/android_multi_engine_test.dart"}, {"id": "source5", "resource": "../quick_blue/example/integration_test/ios_multi_engine_test.dart"}, {"id": "gatt_tests", "resource": "../quick_blue_linux/test/gatt_session_test.dart"}, {"id": "gatt_session", "resource": "../quick_blue_linux/lib/src/gatt_session.dart"}, {"id": "gate", "resource": "../quick_blue_linux/test/test_support/future_gate.dart"}]
---

# Known boundaries and pitfalls

| Symptom / assumption | What to do instead |
| --- | --- |
| A capability flag guarantees success | Check permissions, power and runtime errors too |
| Linux L2CAP flag checks native libraries | It is hard-coded true; install `libbluetooth.so.3`, handle open failure |
| Windows state stream monitors power continuously | It currently emits an availability snapshot only |
| Linux supports requested/readable MTU | `requestMtu` is unsupported here |
| Any connected lookup works without UUIDs | Darwin requires service UUIDs |
| Future timeout aborts Bluetooth work | Explicitly detach/clean up before retrying; use built-in bond-wait options to release observation, not to cancel OS pairing |
| A valid GATT snapshot remains valid forever | Rediscover after service change; old snapshots are invalid |
| Chunked writes implement long-write/reassembly | Choose your own framing and acknowledgement protocol |
| Shared engines share Dart objects | Recreate local handles/subscriptions and coordinate handoff |
| Persistent restoration can precede accessory picker | Choose one startup flow; the picker must run first |

## Linux GATT teardown characterization

Linux teardown cancels pending discovery and retires late notification setup.
The regression and `characterization:` tests in
[`gatt_session_test.dart`](https://github.com/prefanatic/quick_blue/blob/master/quick_blue_linux/test/gatt_session_test.dart)
distinguish corrected lifetime behavior from the remaining gap with fake BlueZ objects:

| Controlled ordering | Observed fake-BlueZ result |
| --- | --- |
| Pending `ServicesResolved`, then clear, replacement discovery, then old resolution | Old discovery fails with `cancelled`; only replacement discovery emits completion, and the old property listener is removed. |
| `StartNotify` suspended until client release and clear finish | Resumed setup fails with `cancelled`, releases its late claim exactly once and installs no watch or value delivery. |
| Enable notifications, invalidate cache with `ServicesResolved=false`, then release and clear | Release and clear make zero `StopNotify` calls and the fake stays notifying, although clear removes its listener. Cache-intact control makes exactly one call and stops notifying. |

Run the current regression suite from the repository root:

```sh
(cd quick_blue_linux && flutter test test/gatt_session_test.dart --reporter expanded)
```


The one-shot `FutureGate` observes setup entry before teardown and explicitly
releases it afterward; no sleep determines ordering. Replacement is a new fake
BlueZ object at the same address, not a physical reconnect. Current regressions
require cleared discovery to fail with `cancelled` without replacement-lifetime
emissions, and late notification setup to release its claim without installing
a watch or delivering values. These corrections are part of the headless Linux
lifecycle implementation. Fake-BlueZ tests do not prove real BlueZ cleanup,
D-Bus ownership release or hardware semantics.

The cache-invalidated final-release gap remains characterized: release must
eventually stop the old characteristic exactly once and remove its listener
without re-resolution, but the current implementation still loses that native
release when its characteristic cache has already been cleared.


## Verification gaps

### Headless proof boundaries

The [external CLI fixture](install.md#operator-cli-fixture) compiles with
standalone Dart and starts `--help` with DISPLAY/WAYLAND_DISPLAY absent; help
does not contact BlueZ. The separately compiled fake flow uses public APIs,
asserts scan/selection/connect/discovery/read/explicit write/notify/cancel/
disconnect ordering and cleanup without a bus, engine, agent or radio.
Pairing and CLI tests use injected errors to check that failures reach callers
without automatic bond replacement or pairing with another device. They do not
test authentication. Real scanning, pairing, GATT delivery, service-account
permissions and physical Zero 2 W memory use/throughput remain untested.
ARM64 library loading can be checked separately with the
[QEMU verifier](testing.md#arm64-build-and-controlled-runtime); it does not test
radio or kernel behavior. The [publication metadata issue](install.md#publication-compatibility-limit)
also prevents a hosted release.

- Runtime BLE multi-engine suites exist for Android and iOS. Other ownership
  implementations have unit/native coverage, not equivalent runtime suites.
- AccessorySetupKit and Android companion association have Dart host-API mapping
  tests; those do not demonstrate the real system pickers on hardware.
- Linux scan-option forwarding has mocked filter/default tests; those do not
  verify adapter behavior for every native knob.
- Darwin type checking on Linux uses stubs and cannot verify platform runtime
  callbacks or background relaunch.
- Android queue characterization in
  `quick_blue/android/src/test/kotlin/com/example/quick_blue/GattQueueStallCharacterizationTest.kt`
  proves JVM state-machine behavior only: an accepted operation without a callback
  blocks later admission; teardown clears active/queued state; detached clients
  receive no settlement callback at admission or teardown. Resource-loss draining
  admits in FIFO order but dispatches disconnected callbacks in reverse order
  through recursive advancement. Queue completion returns an operation without
  delivering its success callback and has no GATT identity argument: bypassing
  the broker gate after reconnect returns the replacement operation for a
  same-kind late completion. The broker's `isCurrentGatt` checks in
  `quick_blue/android/src/main/kotlin/com/example/quick_blue/AndroidGattBroker.kt`
  are inspection-only evidence here, not an executed old-GATT callback test.
  A fix must settle dropped clients explicitly and include tests that
  prove stale callbacks cannot settle replacement work at the identity gate
  (instrumented) or an identity-aware queue boundary. These tests do not fix
  the gaps or add timer-based recovery. The start-throw path
  remains untested: JVM `android.util.Log.e` is not mocked; covering it requires
  injectable logging or Android test configuration.

Do not add platform guarantees based on another platform's tests. Report hardware
or host unavailability explicitly. Android bounded disconnect reconciliation is
not a cross-platform promise.

See [capabilities](capabilities.md), [startup](darwin.md), [GATT](gatt.md), and
[verification](testing.md) for the actionable paths.
