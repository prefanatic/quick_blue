---
type: "Reference"
title: "Known boundaries and pitfalls"
description: "Distinguish implemented support from runtime readiness and hardware evidence."
tags: ["limitations", "platforms"]

sources: [{"id": "source1", "resource": "../quick_blue_linux/lib/quick_blue_linux.dart"}, {"id": "source2", "resource": "../quick_blue_windows/lib/src/quick_blue_windows.dart"}, {"id": "source3", "resource": "../quick_blue_darwin/test/quick_blue_darwin_test.dart"}, {"id": "source4", "resource": "../quick_blue/example/integration_test/android_multi_engine_test.dart"}, {"id": "source5", "resource": "../quick_blue/example/integration_test/ios_multi_engine_test.dart"}]
---

# Known boundaries and pitfalls

| Symptom / assumption | What to do instead |
| --- | --- |
| A capability flag guarantees success | Check permissions, power and runtime errors too |
| Linux L2CAP flag checks native libraries | It is hard-coded true; install `libbluetooth.so.3`, handle open failure |
| Windows state stream monitors power continuously | It currently emits an availability snapshot only |
| Linux supports requested/readable MTU | `requestMtu` is unsupported here |
| Any connected lookup works without UUIDs | Darwin requires service UUIDs |
| Future timeout aborts Bluetooth work | Explicitly detach/clean up before retrying |
| A valid GATT snapshot remains valid forever | Rediscover after service change; old snapshots are invalid |
| Chunked writes implement long-write/reassembly | Choose your own framing and acknowledgement protocol |
| Shared engines share Dart objects | Recreate local handles/subscriptions and coordinate handoff |
| Persistent restoration can precede accessory picker | Choose one startup flow; the picker must run first |

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
  Future corrective tests must require explicit settlement for dropped clients
  and prove stale callbacks cannot settle replacement work at the identity gate
  (instrumented) or a future identity-aware queue boundary. These are criteria,
  not implemented fixes or a timer-based recovery policy. The start-throw path
  remains untested: JVM `android.util.Log.e` is not mocked; covering it requires
  separately coordinated injectable logging or Android test configuration.

Do not add platform guarantees based on another platform's tests. Report hardware
or host unavailability explicitly. Android bounded disconnect reconciliation is
not a cross-platform promise.

See [capabilities](capabilities.md), [startup](darwin.md), [GATT](gatt.md), and
[verification](testing.md) for the actionable paths.
