# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy on Android,
iOS, macOS, Windows, and Linux.

The repository is a Dart workspace:

- `quick_blue/`: app-facing plugin package and Android implementation
- `quick_blue_darwin/`: iOS and macOS implementation
- `quick_blue_linux/`: Linux implementation using BlueZ
- `quick_blue_windows/`: Windows implementation
- `quick_blue_platform_interface/`: shared APIs, models, and tests
- `quick_blue/example/`: BLE explorer example app and hardware smoke tests

## Install

Add the app-facing package from pub.dev. Its federated platform packages are
resolved transitively:

```yaml
dependencies:
  quick_blue: ^0.5.0
```

Then import it:

```dart
import 'package:quick_blue/quick_blue.dart';
```

Configure the Bluetooth permissions required by each target platform. The
example app includes working platform manifests and plist entries.

## Platform Support

| API | Android | iOS | macOS | Windows | Linux |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `isBluetoothAvailable` | yes | yes | yes | yes | yes |
| `bluetoothStateStream` | yes | yes | yes | yes | yes |
| `scan` / `scanResults` | yes | yes | yes | yes | yes |
| `connectedDevices` | yes | yes[1] | yes[1] | yes | yes |
| `connect` / `disconnect` | yes | yes | yes | yes | yes |
| `bondState` / `pair` | yes | no[2] | no[2] | no | yes |
| `discoverServices` | yes | yes | yes | yes | yes |
| `readValue` / `writeValue` | yes | yes | yes | yes | yes |
| `setNotifiable` | yes | yes | yes | yes | yes |
| `requestMtu` | yes | yes | yes | yes | no[3] |

`bluetoothStateStream` emits the latest available Bluetooth state first for each
listener. Android, iOS, macOS, and Linux then emit live state changes; Windows
currently emits only the current availability snapshot.

[1] iOS and macOS use CoreBluetooth's connected-peripheral lookup, which requires
service UUIDs to find system-connected peripherals.

[2] iOS and macOS do not expose app-initiated BLE pairing. CoreBluetooth prompts
automatically when an encrypted characteristic requires pairing.

[3] BlueZ negotiates ATT MTU automatically, but this implementation cannot
reliably retrieve the negotiated value and therefore reports the operation as
unsupported.

## Example Usage

Enable CoreBluetooth state preservation/restoration on iOS and macOS before any
other Bluetooth call:

```dart
await QuickBlue.configure(maintainState: true);
```

On iOS, apps that rely on restoration after background termination also need the
`bluetooth-central` background mode in `UIBackgroundModes`.

Scan for nearby peripherals:

```dart
final scanSubscription = QuickBlue.scanResults().listen((result) {
  print('${result.deviceId} ${result.name} RSSI=${result.rssi}');
});

// Stop scanning when the UI no longer needs results.
await scanSubscription.cancel();
```

Use common filters and scan options when they fit your scanner behavior:

```dart
final scanSubscription = QuickBlue.scanResults(
  scanFilter: ScanFilter(serviceUuids: ['180d'], rssi: -80),
  scanOptions: const ScanOptions(
    allowDuplicates: false,
    scanMode: ScanMode.balanced,
  ),
).listen((result) {
  print('${result.deviceId} ${result.name} RSSI=${result.rssi}');
});
```

Platform-specific scan options are also available when you need native scanner
controls such as Android PHY, CoreBluetooth solicited services, BlueZ pathloss,
or Windows signal-strength timing.

Use `QuickBlue.scan()` when you only need `BluetoothDevice` handles. Use
`QuickBlue.scanResults()` when you need advertisement fields such as RSSI,
service UUIDs, service data, or manufacturer data. `BluetoothDevice` and
`BluetoothCharacteristic` are lightweight handles: creating one does not start
platform work until you call an operation on it.

Get device handles for peripherals that are already connected:

```dart
final devices = await QuickBlue.connectedDevices(
  serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
);
```

Pass service UUIDs when targeting iOS or macOS; CoreBluetooth only returns
connected peripherals that match the supplied services.

