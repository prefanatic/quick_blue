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

The headless CLI (`quick_blue_linux/example/lib/cli.dart`, repository-relative) deliberately
overrides the public `performSecurityRecovery` hook to return
`userActionRequired`, not call Pair. Only the selected device's explicit
`--pair` flag initiates pairing in that example. This is an example policy,
not a change to normal core/Linux/Flutter recovery described below.

Normal managed connect, read, notification setup and acknowledged-write paths
coordinate one security recovery per device, then retry a rejected operation
once after successful recovery. Android first observes implicit bonding for a
bounded period before attempting explicit bonding; calling `pair()` preemptively
is not required for a protected GATT access.

Do not blindly replay writes for arbitrary transport failures. The security retry
contract concerns a write rejected before application, not proof that a timed-out
write had no side effects.

## Headless Linux agent lifecycle

Linux `pair()` delegates to BlueZ Device1.Pair and registers no agent or desktop
UI. According to the [BlueZ AgentManager contract](https://github.com/bluez/bluez/blob/master/doc/org.bluez.AgentManager.rst),
an application's registered agent handles its requests; otherwise BlueZ uses
the default agent. [Device1.Pair](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst)
fails when interaction is required but no suitable agent is available. Some
pairings need no interactive exchange, but NoInputNoOutput does not
guarantee that a protected peripheral will pair.

Provision a separate, operator-controlled agent process before invoking
`--pair`. Its D-Bus connection must remain alive for the complete exchange;
starting and immediately exiting `bluetoothctl` does not provision a persistent
agent. For an attended headless SSH maintenance session, an example interactive
sequence in a separate terminal is:

```text
bluetoothctl
agent KeyboardDisplay
default-agent
```

Verify agent registration/default-agent success and keep that session open while the CLI
pairs the selected device. Review the actual device address before entering a
passkey or approving a confirmation. Do not approve unexpected requests. Finish
with `agent off` and quit that session when maintenance ends. Choose a capability
matching actual input/output: DisplayOnly, DisplayYesNo, KeyboardOnly,
NoInputNoOutput or KeyboardDisplay. NoInputNoOutput trades away interactive
authentication and may be incompatible with the peer's security requirements.

RegisterAgent and RequestDefaultAgent are distinct; becoming default may need
additional authorization and affects requests from other applications without
their own agent. This is a host-wide trust/interaction surface, not a
per-device allowlist. An unattended agent must enforce an explicit authorized
device policy and handle rejection/cancellation securely; none is shipped by
this example. Never install an auto-accept-all default agent. Pairing and
BlueZ's Trusted property are different; the CLI does not set Trusted or remove
bonds. Repair stale credentials only through a separately authorized operator
procedure, never implicit RemoveDevice/re-pair.

Run the CLI and agent under explicitly authorized service identities with
[system-bus and BlueZ permissions](platform-setup.md#linux-service-account-permissions).
No desktop login, root execution or existing desktop agent is assumed.
AuthenticationRejected, AuthenticationFailed/AuthenticationCanceled and
missing-agent failures must reach the caller; inspect the native BlueZ name and
message rather than parsing them into success. The
Linux fake pairing regressions (`quick_blue_linux/test/pairing_failure_test.dart`)
preserve exact injected D-Bus errors and reject unrelated actions;
CLI regressions (`quick_blue_linux/example/test/cli_test.dart`) also verify
protected read/notify failures do not initiate hidden pairing or replay IO.
These tests do not exercise a real agent or peripheral authentication.

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
