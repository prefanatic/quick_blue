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

This package is not published on pub.dev yet. Add it from your chosen Git
source or local checkout:

```yaml
dependencies:
  quick_blue:
    git:
      url: <repository-url>
      path: quick_blue
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
| `connectedDevices` | yes | yes* | yes* | yes | yes |
| `connect` / `disconnect` | yes | yes | yes | yes | yes |
| `discoverServices` | yes | yes | yes | yes | yes |
| `readValue` / `writeValue` | yes | yes | yes | yes | yes |
| `setNotifiable` | yes | yes | yes | yes | yes |
| `requestMtu` | yes | yes | yes | yes | yes |

`bluetoothStateStream` emits the current Bluetooth state first. Android, iOS,
macOS, and Linux then emit live state changes; Windows currently emits only the
current availability snapshot.

* iOS and macOS use CoreBluetooth's connected-peripheral lookup, which requires
  service UUIDs to find system-connected peripherals.

## Example Usage

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

Use `QuickBlue.scan()` when you only need device handles. Use
`QuickBlue.scanResults()` when you need advertisement fields such as RSSI,
service UUIDs, service data, or manufacturer data. `ScanFilter.rssi` and common
`ScanOptions` fields are applied consistently by the Dart lifecycle APIs and
mapped to native filters where the platform supports them. Omitted common
options preserve Quick Blue's existing platform defaults.

Get device handles for peripherals that are already connected:

```dart
final devices = await QuickBlue.connectedDevices(
  serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
);
```

Pass service UUIDs when targeting iOS or macOS; CoreBluetooth only returns
connected peripherals that match the supplied services.

## Platform Notes

- Android companion-device association is available through
  `QuickBlue.companion`. Use `isSupported()` before showing Android-only
  association UI, then call `associate()`, `associations()`, and
  `disassociate()`. The older static companion methods remain as deprecated
  compatibility wrappers.
- iOS and macOS use CoreBluetooth. `requestMtu` returns the negotiated MTU
  currently in effect; CoreBluetooth does not let apps request an exact MTU.
- Linux requires BlueZ.
- Windows has platform-specific service discovery behavior.

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
```

These tests need Bluetooth permission, powered-on Bluetooth hardware, and
nearby BLE advertisements. `ble_smoke_test.dart` targets all quick_blue
platforms and includes read coverage plus opt-in write coverage for known
test peripherals. `ble_ui_switch_test.dart` targets macOS and Linux. See
[`quick_blue/example/README.md`](quick_blue/example/README.md) for optional
Dart defines that target specific devices.

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
