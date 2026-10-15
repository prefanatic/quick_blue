---
type: "Reference"
title: "Connection lifetimes and retries"
description: "Choose one-shot or subscription-owned connections and handle overlapping operations."
tags: ["connections", "lifecycle"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/managed_connection_lifecycle.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/test/bluetooth_device_connection_test.dart"}, {"id": "source4", "resource": "../quick_blue/android/src/main/kotlin/com/example/quick_blue/AndroidGattBroker.kt"}]
---

# Connection lifetimes and retries

## One-shot ownership

`device.connect()` waits for a connected event; `disconnect()` detaches this
client. Device connect/disconnect, discovery and MTU methods accept caller-local
`timeout` and `cancellationToken` options. Neither stops native work or releases
ownership. Disconnect when abandoning a timed-out connection; an immediate retry
instead joins outstanding work.

Dart fragment with a BluetoothDevice `device`:

```dart
await device.connect(timeout: const Duration(seconds: 15));
```

`QuickBlueCancellationToken` is one-shot. Cancellation reports `cancelled` with
`failureReason: QuickBlueFailureReason.callerCancelled`; deadlines throw
`TimeoutException`. Without options waits are unbounded. MTU work with no callback
remains outstanding until platform completion or engine disposal.

| Overlap for the same device | Result |
| --- | --- |
| Disconnect during connect | Supersedes connect; old future gets `cancelled` |
| Connect during pending disconnect | Supersedes disconnect; old future gets `cancelled` |
| Same-kind pending connect/disconnect | Callers share outstanding work with independent deadlines |
| Different devices | May connect concurrently |

Service discoveries coalesce; disconnect cancels pending discovery. Android
additionally bounds final-client teardown and ignores retired-GATT callbacks;
this disconnect reconciliation guarantee is Android-specific.[^source4]

## Managed reconnection

Use this for a feature that should recover after an established link drops.
Dart fragment in an async scope; `device` is a BluetoothDevice:

```dart
final subscription = device.maintainConnection(
  policy: BluetoothReconnectionPolicy(
    maxAttempts: 5,
    initialDelay: const Duration(seconds: 1),
    maxDelay: const Duration(seconds: 20),
    backoffMultiplier: 2,
  ),
).listen(
  (change) => print(change.state),
  onError: (Object error) => print('connection ended: $error'),
);
// Cancel when the feature stops, not immediately after subscribing.
await subscription.cancel();
```

- Listening performs one initial attempt; initial failure ends the stream without
  entering the reconnection policy.
- After link loss, delays grow up to `maxDelay`. `maxAttempts` resets after each
  successful reconnect; `null` means retry until stopped.
- Exhaustion emits the final error and closes the stream.
- Cancellation or `device.disconnect()` stops retries and detaches this client.
- Only one managed connection owns a device per engine. Do not mix it with
  manual `connect()` calls for that device.

For cross-engine handoff, read [multi-engine ownership](multi-engine.md).

[^source4]: Android GATT broker disconnect reconciliation.

## Linux client shutdown

`QuickBlueLinux.close()` is Linux-owned and idempotent, not a portable facade
API. Cancel public scan, Bluetooth-state, notification and managed-connection
subscriptions and await outstanding requests first. Shutdown is not a native
request abort or a deadline for stalled BlueZ calls. It releases only this
client's owned connections under the last-client lease rule, then property
watches and transports. Cleanup attempts continue after failures; the first
shutdown failure is thrown and secondary failures are logged. Initialization
failure releases acquired subscriptions/transport, preserves its primary error
and makes the instance unusable; construct a new instance rather than retrying
it. Source paths: `quick_blue_linux/lib/quick_blue_linux.dart` and
`quick_blue_linux/test/lifecycle_cleanup_test.dart` (repository root-relative).

Caller cancellation still stops only that caller's wait. A connect completing
late retains the client lease until explicit disconnect; an immediate retry
joins it. Local fakes record native connect/disconnect calls and D-Bus owners.
Clearing device state cancels pending discovery waits, and a late notification
setup releases its native claim without installing a watch. Notification setup
and disable requests for the same characteristic are serialized across clears:
a retry waits for retired native setup and cleanup before acquiring its claim,
so old cleanup cannot disable the new generation. A stalled native setup still
requires native completion; serialization is not an abort or deadline. These are fake
contracts, not hardware disconnect or notification-delivery proof.
