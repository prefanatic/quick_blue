---
type: "Reference"
title: "Connection lifetimes and retries"
description: "Choose one-shot or subscription-owned connections and handle overlapping operations."
tags: ["connections", "lifecycle"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/managed_connection_lifecycle.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/test/bluetooth_device_connection_test.dart"}, {"id": "source4", "resource": "../quick_blue/android/src/main/kotlin/com/example/quick_blue/AndroidGattBroker.kt"}, {"id": "linux-gatt", "resource": "../quick_blue_linux_dart/lib/src/gatt_session.dart"}, {"id": "linux-gatt-tests", "resource": "../quick_blue_linux_dart/test/gatt_session_test.dart"}]
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
remains outstanding until platform completion or engine disposal. Negative
timeouts fail before work starts; zero follows Dart timer/event-loop ordering.
Timers and token listeners are removed when each caller's wait settles.

Expiration only stops that caller's wait. A late successful connect can still
attach this engine, and cancelling a wait cannot undo a disconnect already
requested. Retries join the outstanding operation rather than starting work
that could consume an old native callback. Late completion retires shared work;
late errors are consumed even if every caller has left. If a callback never
arrives, one operation per device/kind remains quarantined. Each caller can
still set its own deadline; there is no portable abort/reset for pending MTU
work. Managed-connection policy and deprecated static helpers do not acquire
these device-method wait options.

Identical MTU requests share work; a different requested value is rejected while
negotiation is pending. Disconnect or GATT invalidation resets discovery, but
does not provide a portable reset for MTU negotiation.

| Overlap for the same device | Result |
| --- | --- |
| Disconnect during connect | Supersedes connect; old future gets `cancelled` |
| Connect during pending disconnect | Supersedes disconnect; old future gets `cancelled` |
| Same-kind pending connect/disconnect | Callers share outstanding work with independent deadlines |
| Different devices | May connect concurrently |

Service discoveries coalesce; disconnect cancels pending discovery. Android
additionally bounds final-client teardown and ignores retired-GATT callbacks;
this disconnect reconciliation guarantee is Android-specific.[^source4]
Linux clear cancels its pending discovery waiter and prevents old resolution
from emitting into a replacement discovery. The
[fake-BlueZ characterization](limitations.md#linux-gatt-teardown-characterization)
distinguishes the historical gap from current regression behavior. Facade caller
cancellation alone still does not prove submitted native-session work stopped.

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

## Typed connection failures

Match `QuickBlueException.failureReason` rather than diagnostic text. Its nullable
`QuickBlueFailureReason` values distinguish `connectionFailed`, `callerCancelled`
and `remoteDisconnected`; a reason does not establish whether retrying is safe.

Connection attempts through the static, device and managed APIs classify failures
using operation context. Unexpected loss after an observed connection appears in
`BluetoothConnectionStateChange.error`, even when native status is success; the
original state and status are unchanged. A local disconnect is not a remote
failure. Superseded connection work and discovery cancelled by local disconnect
report `callerCancelled`. Database invalidation uses code `cancelled` without
claiming caller cancellation. Discovery interrupted by remote link loss retains
the remote reason and diagnostic cause in `details`.

Existing codes, messages, native GATT statuses, Darwin domains/codes and security
subclasses remain available. Raw native connection exceptions are wrapped with
`connectionFailed`, retaining the original exception in `details` and preserving
the Dart throw stack. Unknown causes do not acquire a reason from their text.

[^source4]: Android GATT broker disconnect reconciliation.

## Linux client shutdown

The [headless operator CLI](quickstart.md#headless-linux-operator-workflow) uses built-in
connect/discovery deadlines and a Ctrl-C cancellation token, cancels scans and
notifications, then attempts disconnect and Linux close in nested `finally`
blocks. Primary failures propagate while secondary cleanup failures are printed.
It does not treat caller cancellation as a native abort. Already submitted
pair/read/write/notification setup calls and teardown must settle before exit;
a stalled D-Bus call can delay it. The example is not a process supervisor or
an unlimited reconnecting service.

`QuickBlueLinux.close()` is Linux-owned and idempotent, not a portable facade
API. Cancel public scan, Bluetooth-state, notification and managed-connection
subscriptions and await outstanding requests first. Shutdown is not a native
request abort or a deadline for stalled BlueZ calls. It releases only this
client's owned connections under the last-client lease rule, scoped by actual
local adapter address plus remote device address, then property
watches and transports. Cleanup attempts continue after failures; the first
shutdown failure is thrown and secondary failures are logged. Initialization
failure releases acquired subscriptions/transport, preserves its primary error
and makes the instance unusable; construct a new instance rather than retrying
it. Source paths: `quick_blue_linux_dart/lib/quick_blue_linux_dart.dart` and
`quick_blue_linux_dart/test/lifecycle_cleanup_test.dart` (repository root-relative).

Caller cancellation still stops only that caller's wait. A connect completing
late retains the client lease until explicit disconnect; an immediate retry
without detach joins it. Explicit disconnect supersedes that pending connect.
A fresh reconnect after detach must reacquire actual membership and a native
target, not join a retired native Connect reply. Late success/error cannot alter
the replacement connection; this is lifetime retirement, not native abort.
A new explicit disconnect also retires a reconnect queued behind an earlier
teardown, even when both disconnects join that cleanup. A reconnect requested
after the new disconnect remains intentional; old native-event cleanup does not
retire it merely by joining the same teardown.
Linux exposes the entire explicit disconnect as pending before notification
release can suspend. A newer connect waits for StopNotify, lease detach and old
state/observer cleanup before selecting its native target and acquiring membership.
Native events during that release join the same transition. Only after GATT,
scan and native-observer cleanup settle is the old state deduplication cache
retired, so an earlier native event cannot suppress terminal state for a joining
facade disconnect. Completion remains ordered before a waiting newer connect.
Failed teardown remains
observable to waiting platform requests and retryable, not a successful reconnect.
See the [Linux ownership regression boundary](multi-engine.md#verification-boundary).
Clearing device state cancels pending discovery waits, and a late notification
setup releases its native claim without installing a watch. Notification setup
and disable requests for the same characteristic are serialized across clears:
a retry waits for retired native setup and cleanup before acquiring its claim,
so old cleanup cannot disable the new generation. A stalled native setup still
requires native completion; serialization is not an abort or deadline. Tests use
fake BlueZ clients; hardware disconnect and notification delivery remain untested.

Native notification claims survive replacement of their local property watch
and GATT cache invalidation. Disconnect's queued release still stops this client's
claim after an earlier reconfiguration succeeds or reports `AlreadyExists`;
a reconfiguration error does not discard the existing claim. After same-UUID
native endpoint replacement, successful setup records the new acquisition and
attempts to stop obsolete targets. Obsolete-target errors are logged and retained
for retry. Because different wrappers may alias the same native endpoint, setup
confirms the current claim after retirement before returning success; queued
disconnect waits for this confirmation, including its error path. Confirmation
can fail, attempting acquired-claim release before propagating the error, and is
not an atomic or uninterrupted native handoff. Failed stops remain
for retry, but do not block release of the current target. Independent clients
keep their native notification ownership and connection. See the controlled
[teardown cases](limitations.md#linux-gatt-teardown-characterization).
