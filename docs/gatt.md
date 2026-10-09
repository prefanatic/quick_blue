---
type: "Reference"
title: "Discover, write and subscribe"
description: "Use valid GATT snapshots, explicit write framing and subscription-owned notifications."
tags: ["gatt", "notifications", "writes"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_gatt.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/test/bluetooth_gatt_test.dart"}, {"id": "routing", "resource": "../quick_blue_platform_interface/lib/src/characteristic_lifecycle.dart"}, {"id": "retained", "resource": "../quick_blue_platform_interface/test/retained_characteristic_value_stream_test.dart"}]
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

[^source3]: GATT discovery, invalidation and chunked-write tests.
[^routing]: Raw value controller registration, identity-safe cancellation and event dispatch.
[^retained]: Injected-event regressions for retained streams and overlapping listeners; no native notification calls.
