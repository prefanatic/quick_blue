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
| startScan/stopScan | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| connect/disconnect | ✔️ | ✔️ | ✔️ | ✔️ |  |
| discoverServices | ✔️ | ✔️ | ✔️ | ✔️ |  |
| setNotifiable | ✔️ | ✔️ | ✔️ | ✔️ |  |
| readValue | ✔️ | ✔️ | ✔️ | ✔️ |  |
| writeValue | ✔️ | ✔️ | ✔️ | ✔️ |  |
| requestMtu | ✔️ | ✔️ | ✔️ | ✔️ |  |

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

## Connect BLE peripheral

Connect to `deviceId`, received from `QuickBlue.scan()`

```dart
QuickBlue.setConnectionHandler(_handleConnectionChange);

void _handleConnectionChange(String deviceId, BlueConnectionState state) {
  print('_handleConnectionChange $deviceId, $state');
}

QuickBlue.connect(deviceId);
// ...
QuickBlue.disconnect(deviceId);
```

Or use the device object API:

```dart
final device = QuickBlue.device(deviceId);

await device.connect();
// ...
await device.disconnect();
```

## Discover services of BLE peripheral

Discover services od `deviceId`

```dart
QuickBlue.setServiceHandler(_handleServiceDiscovery);

void _handleServiceDiscovery(String deviceId, String serviceId) {
  print('_handleServiceDiscovery $deviceId, $serviceId');
}

QuickBlue.discoverServices(deviceId);
```

Or use the device object API:

```dart
final device = QuickBlue.device(deviceId);

final services = await device.discoverServices();

for (final service in services) {
  print('${service.uuid}: ${service.characteristics}');
}
```

## Transfer data between BLE central & peripheral

- Pull data from peripheral of `deviceId`

> Data would receive within value handler of `QuickBlue.setValueHandler`
> Because it is how [peripheral(_:didUpdateValueFor:error:)](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/1518708-peripheral) work on iOS/macOS

```dart
// Data would receive from value handler of `QuickBlue.setValueHandler`
QuickBlue.readValue(deviceId, serviceId, characteristicId);
```

Or receive the read result as a `Future` from the device object:

```dart
final value = await device.readValue(serviceId, characteristicId);
```

- Send data to peripheral of `deviceId`

```dart
QuickBlue.writeValue(deviceId, serviceId, characteristicId, value);
```

- Receive data from peripheral of `deviceId`

```dart
QuickBlue.setValueHandler(_handleValueChange);

void _handleValueChange(String deviceId, String characteristicId, Uint8List value) {
  print('_handleValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
}

QuickBlue.setNotifiable(deviceId, serviceId, characteristicId, true);
```

Or subscribe to characteristic values from the device object:

```dart
final characteristic = device.characteristic(serviceId, characteristicId);

final subscription = characteristic.notifications().listen((value) {
  print(hex.encode(value));
});

// ...
await subscription.cancel();
```
