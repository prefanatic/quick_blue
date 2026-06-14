# quick_blue

A cross-platform (Android/iOS/macOS/Windows/Linux) BluetoothLE plugin for Flutter

# Usage

- [Scan BLE peripheral](#scan-ble-peripheral)
- [Connect BLE peripheral](#connect-ble-peripheral)
- [Discover services of BLE peripheral](#discover-services-of-ble-peripheral)
- [Transfer data between BLE central & peripheral](#transfer-data-between-ble-central--peripheral)

| API | Android | iOS | macOS | Windows | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| isBluetoothAvailable | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| bluetoothStateStream | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| scan/scanResults | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| connectedDevices | ✔️ | ✔️* | ✔️* | ✔️ | ✔️ |
| connect/disconnect | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| discoverServices | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| setNotifiable | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| readValue | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| writeValue | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| requestMtu | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |

`bluetoothStateStream` emits live state changes on Android, iOS, macOS, and
Linux. Windows currently emits the current availability snapshot.

* iOS and macOS require service UUIDs when looking up already connected
  peripherals.

> * Windows' APIs are little different on `discoverServices`: https://github.com/woodemi/quick_blue/issues/76

## Scan BLE peripheral

Android/iOS/macOS/Windows/Linux

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

Get peripherals that are already connected:

```dart
final devices = await QuickBlue.connectedDevices(
  serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
);
```

Pass service UUIDs for iOS and macOS so CoreBluetooth can find matching
system-connected peripherals.

## Connect BLE peripheral

Connect to `deviceId`, received from `QuickBlue.scan()` or
`QuickBlue.scanResults()`.

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

The static methods delegate through the same device API:

```dart
await QuickBlue.connect(deviceId).timeout(const Duration(seconds: 15));
// ...
await QuickBlue.disconnect(deviceId).timeout(const Duration(seconds: 5));
```

## Discover services of BLE peripheral

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

When you know a characteristic UUID but not its service UUID, discover a GATT
view and resolve the characteristic from the discovered services:

```dart
final gatt = await device.discoverGatt();
final characteristic = gatt.characteristic(characteristicId);
final value = await characteristic.read();
```

If the same characteristic UUID appears under multiple services, pass the
service UUID to disambiguate:

```dart
final characteristic = gatt.characteristic(
  characteristicId,
  service: serviceId,
);
```

## Transfer data between BLE central & peripheral

- Pull data from a characteristic.

```dart
final value = await QuickBlue.readValue(
  deviceId,
  serviceId,
  characteristicId,
).timeout(const Duration(seconds: 5));
```

Or use the device object:

```dart
final value = await device.readValue(
  serviceId,
  characteristicId,
).timeout(const Duration(seconds: 5));
```

- Send data to peripheral of `deviceId`

```dart
await QuickBlue.writeValue(
  deviceId,
  serviceId,
  characteristicId,
  value,
  BleOutputProperty.withResponse,
);
```

- Receive data from peripheral of `deviceId`

```dart
final characteristic = device.characteristic(serviceId, characteristicId);

final subscription = characteristic.notifications(
  bleInputProperty: BleInputProperty.notification,
).listen((value) {
  print(hex.encode(value));
});

// ...
await subscription.cancel();
```

Characteristic value events are scoped by device, service, and characteristic.
This matters for peripherals that reuse a characteristic UUID under multiple
services.

- Write data from the device object:

```dart
final characteristic = device.characteristic(serviceId, characteristicId);

await characteristic.write(value, BleOutputProperty.withResponse);
```

- Enable notifications through the static API:

```dart
await QuickBlue.setNotifiable(
  deviceId,
  serviceId,
  characteristicId,
  BleInputProperty.notification,
);

// ...
await QuickBlue.setNotifiable(
  deviceId,
  serviceId,
  characteristicId,
  BleInputProperty.disabled,
);
```
