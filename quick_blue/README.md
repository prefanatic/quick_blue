# quick_blue

A cross-platform (Android/iOS/macOS/Windows/Linux) BluetoothLE plugin for Flutter

# Usage

- [Scan BLE peripheral](#scan-ble-peripheral)
- [Use device handles](#use-device-handles)
- [Observe Android bond state](#observe-android-bond-state)
- [Discover services and characteristics](#discover-services-and-characteristics)
- [Transfer characteristic data](#transfer-characteristic-data)

| API | Android | iOS | macOS | Windows | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| isBluetoothAvailable | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| bluetoothStateStream | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| scan/scanResults | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| connectedDevices | ✔️ | ✔️* | ✔️* | ✔️ | ✔️ |
| connect/disconnect | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| bondState/pair | ✔️ | — | — | — | ✔️ |
| bondStateStream | ✔️ | — | — | — | — |
| discoverServices | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| setNotifiable | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| readValue | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| writeValue | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| requestMtu | ✔️ | ✔️ | ✔️ | ✔️ | — |

`bluetoothStateStream` emits the latest available Bluetooth state first for each
listener. Android, iOS, macOS, and Linux then emit live state changes; Windows
currently emits only the current availability snapshot.

* iOS and macOS require service UUIDs when looking up already connected
  peripherals.

> * Windows' APIs are little different on `discoverServices`: https://github.com/prefanatic/quick_blue/issues/76

## Scan BLE peripheral

Android/iOS/macOS/Windows/Linux

Enable CoreBluetooth state preservation/restoration on iOS and macOS before any
other Bluetooth call:

```dart
await QuickBlue.configure(maintainState: true);
```

On iOS, apps that rely on restoration after background termination also need the
`bluetooth-central` background mode in `UIBackgroundModes`.

Use `scan()` when you only need `BluetoothDevice` handles. A handle is a
lightweight reference to a platform device identifier; creating one does not
connect, scan, or validate that the peripheral is nearby.

```dart
final subscription = QuickBlue.scan().listen((device) {
  print('onScanResult ${device.id}');
});

// ...
await subscription.cancel();
```

Use `scanResults()` when you need advertisement payloads such as service data or
manufacturer data. The scan starts when the stream is listened to and stops when
the subscription is canceled.

```dart
final subscription = QuickBlue.scanResults().listen((result) {
  print('onScanResult ${result.deviceId}, ${result.serviceData}');
});

// ...
await subscription.cancel();
```

Filter service data separately from advertised service UUIDs. Values are
payload prefixes, an empty value matches any service data for that UUID, and
multiple entries use OR semantics:

```dart
import 'dart:typed_data';

final subscription = QuickBlue.scanResults(
  scanFilter: ScanFilter(
    serviceData: <String, Uint8List>{'180a': Uint8List(0)},
  ),
).listen((result) {
  print('onScanResult ${result.deviceId}');
});
```

These result semantics are consistent across platforms. Android additionally
applies the service-data filter through its native scanner.

Get handles for peripherals that are already connected:

```dart
final devices = await QuickBlue.connectedDevices(
  serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
);
```

Pass service UUIDs for iOS and macOS so CoreBluetooth can find matching
system-connected peripherals.

## Use device handles

Create a handle from a scanned device or a known platform `deviceId`, then keep
using that handle for connection state, service discovery, MTU, L2CAP, and
characteristic operations.

```dart
final device = QuickBlue.device(deviceId);

final connectionSubscription = device.connectionStateStream.listen((event) {
  print('connection ${event.deviceId}: ${event.state} (${event.status})');
});

await device.connect().timeout(const Duration(seconds: 15));
// ...
await device.disconnect().timeout(const Duration(seconds: 5));
await connectionSubscription.cancel();
```

The static `connect`, `disconnect`, `discoverServices`, `readValue`,
`writeValue`, and `setNotifiable` methods delegate through the same handle API.
They remain available as deprecated compatibility wrappers. Prefer keeping a
`BluetoothDevice` when doing more than one operation.
Only one connect or disconnect operation may be pending for a device at a time.
Overlapping operations fail with `QuickBlueErrorCode.invalidState`; operations
for different devices remain independent.

## Observe Android bond state

Android exposes live pairing/bonding transitions through each device handle.
`waitForBondState()` subscribes before reading the current state, so it does not
miss a transition racing with the snapshot. Calling `pair()` while Android is
already bonding joins that in-progress operation.

```dart
final device = QuickBlue.device(deviceId);
final subscription = device.bondStateStream.listen((event) {
  print('bond ${event.previousState} -> ${event.state}');
});

await device.pair();
await device.waitForBondState(BluetoothBondState.bonded);
await subscription.cancel();
```

`bondState()` remains available for a one-time snapshot. App-initiated pairing
and live bond-state events are not supported on iOS, macOS, or Windows.

## Discover services and characteristics

Discover services and characteristic metadata for a connected device.

```dart
final device = QuickBlue.device(deviceId);

final services = await device.discoverServices().timeout(
  const Duration(seconds: 15),
);

for (final service in services) {
  print(service.uuid);
  for (final characteristic in service.characteristicDetails) {
    print(
      '${characteristic.uuid}: '
      'read=${characteristic.canRead}, '
      'write=${characteristic.canWrite}, '
      'notify=${characteristic.canNotify}, '
      'indicate=${characteristic.canIndicate}',
    );
  }
}
```

`BluetoothService.characteristics` remains available as the list of
characteristic UUIDs. Use `BluetoothService.characteristicDetails` when you need
read/write/notify/indicate capabilities.

When you know a characteristic UUID but not its service UUID, discover a
`BluetoothGatt` snapshot and resolve a service-scoped characteristic handle:

```dart
final gatt = await device.discoverGatt();
final characteristic = gatt.characteristic(characteristicId);
final value = await characteristic.read();
```

Use `gatt.hasCharacteristic(characteristicId, service: serviceId)` when you only
need to check whether a discovered GATT view contains a characteristic.

If the same characteristic UUID appears under multiple services, pass the
service UUID to disambiguate:

```dart
final characteristic = gatt.characteristic(
  characteristicId,
  service: serviceId,
);
```

## Transfer characteristic data

Create a service-scoped `BluetoothCharacteristic` handle when you already know
the service and characteristic UUIDs.

```dart
final characteristic = device.characteristic(serviceId, characteristicId);
```

- Read data from a characteristic.

```dart
final value = await characteristic.read().timeout(const Duration(seconds: 5));
```

- Write data to a characteristic.

```dart
await characteristic.write(value, BleOutputProperty.withResponse);
```

- Receive data from a characteristic.

```dart
final subscription = characteristic.notifications(
  bleInputProperty: BleInputProperty.notification,
).listen((value) {
  print(hex.encode(value));
});

// ...
await subscription.cancel();
```

When notification lifetime needs to be managed separately from one stream
subscription, listen to `valueStream` and call `setNotifiable` explicitly:

```dart
final subscription = characteristic.valueStream.listen((value) {
  print(hex.encode(value));
});

await characteristic.setNotifiable(BleInputProperty.notification);

// ...
await characteristic.setNotifiable(BleInputProperty.disabled);
await subscription.cancel();
```

Characteristic value events are scoped by device, service, and characteristic.
This matters for peripherals that reuse a characteristic UUID under multiple
services.

`notifications()` enables notifications before forwarding values and disables
them after the final subscription for that characteristic is canceled.
Concurrent listeners share one native notification lifecycle. On Android,
GATT operations for a device
are serialized and notification setup completes after the client characteristic
configuration descriptor write is acknowledged; descriptor write failures are
reported through the returned notification stream error.

Linux relies on BlueZ's automatic ATT MTU negotiation. Because the negotiated
value is not reliably available through this implementation, `requestMtu`
reports an unsupported-operation error on Linux.

The device handle also exposes one-off characteristic methods:

```dart
final value = await device.readValue(serviceId, characteristicId);
await device.writeValue(
  serviceId,
  characteristicId,
  value,
  BleOutputProperty.withResponse,
);
```

Android non-security GATT callback failures are exposed as
`QuickBlueGattException`. Its `status` field is the unmodified numeric status,
including vendor-specific values, so applications do not need to parse error
messages.

```dart
try {
  await device.readValue(serviceId, characteristicId);
} on QuickBlueGattException catch (error) {
  print('read failed with GATT status ${error.status}');
}
```

Managed connect, characteristic read, notification setup, and acknowledged
write operations use the same security-recovery contract across platforms.
QuickBlue coordinates one recovery per device, pairs an unbonded device when
the platform supports it, and retries the rejected operation once after
successful recovery. This retry is safe for acknowledged writes because a
security response means the peer rejected the write before applying it.

If automatic recovery cannot proceed, QuickBlue exposes
`QuickBlueSecurityException`. Its `reason` identifies authentication,
authorization, encryption, encryption-key-size, encryption-timeout, and
peer-removed-pairing failures. `nativeDomain` and `nativeCode` preserve native
diagnostics when available, while `recoveryResult` reports whether user action
is required or programmatic recovery is unsupported. Failed connection events
also expose the exception through `BluetoothConnectionStateChange.error`.

```dart
try {
  await device.readValue(serviceId, characteristicId);
} on QuickBlueSecurityException catch (error) {
  if (error.recoveryResult ==
      QuickBlueSecurityRecoveryResult.userActionRequired) {
    // Ask the user to forget and re-pair the device in system settings.
  }
}
```

The older static read, write, notify, MTU, L2CAP, and service-discovery helpers
remain available as deprecated compatibility wrappers around the device and
characteristic APIs.