Connect, discover services, and interact with a characteristic:

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
      print('${service.uuid}: ${service.characteristics}');
    }

    final characteristic = device.characteristic(serviceId, characteristicId);

    final notifications = characteristic.notifications().listen((value) {
      print('notification: $value');
    });

    final currentValue = await characteristic.read();
    print('read: $currentValue');

    await characteristic.write(
      Uint8List.fromList([0x01]),
      BleOutputProperty.withResponse,
    );

    await notifications.cancel();
  } finally {
    await device.disconnect().timeout(const Duration(seconds: 5));
  }
}
```

Pair with a device on platforms that expose app-initiated bonding:

```dart
final device = QuickBlue.device(deviceId);
final state = await device.bondState();
if (state != BluetoothBondState.bonded) {
  await device.pair();
}
```

The static `connect`, `disconnect`, `discoverServices`, `readValue`,
`writeValue`, and `setNotifiable` methods delegate through the same handle API.
Prefer keeping a `BluetoothDevice` when doing more than one operation.
Only one connect or disconnect operation may be pending for a device at a time.
Calling `disconnect()` while `connect()` is pending supersedes the connect,
which completes with `QuickBlueErrorCode.cancelled`, and then disconnects the
native device. This also makes a caller-side `connect().timeout(...)` safe to
follow with `disconnect()` and a retry. Other overlapping operations fail with
`QuickBlueErrorCode.invalidState` instead of consuming an event intended for
the first operation. Different devices can still connect concurrently.

### Multiple Flutter engines

Quick Blue coordinates each device connection across Flutter engines in the
same application process. This covers foreground UI engines, Workmanager
engines, and engines hosted by an Android foreground service.

On every supported platform, engines share one process-wide native GATT
connection.
Calling `connect()` attaches that engine to the existing connection (or starts
it when there is none), and connection, discovery, MTU, and notification-value
events are delivered to every attached engine. GATT operations from all engines
are sent through that shared native connection (and serialized through
Android's native operation queue). Calling `disconnect()` detaches only the
calling engine; the physical connection closes after the final engine
disconnects or detaches. Notification ownership is reference-counted across
engines so one engine cannot disable another engine's active subscription. On
Linux, BlueZ owns the shared system connection while per-engine D-Bus client
memberships serialize final disconnect. On Windows, the WinRT device and GATT
session transfer to a surviving engine when their original host detaches.
For a foreground handoff, attach the new engine before disconnecting the old
one. Cancel the old engine's Dart notification subscriptions as part of its
normal teardown:

```dart
await foregroundDevice.connect();
await backgroundNotifications.cancel();
await backgroundDevice.disconnect();
```

This does not require the old Flutter engine to terminate. On Darwin, a stable
CoreBluetooth device UUID can be passed directly to `QuickBlue.device(id)` and
connected without a preceding scan or `connectedDevices()` lookup, provided
CoreBluetooth already knows that peripheral.

Dart subscriptions and characteristic handles remain engine-local on every
platform and must be created in each engine.

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

Use `characteristic.notifications()` when a subscription should own notification
setup and teardown. Use `characteristic.valueStream` with
`characteristic.setNotifiable(...)` when callers need to subscribe before
enabling notifications or manage notification lifetime separately.
Concurrent `notifications()` listeners for the same characteristic share one
native subscription; updates are disabled after the final listener cancels.

`ScanFilter.rssi` and common `ScanOptions` fields are applied consistently by
the Dart lifecycle APIs and mapped to native filters where the platform supports
them. Omitted common options preserve Quick Blue's existing platform defaults.

## Platform Notes

- Android companion-device association is available through
  `QuickBlue.companion`. Use `isSupported()` before showing Android-only
  association UI, then call `associate()`, `associations()`, and
  `disassociate()`. The older static companion methods remain as deprecated
  compatibility wrappers.
- Android and Linux expose app-initiated BLE pairing through
  `BluetoothDevice.pair()`. Android shows the system pairing flow and the
  returned future completes when bonding succeeds or fails.
- iOS and macOS use CoreBluetooth. `requestMtu` returns the negotiated MTU
  currently in effect; CoreBluetooth does not let apps request an exact MTU or
  manually start BLE pairing.
- Linux requires BlueZ. BlueZ negotiates ATT MTU automatically, so
  `requestMtu` is unsupported rather than returning an estimated value.
- Windows has platform-specific service discovery behavior. App-initiated
  pairing is not currently implemented by this plugin.

## Development

Set up dependencies from the repository root:

```sh
flutter pub get
```

Run the common checks:

```sh
dart format .
flutter analyze
```

Run package-focused tests:

```sh
cd quick_blue_platform_interface && flutter test
cd quick_blue_darwin && flutter test
cd quick_blue/example && flutter test
```

Run hardware-backed integration tests from the example app when changing scan,
connect, service discovery, or device-switching behavior:

```sh
cd quick_blue/example

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d macos

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_ui_switch_test.dart -d macos

flutter test integration_test/android_multi_engine_test.dart -d ANDROID_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_ID'

flutter test integration_test/ios_multi_engine_test.dart -d IOS_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID='SERVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'
```

These tests need Bluetooth permission, powered-on Bluetooth hardware, and
nearby BLE advertisements. `ble_smoke_test.dart` targets all quick_blue
platforms and includes read coverage plus opt-in write coverage for known
test peripherals. `ble_ui_switch_test.dart` targets macOS and Linux. See
[`quick_blue/example/README.md`](quick_blue/example/README.md) for optional
Dart defines that target specific devices.

The example app also includes a hardware-backed characteristic benchmark for
high-volume notification throughput and read latency:

```sh
cd quick_blue/example

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_characteristic_benchmark_test.dart -d macos \
    --dart-define=QUICK_BLUE_BENCHMARK_DEVICE_ID='DEVICE_ID' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID='SERVICE_UUID' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'
```

Run the Windows smoke test in a Dockur Windows VM from the repository root:

```sh
QUICK_BLUE_WINDOWS_USB_VENDOR_ID=0x0a12 \
QUICK_BLUE_WINDOWS_USB_PRODUCT_ID=0x0001 \
  scripts/windows-integration-test.sh
```

The script starts `dockurr/windows`, mounts this checkout into the guest, and
runs `quick_blue/example/integration_test/ble_smoke_test.dart` on the Windows
Flutter target. Pass the same `QUICK_BLUE_SMOKE_*` environment variables shown
in the example README to target a known BLE device. The first run installs
Windows, Visual Studio Build Tools, Git, and Flutter into persistent state under
`.dart_tool/dockur_windows/`. During that install it also registers a Windows
logon task so later runs reuse the same VM and execute the latest generated
test script from the shared folder. The guest keeps a synced NTFS checkout at
`C:\quick_blue_workspace\quick_blue` so Flutter can reuse `.dart_tool` and
`build` output between runs. Set `QUICK_BLUE_WINDOWS_CLEAN_WORKTREE=1` to
recreate that checkout without reinstalling Windows.

## Generated Code

Pigeon schemas and generated platform bindings must stay in sync. Regenerate
after changing a Pigeon file:

```sh
cd quick_blue
dart run pigeon --input pigeons/messages.dart

cd ../quick_blue_darwin
dart run pigeon --input pigeons/messages.dart
```

## License

This repository is licensed under the terms of [`LICENSE`](LICENSE).
