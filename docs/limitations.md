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
| A bound handle proves native-side rejection | It is a Dart pre-submission guard; native or hardware rejection is not established |
| Chunked writes implement long-write/reassembly | Choose your own framing and acknowledgement protocol |
| Shared engines share Dart objects | Recreate local handles/subscriptions and coordinate handoff |
| Persistent restoration can precede accessory picker | Choose one startup flow; the picker must run first |

## Linux GATT teardown characterization

At production baseline `0596865a0a46e18f7dc6d56561a79f538cf7bcea`,
the three `characterization:` tests in
[`gatt_session_test.dart`](https://github.com/prefanatic/quick_blue/blob/2cce9eb00644c2a9daa60534791fc94a00fd7f8d/quick_blue_linux/test/gatt_session_test.dart)
pin observed gaps, not corrected behavior:

| Controlled ordering | Observed fake-BlueZ result |
| --- | --- |
| Pending `ServicesResolved`, then clear, replacement discovery, then old resolution | Old waiter survives clear; replacement completes first, then old resolution emits a second discovery and completion. |
| `StartNotify` suspended until client release and clear finish | Teardown makes zero `StopNotify` calls; resumed setup installs a watch and emits initial `[0]` and later `[6]`. Later client release also makes zero calls with its cache cleared. |
| Enable notifications, invalidate cache with `ServicesResolved=false`, then release and clear | Listener survives invalidation; release and clear make zero `StopNotify` calls and the fake stays notifying. Cache-intact control makes exactly one call and stops notifying. |

Run from the repository root:

```sh
(cd quick_blue_linux && flutter test test/gatt_session_test.dart \
  --plain-name 'characterization:' --reporter expanded)
```

The one-shot `FutureGate` observes setup entry before teardown and explicitly
releases it afterward; no sleep determines ordering. Replacement is a new fake
BlueZ object at the same address, not a physical reconnect. Passing assertions
preserve gaps, not safe teardown. Evidence proves reproducible fake-BlueZ
lifetime behavior only, not real BlueZ cleanup, D-Bus ownership release, or
hardware semantics. Production code is unchanged by these tests.

To fix these gaps, old resolution
must not emit into a replacement lifetime and must settle observably; late setup
must not revive watches/values and must balance acquired native ownership;
cache-invalidated final release must stop the old characteristic exactly once
and remove its listener without re-resolution. The current implementation does
not meet these requirements.

## Verification gaps

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
- Snapshot-bound submission guards and the disconnect/reconnect snapshot
  policy are covered by fake-platform Dart tests; native-side rejection and
  rollback behavior are not established.


Do not add platform guarantees based on another platform's tests. Report hardware
or host unavailability explicitly. Android bounded disconnect reconciliation is
not a cross-platform promise.

See [capabilities](capabilities.md), [startup](darwin.md), [GATT](gatt.md), and
[verification](testing.md) for the actionable paths.
