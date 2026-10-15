---
type: "Playbook"
title: "Scan, connect and read"
description: "Run a small read-only workflow with explicit cleanup and caller timeouts."
tags: ["getting-started", "scan", "gatt"]

sources: [{"id": "source1", "resource": "../quick_blue_core/lib/src/quick_blue.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart"}]
---

# Scan, connect and read

First complete [platform setup](platform-setup.md). Device identifiers are
platform-specific; do not assume that an Android address is a CoreBluetooth UUID.

## Find a device

Dart fragment inside an async function, with `quick_blue.dart` imported:

```dart
final result = await QuickBlue.scanResults(
  scanFilter: ScanFilter(serviceUuids: ['180f']),
).first.timeout(const Duration(seconds: 12));
print(result.deviceId);
```

`.first` cancels its scan subscription after one match. A filter only finds
advertisements that actually include that service. See [scanning](scanning.md)
if discovery yields no result.

## Read a known characteristic

Complete Dart function; call it with a real device and readable UUIDs. Battery
Service `180f` / Battery Level `2a19` is an example, not a guaranteed device feature.

```dart
import 'dart:typed_data';
import 'package:quick_blue/quick_blue.dart';

Future<Uint8List> readCharacteristic(
  String deviceId,
  String serviceId,
  String characteristicId,
) async {
  final device = QuickBlue.device(deviceId);
  try {
    await device.connect().timeout(const Duration(seconds: 15));
    final gatt = await device.discoverGatt()
        .timeout(const Duration(seconds: 15));
    final characteristic = gatt.characteristic(
      characteristicId,
      service: serviceId,
    );
    return await characteristic.read().timeout(const Duration(seconds: 8));
  } finally {
    await device.disconnect().timeout(const Duration(seconds: 5));
  }
}
```

The `finally` covers connection timeouts too: a Dart timeout does not cancel
native work. Cleanup errors propagate and can replace the original error;
production apps should record both when diagnosing failures.

Next: [writes and notifications](gatt.md), [connection lifetimes](connections.md),
and [structured errors](pairing.md).
