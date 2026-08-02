# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy (BLE) on
Android, iOS, macOS, Windows, and Linux.

- [Example app](https://github.com/prefanatic/quick_blue/tree/master/quick_blue/example)
- [Changelog](https://github.com/prefanatic/quick_blue/blob/master/quick_blue/CHANGELOG.md)
- [Issue tracker](https://github.com/prefanatic/quick_blue/issues)

> To use the code documented here, install this repository from Git. A hosted
> `quick_blue` release may not contain the changes in this fork.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Platform setup](#platform-setup)
- [Quick start](#quick-start)
- [Working with devices and characteristics](#working-with-devices-and-characteristics)
- [Advanced usage](#advanced-usage)
- [Platform support](#platform-support)

## Requirements

| Target | Minimum or runtime requirement |
| :--- | :--- |
| Flutter | 3.44.2 |
| Dart | 3.12.2 |
| Android | API 26 |
| iOS | 13.0 |
| macOS | 10.15 |
| Windows | Windows 10 or 11 with a BLE adapter |
| Linux | BlueZ with a BLE adapter |

## Install

Install this fork from Git. Override every federated package so Dart does not
mix this fork's app-facing package with hosted platform implementations:

```yaml
dependencies:
  quick_blue:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue

dependency_overrides:
  quick_blue_platform_interface:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_platform_interface
  quick_blue_darwin:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_darwin
  quick_blue_linux:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_linux
  quick_blue_windows:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_windows
```

For reproducible builds, replace `master` with a tested commit SHA in all five
entries. If these changes become available in a hosted release, replace the Git
dependency and overrides with the corresponding version constraint.

Then import it:

```dart
import 'package:quick_blue/quick_blue.dart';
```

## Platform setup

### Android

The plugin contributes the appropriate Bluetooth and legacy location
permissions to the merged Android manifest. Your app must still request the
dangerous permissions at runtime before using BLE; `quick_blue` reports a
missing permission but does not show a permission prompt.

- Android 12 and later: request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`.
- Android 11 and earlier: request location permission before scanning.

If your app derives physical location from scan results, review Android's
Bluetooth permission guidance and override the plugin's `neverForLocation`
manifest declaration as appropriate for your use case.

### iOS

Add a Bluetooth usage description to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app scans for and connects to nearby Bluetooth devices.</string>
```

State restoration is optional. Apps that need reliable CoreBluetooth
restoration after background termination must add `bluetooth-central` to
`UIBackgroundModes` and enable Quick Blue's persistent native opt-in:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
</array>
<key>QuickBlueCoreBluetoothStateRestorationEnabled</key>
<true/>
```

The plugin reads this setting during native registration and immediately
creates its `CBCentralManager` with Quick Blue's stable restoration identifier,
before the Dart entrypoint runs. The persistent setting is authoritative:
`QuickBlue.configure(maintainState: false)` does not disable it.

`QuickBlue.configure(maintainState: true)` remains available as a runtime-only
opt-in when the Info.plist setting is absent. It must run before other Quick
Blue APIs, but it is not sufficient for a reliable iOS background relaunch
because Dart may start too late. See
[Darwin restoration launch correctness](#darwin-restoration-launch-correctness).

### macOS

Add `NSBluetoothAlwaysUsageDescription` to
`macos/Runner/Info.plist`. Sandboxed apps must also enable Bluetooth in both
debug and release entitlements:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

Apps that want restoration initialized before Dart can add
`QuickBlueCoreBluetoothStateRestorationEnabled` to the macOS Info.plist as
shown for iOS. A runtime-only
`QuickBlue.configure(maintainState: true)` remains available when early native
bootstrap is unnecessary.

### Windows

No application manifest changes are normally required. The machine must have a
working BLE adapter and Bluetooth must be enabled.

### Linux

BlueZ and a working BLE adapter are required. The BlueZ daemon must be running,
and the application process must be allowed to access BlueZ on the system
D-Bus.

The [example app](https://github.com/prefanatic/quick_blue/tree/master/quick_blue/example)
contains working Android, iOS, and macOS configuration.

## Quick start

`scanResults()` starts scanning when the stream is listened to and stops after
the subscription is canceled:

```dart
final scanSubscription = QuickBlue.scanResults().listen((result) {
  print('${result.deviceId} ${result.name} RSSI=${result.rssi}');
});

// Stop scanning when the UI no longer needs results.
await scanSubscription.cancel();
```

Connect, discover services, and interact with a known characteristic. The
service and characteristic UUIDs must identify a characteristic that supports
the operations used below:

```dart
import 'dart:typed_data';

import 'package:quick_blue/quick_blue.dart';

Future<void> readWriteNotify({
  required String deviceId,
  required String serviceId,
  required String characteristicId,
}) async {
  final device = QuickBlue.device(deviceId);

  await device.connect().timeout(const Duration(seconds: 15));
  try {
    final services = await device.discoverServices();
    for (final service in services) {
      print('${service.uuid}: ${service.characteristicDetails}');
    }

    final characteristic = device.characteristic(serviceId, characteristicId);
    final notifications = characteristic.notifications().listen((value) {
      print('notification: $value');
    });

    try {
      final currentValue = await characteristic.read();
      print('read: $currentValue');

      await characteristic.write(
        Uint8List.fromList([0x01]),
        BleOutputProperty.withResponse,
      );
    } finally {
      await notifications.cancel();
    }
  } finally {
    await device.disconnect().timeout(const Duration(seconds: 5));
  }
}
```

## Working with devices and characteristics

### Scan options

Use `QuickBlue.scan()` when you only need lightweight `BluetoothDevice`
handles. Use `QuickBlue.scanResults()` for advertisement fields such as RSSI,
service UUIDs, service data, or manufacturer data.

Common filters and options are available across platforms:

```dart
final subscription = QuickBlue.scanResults(
  scanFilter: ScanFilter(serviceUuids: ['180d'], rssi: -80),
  scanOptions: const ScanOptions(
    allowDuplicates: false,
    scanMode: ScanMode.balanced,
  ),
).listen((result) {
  print('${result.deviceId} ${result.name} RSSI=${result.rssi}');
});
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

Platform-specific scan options expose controls such as Android PHY,
CoreBluetooth solicited services, BlueZ pathloss, and Windows signal-strength
timing. Omitted common options preserve the platform defaults.

### Already-connected devices

Get handles for peripherals that are already connected:

```dart
final devices = await QuickBlue.connectedDevices(
  serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
);
```

iOS and macOS require service UUIDs because CoreBluetooth only returns
system-connected peripherals that match the supplied services.

### Discovering a characteristic

When you know a characteristic UUID but not its service UUID, discover a GATT
snapshot and resolve a service-scoped handle:

```dart
final gatt = await device.discoverGatt();
final characteristic = gatt.characteristic(characteristicId);
final value = await characteristic.read();
```

Use `gatt.hasCharacteristic(characteristicId, service: serviceId)` for a
presence check. If the same characteristic UUID appears under multiple
services, pass the service UUID to disambiguate:

```dart
final characteristic = gatt.characteristic(
  characteristicId,
  service: serviceId,
);
```

`BluetoothService.characteristicDetails` reports whether each discovered
characteristic supports reads, writes, notifications, or indications.

### GATT service changes

Listen for remote GATT database changes and rediscover services before using
the new database:

```dart
final subscription = device.gattServiceChangedStream.listen((change) async {
  print('invalidated services: ${change.invalidatedServiceUuids}');
  final refreshedGatt = await device.discoverGatt();
  // Replace the application's previous GATT snapshot with refreshedGatt.
});
```

`invalidatedServiceUuids` is empty when the platform reports only that the
database changed. Always rediscover the complete database after an event.
Previously returned `BluetoothGatt` snapshots report `isValid == false`, and
attempting to resolve a characteristic from an invalid snapshot throws
`QuickBlueException` with `QuickBlueErrorCode.invalidState`.

If a change arrives during service discovery, that discovery completes with
`QuickBlueErrorCode.cancelled` so callers can retry without receiving a mixture
of the old and new databases.

### Notifications

Use `characteristic.notifications()` when a stream subscription should own
notification setup and teardown. Concurrent listeners for the same
characteristic share one native subscription, which is disabled after the final
listener cancels.

Use `characteristic.valueStream` with
`characteristic.setNotifiable(...)` when callers must listen before enabling
updates or manage the notification lifetime separately.

### Pairing

Android and Linux expose app-initiated pairing:

```dart
final device = QuickBlue.device(deviceId);
final state = await device.bondState();
if (state != BluetoothBondState.bonded) {
  await device.pair();
}
```

iOS and macOS prompt automatically when an encrypted characteristic requires
pairing. Windows app-initiated pairing is not currently implemented.

## Advanced usage

### Connection concurrency

Prefer keeping a `BluetoothDevice` handle when performing more than one
operation. The deprecated static connection, discovery, and characteristic
methods delegate through the same handle API.

Only one connect or disconnect operation may be pending for a device. Calling
`disconnect()` during a pending `connect()` supersedes it: the connect completes
with `QuickBlueErrorCode.cancelled`, then the native device disconnects. A later
`connect()` likewise supersedes a disconnect still waiting for its terminal
native callback. Other overlapping operations of the same kind fail with
`QuickBlueErrorCode.invalidState`. Different devices can connect concurrently.

This makes it safe to follow a caller-side `connect().timeout(...)` with
`disconnect()` before retrying, or to reconnect after a caller-side disconnect
timeout. Android bounds final-client native teardown and ignores callbacks from
the retired GATT after a replacement connection starts.

Concurrent service-discovery calls for one device share the same result. A
disconnect cancels any pending discovery with `QuickBlueErrorCode.cancelled`,
so discovery can start fresh after reconnecting even when the original caller
timed out.

### Multiple Flutter engines

Quick Blue coordinates each device connection across Flutter engines in the
same application process, including foreground UI engines, Workmanager engines,
and engines hosted by an Android foreground service.

All supported platforms share one process-wide native GATT connection per
device. `connect()` attaches the calling engine to that connection, while
`disconnect()` detaches only that engine. The physical connection closes after
the final engine detaches. Connection, discovery, MTU, and notification events
are delivered to every attached engine, and notification ownership is
reference-counted across engines.

For a foreground handoff, attach the new engine before detaching the old one:

```dart
await foregroundDevice.connect();
await backgroundNotifications.cancel();
await backgroundDevice.disconnect();
```

Dart subscriptions and characteristic handles remain engine-local and must be
created in each engine. On Darwin, a stable CoreBluetooth device UUID can be
connected directly through `QuickBlue.device(id)` when CoreBluetooth already
knows the peripheral; a preceding scan is not required.

### Security recovery

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

### Observability

Set `QuickBlue.observer` to receive typed Quick Blue operation lifecycles. The
API is intentionally independent of traces, metrics, and logs: an adapter can
turn each operation into the signals supported by the app's telemetry stack.

For example, an observer can retain a Flutter `TimelineTask` in the returned
per-operation handle:

```dart
import 'dart:developer';

final class TimelineQuickBlueObserver implements QuickBlueObserver {
  @override
  QuickBlueOperationObservation onOperationStarted(
    QuickBlueOperation operation,
  ) {
    final task = TimelineTask()
      ..start('quick_blue.${operation.kind.name}');
    return _TimelineOperation(task);
  }
}

final class _TimelineOperation implements QuickBlueOperationObservation {
  _TimelineOperation(this.task);

  final TimelineTask task;

  @override
  void onOperationEnded(QuickBlueOperationEnd operation) {
    final failure = operation.failure;
    task.finish(arguments: <String, Object?>{
      'outcome': operation.outcome.name,
      'duration_us': operation.duration.inMicroseconds,
      if (failure != null) 'error_type': failure.errorType,
      if (failure?.code != null) 'error_code': failure!.code!.name,
      if (failure?.nativeDomain != null)
        'native_domain': failure!.nativeDomain,
      if (failure?.nativeStatus != null)
        'native_status': failure!.nativeStatus,
    });
  }
}

QuickBlue.observer = TimelineQuickBlueObserver();
```

Combine independent timeline, tracing, metrics, or test observers without
making one adapter own the others:

```dart
QuickBlue.observer = CompositeQuickBlueObserver([
  timelineObserver,
  openTelemetryObserver,
]);
```

An observer that also implements `QuickBlueValueObserver` receives one
payload-free callback as soon as Quick Blue receives each characteristic value.
The callback includes the device, service, and characteristic identifiers plus
the byte count, so it covers both `notifications()` and the explicit
`valueStream` / `setNotifiable()` lifecycle without waiting for a long-lived
subscription to end.

An observer can separately implement `QuickBlueDarwinRestorationObserver` to
learn when CoreBluetooth actually invokes `centralManager(_:willRestoreState:)`:

```dart
final class BluetoothTelemetryObserver
    implements QuickBlueObserver, QuickBlueDarwinRestorationObserver {
  @override
  QuickBlueOperationObservation? onOperationStarted(
    QuickBlueOperation operation,
  ) {
    // A configure operation whose maintainState field is true means the app
    // requested restoration during this Dart process.
    return null;
  }

  @override
  void onDarwinStateRestored(QuickBlueDarwinRestorationEvent event) {
    restorationCallbacks.add(<String, Object>{
      'peripheral_count': event.restoredPeripheralCount,
      'disconnected_count': event.disconnectedPeripheralCount,
      'connecting_count': event.connectingPeripheralCount,
      'connected_count': event.connectedPeripheralCount,
      'disconnecting_count': event.disconnectingPeripheralCount,
      'unknown_count': event.unknownPeripheralCount,
      'scanning_restored': event.scanningRestored,
      'scan_service_count': event.restoredScanServiceCount,
    });
  }
}
```

Native callbacks are buffered until Dart subscribes, then buffered again until
a restoration observer is installed. Each native callback is delivered once.
The restoration event is export-safe: it contains aggregate counts only and
never contains the restoration identifier or peripheral identifiers.

These lifecycle facts are distinct:

| Fact | How to observe it |
| --- | --- |
| Restoration was requested from Dart | `QuickBlueOperation.kind` is `configure` and `maintainState` is `true`. |
| The manager was initialized with Quick Blue's restoration identifier | The persistent Info.plist key is `true` and native plugin registration completed, or `configure(maintainState: true)` completed successfully without the persistent setting. |
| CoreBluetooth had state to restore | `onDarwinStateRestored` runs. A successful configure does not imply this callback will occur. |

An OpenTelemetry adapter follows the same pattern: create a real SDK span in
`onOperationStarted`, retain it in the returned handle, then record the typed
outcome and measurements before ending it. The adapter—not Quick Blue—chooses
span names, metric instruments, log severity, sampling, and export policy.

Healthy streams stopped by their subscriber—including a scan consumed with
`.first`—are reported as `stopped`. Operations superseded by Quick Blue are
reported as `cancelled`, not failed. Observer callback failures are ignored so
diagnostics cannot change Bluetooth behavior.

`QuickBlueOperationEnd.failure` contains export-safe error type, portable code,
and native status metadata. Its raw `error` and `stackTrace` remain available
for local diagnostics but are sensitive: errors can contain device identifiers,
native details, and local paths. `QuickBlueOperation.deviceId` and
`QuickBlueValueObservation.deviceId` can identify a physical device, and scan
filters can contain service/manufacturer data prefixes. Redact or hash sensitive
context before export. Characteristic values and advertisement results are
never included. Set `QuickBlue.observer = null` to disable observation.

### Darwin restoration launch correctness

Apple requires an app relaunched for Bluetooth work to recreate its
`CBCentralManager` with the same restoration identifier. In a scene-based app,
the identifier must be persisted or otherwise stable because launch options do
not supply it. CoreBluetooth may invoke `willRestoreState` before ordinary app
initialization callbacks, so relying on Dart to call
`configure(maintainState: true)` after the app reaches `resumed` is too late
for a robust iOS background-relaunch path.

Quick Blue provides a native persistent opt-in:

```xml
<key>QuickBlueCoreBluetoothStateRestorationEnabled</key>
<true/>
```

Plugin registration reads this setting and creates the central manager
immediately with the stable identifier, before the Dart entrypoint runs. The
setting is persistent app configuration rather than a per-process Dart call.
The native restoration-event buffer is installed before manager creation, so a
restoration callback delivered before Dart attaches remains available.

Automatic manager creation prevents a later AccessorySetupKit system picker
from running first. An app must therefore use either the persistent restoration
opt-in or an AccessorySetupKit-first startup flow. Leave
`QuickBlueCoreBluetoothStateRestorationEnabled` absent or `false` while using
the picker, then use the runtime configuration path after setup. A single app
build cannot currently combine the persistent bootstrap with Quick Blue's
AccessorySetupKit picker.

Registration-time bootstrap assumes the Flutter engine and plugins are
registered during application launch, as in a standard Flutter app. Add-to-app
integrations that intentionally delay Flutter engine creation still need an
application-owned native `CBCentralManager` bootstrap; Quick Blue does not yet
provide a pre-engine AppDelegate API.

This behavior is based on Apple's
[Core Bluetooth restoration guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
and
[`CBCentralManagerOptionRestoreIdentifierKey` documentation](https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey).

### Apple AccessorySetupKit

iOS 18 and later can use AccessorySetupKit to discover and authorize a known
Bluetooth product with Apple's system picker. Add the product's discovery
values to the app's Info.plist:

Do not enable `QuickBlueCoreBluetoothStateRestorationEnabled` before showing
the picker. Persistent restoration creates CoreBluetooth during native plugin
registration, while AccessorySetupKit must run first.

```xml
<key>NSAccessorySetupSupports</key>
<array>
  <string>Bluetooth</string>
</array>
<key>NSAccessorySetupBluetoothServices</key>
<array>
  <string>180D</string>
</array>
<key>NSAccessorySetupBluetoothNames</key>
<array>
  <string>Sensor</string>
</array>
```

Load product artwork and show the picker before any API that initializes
CoreBluetooth:

```dart
import 'package:flutter/services.dart';

final imageData = await rootBundle.load('assets/sensor.png');
final imageBytes = imageData.buffer.asUint8List(
  imageData.offsetInBytes,
  imageData.lengthInBytes,
);
final accessory = await QuickBlue.appleAccessorySetup.showPicker([
  AppleAccessoryPickerItem(
    displayName: 'Sensor',
    productImage: imageBytes,
    discovery: AppleAccessoryDiscovery(
      serviceUuid: '180d',
      nameSubstring: 'Sensor',
    ),
  ),
]);

if (accessory != null) {
  await QuickBlue.device(accessory.deviceId).connect();
}
```

The picker authorizes the accessory but does not establish its GATT connection.
Use `accessories()` to list authorized Bluetooth accessories and `remove()` to
remove one. Calling `isSupported()` returns false on macOS and iOS versions
before 18.

Set `migrationDeviceId` on a picker item to migrate a peripheral UUID that the
app configured through CoreBluetooth before adopting AccessorySetupKit. Run
that picker before Quick Blue initializes CoreBluetooth.

AccessorySetupKit is an app-level opt-in. Once its Info.plist keys are present,
CoreBluetooth scanning is limited to accessories authorized for the app. The
runtime service UUID and name substring must match the Info.plist declarations;
Quick Blue validates them before showing the picker.

### Android companion-device association

Android companion-device association is available through
`QuickBlue.companion`. Call `isSupported()` before presenting Android-only
association UI, then use `associate()`, `associations()`, and `disassociate()`.

## Platform support

| API | Android | iOS | macOS | Windows | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `isBluetoothAvailable` | yes | yes | yes | yes | yes |
| `bluetoothStateStream` | yes | yes | yes | yes | yes |
| `scan` / `scanResults` | yes | yes | yes | yes | yes |
| `connectedDevices` | yes | yes [1] | yes [1] | yes | yes |
| `connect` / `disconnect` | yes | yes | yes | yes | yes |
| `bondState` / `pair` | yes | no [2] | no [2] | no | yes |
| `bondStateStream` | yes | no | no | no | no |
| `discoverServices` | yes | yes | yes | yes [3] | yes |
| `gattServiceChangedStream` | yes [7] | yes | yes | yes | yes [8] |
| `readValue` / `writeValue` | yes | yes | yes | yes | yes |
| `setNotifiable` | yes | yes | yes | yes | yes |
| `requestMtu` | yes | yes [4] | yes [4] | yes | no [5] |
| `appleAccessorySetup` | no | yes [6] | no | no | no |

[1] CoreBluetooth requires service UUIDs when looking up system-connected
peripherals.

[2] CoreBluetooth does not expose app-initiated BLE pairing.

[3] On Windows, failure to enumerate the characteristics of any returned
service fails the whole discovery operation. Handle the discovery error and
retry after the peripheral is ready.

[4] CoreBluetooth reports the negotiated MTU but does not let an app request an
exact value.

[5] BlueZ negotiates ATT MTU automatically, but this implementation cannot
reliably retrieve the negotiated value and reports the operation as unsupported.

[6] AccessorySetupKit requires iOS 18 or later and explicit Info.plist setup.

[7] Android exposes GATT service-change callbacks on API 31 and later.

[8] Linux reports changes when BlueZ invalidates or replaces its resolved GATT
database.

`bluetoothStateStream` emits the latest state first for every listener. Android,
iOS, macOS, and Linux then emit live changes; Windows currently emits only the
current availability snapshot.

## License

This project is licensed under the terms of the
[BSD 3-Clause License](https://github.com/prefanatic/quick_blue/blob/master/LICENSE).
