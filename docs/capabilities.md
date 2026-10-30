---
type: "Reference"
title: "Runtime capability matrix"
description: "Gate optional APIs using modes rather than assuming uniform platform support."
tags: ["platforms", "capabilities"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/models.dart"}, {"id": "source2", "resource": "../quick_blue/lib/src/quick_blue_android.dart"}, {"id": "source3", "resource": "../quick_blue/android/src/main/kotlin/com/example/quick_blue/QuickBluePlugin.kt"}, {"id": "source4", "resource": "../quick_blue_darwin/lib/src/quick_blue_darwin.dart"}, {"id": "source5", "resource": "../quick_blue_linux_dart/lib/quick_blue_linux_dart.dart"}, {"id": "source6", "resource": "../quick_blue_windows/lib/src/quick_blue_windows.dart"}, {"id": "source7", "resource": "../quick_blue_platform_interface/lib/src/quick_blue_platform.dart"}]
---

# Runtime capability matrix

Query `await QuickBlue.capabilities()` on the actual target. These modes describe
implemented behavior, not permission, power, nearby hardware, or successful IO.

| Mode / API | Android | iOS / macOS | Linux | Windows |
| --- | --- | --- | --- | --- |
| `bonding` | `queryPairAndObserve` | `unsupported` | `queryAndPair` | `unsupported` |
| `mtu` | `requestable` | `readNegotiated` | `unsupported` | `readNegotiated` |
| `gattServiceChanges` | `databaseOnly` on API 31+ | `invalidatedServices` | `databaseOnly` | `databaseOnly` |
| `connectedDeviceLookup` | `unrestricted` | `requiresServiceUuids` | `unrestricted` | `unrestricted` |
| `supportsL2capSockets` | API 29+ | true | true; library checked at use | false |
| `supportsCompanionAssociation` | API-dependent | false | false | false |
| `supportsAppleAccessorySetup` | false | iOS 18+ only; false on macOS | false | false |
| `bluetoothStateStream` | Snapshot + live | Snapshot + live | Snapshot + live | Snapshot only |

Android service-change support is `unsupported` below API 31. The Windows state
stream uses the base implementation's availability snapshot, not a live power
monitor.[^source7]

## Portable operations

Scan, connect/disconnect, managed connections, service/GATT discovery, read/write,
chunked writes, and notifications have implementations on all five targets.
That does not mean every peripheral supports every characteristic operation.
Windows discovery fails as a whole if enumeration of one returned service fails.

Dart fragment in an async function, with an existing `device`:

```dart
final capabilities = await QuickBlue.capabilities();
if (capabilities.mtu == BluetoothMtuCapability.requestable) {
  final mtu = await device.requestMtu(247);
  print('negotiated MTU: $mtu');
}
if (capabilities.supportsPairing) {
  await device.pair();
}
```

`supportsPairing` is a real derived helper; `supportsBonding` is not an API.
Other helpers: `supportsBondStateChanges`, `supportsGattServiceChanges`,
`reportsInvalidatedServiceUuids`. `requestMtu` on Darwin/Windows reads the negotiated
value rather than requesting that exact size; Linux reports `unsupported`.

## Already-connected devices

```dart
final devices = await QuickBlue.connectedDevices(serviceUuids: ['180f']);
```

CoreBluetooth requires service UUIDs. This lookup returns system-connected
handles, not ownership in this engine: attach with `connect()` before GATT work.
See [multi-engine](multi-engine.md), [pairing](pairing.md), and [L2CAP](l2cap.md).

[^source7]: Base Bluetooth state event implementation.
