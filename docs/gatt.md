---
type: "Reference"
title: "Discover, write and subscribe"
description: "Use valid GATT snapshots, explicit write framing and subscription-owned notifications."
tags: ["gatt", "notifications", "writes"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_gatt.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/test/bluetooth_gatt_test.dart"}]
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

Concurrent listeners share native setup; the final listener requests its release.
Linux has reproduced [fake-BlueZ teardown gaps](limitations.md#linux-gatt-teardown-characterization);
do not interpret cancellation as proof of native cleanup. Use
`valueStream` plus `setNotifiable(...)` only when setup/teardown must be managed
separately (listen before enabling).

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
