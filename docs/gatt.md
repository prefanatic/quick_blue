---
type: "Reference"
title: "Discover, write and subscribe"
description: "Use valid GATT snapshots, opt-in snapshot-bound handles, explicit write framing and subscription-owned notifications."
tags: ["gatt", "notifications", "writes"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_gatt.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/test/bluetooth_gatt_test.dart"}, {"id": "routing", "resource": "../quick_blue_platform_interface/lib/src/characteristic_lifecycle.dart"}, {"id": "retained", "resource": "../quick_blue_platform_interface/test/retained_characteristic_value_stream_test.dart"}, {"id": "settlement", "resource": "../quick_blue_platform_interface/test/bluetooth_notifications_test.dart"}, {"id": "source4", "resource": "../quick_blue_platform_interface/test/snapshot_bound_characteristic_test.dart"}]
---

# Discover, write and subscribe

## Resolve a characteristic

Dart fragments below assume a connected `device`, real UUIDs, and `quick_blue.dart`
imported. Inspect `BluetoothService.characteristicDetails` for read/write/subscribe
support before performing an operation.

```dart
final gatt = await device.discoverGatt();
final characteristic = gatt.characteristic(characteristicId, service: serviceId);
final value = await characteristic.read();
```

Omit `service` only when the UUID identifies one characteristic across the snapshot.
Missing or duplicate UUIDs produce `notFound` or `ambiguous`, not an arbitrary pick.
`hasCharacteristic(uuid, service: ...)` is available for presence checks.

`gatt.characteristic(...)` returns an ID-only handle: snapshot validity is
checked when the handle is resolved, not when it is used later. To keep
checking validity at every new submission, resolve with
[boundCharacteristic](#opt-into-snapshot-bound-handles) instead.

## Notifications own their teardown

```dart
final notifications = characteristic.notifications().listen(
  (value) => print('received ${value.length} bytes'),
  onError: (Object error) => print('notifications failed: $error'),
);
// Keep listening while needed; cancellation releases the notification claim.
await notifications.cancel();
```

Concurrent listeners share native setup; the final listener disables it. Use
`valueStream` plus `setNotifiable(...)` only when setup/teardown must be managed
separately (listen before enabling).

A terminal setup failure emits one error followed by `done`, even when the
listener does not cancel on error. Values buffered while enabling are discarded
on failure. A new subscription can retry setup; the failed subscription has no
acquired claim to release. A conflicting notification/indication mode also
terminates only the rejected stream and leaves the active owner's claim intact.
[^routing][^settlement]

If you cancel while setup is pending, cancellation waits for setup to settle.
A late success releases that subscription's acquired claim exactly once; a late
failure releases no claim. Concurrent same-mode listeners still share setup,
and only the final owner disables updates. This does not abort native setup or
add a setup deadline: if setup never settles, cancellation can remain pending.
Controlled-future regressions prove this Dart stream/claim state machine, not
Bluetooth readiness or native/hardware notification delivery.[^routing][^settlement]

## Raw value streams are reusable

`characteristic.valueStream` is a broadcast stream for raw value updates. Retain
the returned stream if convenient: after cancelling its final subscription, you
can listen to that same stream again and receive newly arriving matching values.
Cancellation removes that listener's Dart routing interest, not the stream's
ability to be reused.[^routing]

This fragment assumes the connected `characteristic` above; native update
setup/teardown is managed separately:

```dart
final values = characteristic.valueStream;
final first = values.listen((value) => print('first: ${value.length} bytes'));
await first.cancel();
final resumed = values.listen((value) => print('resumed: ${value.length} bytes'));
// Receive future updates while listening, then release this subscription.
await resumed.cancel();
```

There is no cached-value replay guarantee, and getter results are not guaranteed
to have stable object identity. A fresh getter obtained after cancellation works
alongside the retained old stream: when both are listened to, both receive matching
updates. Cancelling either stream's listeners must not remove the other's routing.
Multiple listeners on one retained stream are also supported; cancelling one
leaves the others active, and the stream remains reusable after all cancel.
Regression tests cover old/fresh overlap with cancellation in either order and
a further getter during overlap.[^retained]

Routing normally matches device, service and characteristic. Legacy events with
an empty service ID match that device and characteristic across service-scoped
streams for compatibility; they do not establish which service produced the
value. The old/fresh overlap tests cover both event shapes.[^routing][^retained]

Raw stream listening, cancellation and re-listening do not enable or disable
native notifications. Use `setNotifiable(...)` explicitly, or prefer
`notifications()` for subscription-owned setup/teardown. Reusable Dart routing
does not change native notification behavior or ensure that a peripheral sends
anything. These regression tests inject platform value events and verify Dart
delivery only; they neither prove hardware notification delivery nor exercise
native notification setup/teardown. See [verification boundaries](testing.md#report-evidence-not-assumptions).

## Writes are application protocol operations

`write(bytes, BleOutputProperty.withResponse)` submits one write. For a protocol
that expects multiple writes, explicitly choose its frame size:

```dart
await characteristic.writeInChunks(
  firmwareBlock,
  BleOutputProperty.withResponse,
  chunkSize: 20,
);
```

Here `firmwareBlock` is a Uint8List and `20` is an illustrative protocol choice.
Chunks are serial; the first failure stops the future. This is not ATT long-write,
does not add reassembly metadata, and cannot infer peripheral framing.
Without-response completion is not a peripheral acknowledgement or universal
backpressure. When supported, negotiated MTU minus 3 is a common ATT payload
upper bound, not a recommended application frame size.

Query `await characteristic.maximumWriteValueLength(mode)` after connecting
and again after reconnecting. Darwin returns CoreBluetooth's per-mode maximum;
Android, Linux and Windows return `null` (unknown), not an MTU-derived guess.
Darwin rejects oversized writes and fails fast with `invalidState` when its
without-response buffer is full. The caller owns any retry budget; awaiting a
previous handoff is not proof that buffer space is available. See the
[repository write/backpressure reference](https://github.com/prefanatic/quick_blue#write-payload-limits-and-backpressure)
for platform-specific completion boundaries.

## Database changes invalidate snapshots

On `device.gattServiceChangedStream`, replace your snapshot by rediscovering the
complete database. Old snapshots have `isValid == false`; resolving from them
throws `invalidState`. A change during discovery cancels that discovery with
`cancelled` so the caller can retry.[^source3]

Darwin identifies invalidated services; other supported implementations can emit
an empty list meaning the database changed, not that nothing changed. Serialize
refresh work, await it, and surface failures instead of discarding an async
listener future. See [capabilities](capabilities.md) for OS gates.

## Opt into snapshot-bound handles

`gatt.characteristic(...)` resolves an ID-only handle: it validates the
snapshot at resolution time, then keeps submitting on later use even if the
snapshot is invalidated in between. Applications that want every new
submission checked against the snapshot can opt in per handle with
`gatt.boundCharacteristic(...)`, which returns the same
`BluetoothCharacteristic` type carrying that snapshot's validity:

```dart
final gatt = await device.discoverGatt();
final bound = gatt.boundCharacteristic(characteristicId, service: serviceId);
final value = await bound.read(); // submits while gatt.isValid is true
```

While the snapshot stays valid, a bound handle behaves exactly like an
ID-only handle. After a service-database change invalidates the snapshot, a
new submission through that bound handle throws `QuickBlueException` with
`QuickBlueErrorCode.invalidState` before anything reaches the platform:

- `read()`, `write(...)` and `setNotifiable(...)` check on entry, with the
  device, service and characteristic identifiers on the error.
- `notifications(...)` checks when the stream is listened to; rejection is a
  stream error delivered before native notification setup starts, so a
  subscription retained across invalidation fails instead of silently doing
  nothing.
- `writeInChunks(...)` checks each new chunk: a chunk already submitted keeps
  its normal completion, and processing stops before the next chunk is sent.

`valueStream` and `maximumWriteValueLength(...)` are not submissions and are
not guarded. The existing security-recovery retry is part of an
already-started operation and is unchanged.

Already-submitted IO is not rolled back. A write accepted before
invalidation completes according to its normal platform contract;
invalidation only rejects new submissions.

```dart
try {
  await bound.read();
} on QuickBlueException catch (error) {
  if (error.code == QuickBlueErrorCode.invalidState) {
    // Rediscover and resolve a fresh bound handle (see below).
  }
}
```

### Resolve fresh handles after a change

Bound handles fail fast instead of going stale quietly. After a
`gattServiceChangedStream` event, rediscover the database and resolve again:

```dart
// Run inside an awaited async workflow; discovery errors reach its caller.
await for (final change in device.gattServiceChangedStream) {
  final freshGatt = await device.discoverGatt();
  final fresh = freshGatt.boundCharacteristic(
    characteristicId,
    service: serviceId,
  );
  // Replace the application's previous handles with fresh.
}
```

Each `discoverGatt()` result carries its own validity, and bound handles
resolved from the fresh snapshot submit normally again.

### Direct-ID handles stay the compatibility escape hatch

Migration is opt-in per handle; every existing entry point keeps its current
semantics:

- `gatt.characteristic(...)` still validates at resolution — resolving from
  an invalidated snapshot throws `invalidState` — but the resolved handle is
  ID-only and is not guarded later.
- `device.characteristic(service, characteristic)` and the direct-ID helpers
  (`device.readValue`, `device.writeValue`, `device.setNotifiable`, ...) are
  not associated with any snapshot and never gain the new guard.

Use the ID-only paths when the application deliberately manages validity
itself, and the bound path where a submission against a stale database view
must fail before it is sent.

### Disconnect and reconnect snapshot policy

Neither `disconnect()` nor a subsequent `connect()` invalidates a snapshot:
`isValid` stays `true` across disconnect/reconnect, and bound handles keep
submitting. Only a platform-reported service-database change event
invalidates a snapshot. This is the existing policy, characterized by the
regression tests — observed current behavior, not a newly invented
guarantee that reconnects will never invalidate a snapshot.[^source4]

### Evidence scope

The bound-handle contract is established by executable Dart tests against a
fake platform: they prove the additive Dart validity contract, namely that
the guard runs before platform submission. They do not establish native-side
rejection, hardware behavior, or any rollback of IO already handed to a
platform.[^source4]

[^source3]: GATT discovery, invalidation and chunked-write tests.
[^routing]: Raw value controller registration, identity-safe cancellation and event dispatch.
[^retained]: Injected-event regressions for retained streams and overlapping listeners; no native notification calls.
[^settlement]: Controlled-future notification setup, cancellation, retry, shared ownership and conflicting-mode regressions; Dart lifecycle evidence only.
[^source4]: Snapshot-bound handle guards, rediscovery and disconnect/reconnect policy tests.
