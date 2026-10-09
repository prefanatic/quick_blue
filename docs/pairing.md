---
type: "Reference"
title: "Pairing and security failures"
description: "Gate bonding APIs and handle coordinated security recovery without blind retries."
tags: ["security", "bonding", "errors"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/quick_blue_exception.dart"}, {"id": "source3", "resource": "../quick_blue/lib/src/android_security_recovery.dart"}, {"id": "source4", "resource": "../quick_blue_platform_interface/test/bluetooth_device_connection_test.dart"}, {"id": "bondWaitTests", "resource": "../quick_blue_platform_interface/test/bond_state_wait_test.dart"}]
---

# Pairing and security failures

## Pair deliberately

Android exposes query, pair and bond events. Linux exposes query and pair, but
not live bond events. Darwin and Windows do not expose app-initiated pairing.
CoreBluetooth can prompt when a protected attribute is accessed.

Dart fragment in an async function with a BluetoothDevice `device`:

```dart
final capabilities = await QuickBlue.capabilities();
if (capabilities.supportsPairing &&
    await device.bondState() != BluetoothBondState.bonded) {
  await device.pair();
}
if (capabilities.supportsBondStateChanges) {
  await device.waitForBondState(
    BluetoothBondState.bonded,
    timeout: const Duration(seconds: 30),
  );
}
```

`waitForBondState` subscribes before reading the current state, avoiding a
snapshot/event race.[^source1] Without live events (Linux), it can return an already
matching snapshot but cannot be relied on to observe a future transition. Gate
it with `supportsBondStateChanges` and supply the built-in `timeout` option.

Device and static `QuickBlue.waitForBondState` APIs accept `timeout` and
`cancellationToken: QuickBlueCancellationToken()`. The deadline covers the
snapshot read as well as the event wait. Timeout throws `TimeoutException`;
cancellation throws `QuickBlueException` with code `cancelled` and failure reason
`callerCancelled`. A pre-cancelled token or negative timeout fails before
subscribing or querying. Omitted options retain an unbounded wait.

Cancellation fragment in an async function; retain the token for a separate
UI stop action, which calls `cancellation.cancel()`:

```dart
final cancellation = QuickBlueCancellationToken();
try {
  await device.waitForBondState(
    BluetoothBondState.bonded,
    timeout: const Duration(seconds: 30),
    cancellationToken: cancellation,
  );
} on TimeoutException {
  // The observation deadline expired; OS pairing may still be active.
} on QuickBlueException catch (error) {
  if (error.code != QuickBlueErrorCode.cancelled) rethrow;
  // This caller stopped observing; OS pairing may still be active.
}
```

The fragment requires `dart:async` for `TimeoutException` and the
`package:quick_blue/quick_blue.dart` public API import. Use a new token for
each subsequent wait after cancellation.

Success, platform errors, timeout and cancellation release the caller's internal
event subscription, timer and token listener. Concurrent waits are independent:
stopping one does not stop another (a shared token intentionally cancels all
waits using it). These options stop Dart observation only; they never initiate,
modify, or cancel OS pairing. External `Future.timeout` composition does not
release the underlying wait's subscription. Deterministic observer tests prove
Dart cleanup, not native bonding or Android bond repair.[^bondWaitTests]

## Automatic recovery is bounded

Normal managed connect, read, notification setup and acknowledged-write paths
coordinate one security recovery per device, then retry a rejected operation
once after successful recovery. Android first observes implicit bonding for a
bounded period before attempting explicit bonding; calling `pair()` preemptively
is not required for a protected GATT access.

Do not blindly replay writes for arbitrary transport failures. The security retry
contract concerns a write rejected before application, not proof that a timed-out
write had no side effects.

## Preserve structured diagnostics

Dart error-handling fragment:

```dart
try {
  await device.readValue(serviceId, characteristicId);
} on QuickBlueSecurityException catch (error) {
  if (error.recoveryResult ==
      QuickBlueSecurityRecoveryResult.userActionRequired) {
    // Show actionable system-settings guidance; do not loop indefinitely.
  }
} on QuickBlueGattException catch (error) {
  print('native GATT status: ${error.status}');
}
```

Security errors expose `reason`, `nativeDomain`, `nativeCode`, and `recoveryResult`.
Android non-security GATT failures preserve their numeric `status`, including
vendor values. Connection events can carry an `error` too. Portable
`QuickBlueException.code` values include `unsupported`, `unavailable`,
`invalidState`, `deviceBusy`, `operationFailed`, `notFound`, `ambiguous`, `cancelled`.

See [capabilities](capabilities.md) and [observability privacy](observability.md).

[^source1]: Bond-state wait and pairing handle contract.
[^bondWaitTests]: Fake-clock deadlines, cancellation, races and independent observers.
