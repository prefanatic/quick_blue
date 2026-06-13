import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_explorer_controller.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import '../fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuickBluePlatform previousPlatform;
  late FakeQuickBluePlatform platform;

  setUp(() {
    previousPlatform = QuickBluePlatform.instance;
    platform = FakeQuickBluePlatform();
    QuickBluePlatform.instance = platform;
  });

  tearDown(() async {
    QuickBluePlatform.instance = previousPlatform;
    await platform.dispose();
  });

  test('startScan and stopScan use scanResults lifecycle', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    await controller.startScan();
    await pumpEventQueue();
    expect(controller.scanning, isTrue);
    expect(platform.calls, contains('startScan'));

    platform.addScanResult(
      BlueScanResult(name: 'Heart Sensor', deviceId: 'device-a', rssi: -51),
    );
    await pumpEventQueue();

    expect(controller.discoveredDevices.single.deviceId, 'device-a');

    await controller.stopScan();
    await pumpEventQueue();

    expect(controller.scanning, isFalse);
    expect(platform.calls, contains('stopScan'));
    expect(
      controller.events.map((event) => event.message),
      contains('Scan stopped.'),
    );
  });

  test('keeps discovered device positions stable', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    await controller.startScan();
    await pumpEventQueue();

    platform.addScanResult(
      BlueScanResult(
        name: 'First',
        deviceId: 'device-a',
        rssi: -70,
        advertisedDateTime: DateTime(2026),
      ),
    );
    platform.addScanResult(
      BlueScanResult(
        name: 'Second',
        deviceId: 'device-b',
        rssi: -40,
        advertisedDateTime: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    );
    await pumpEventQueue();

    expect(
      controller.discoveredDevices.map((device) => device.deviceId),
      <String>['device-a', 'device-b'],
    );

    platform.addScanResult(
      BlueScanResult(
        name: 'First',
        deviceId: 'device-a',
        rssi: -45,
        advertisedDateTime: DateTime(2026, 1, 1, 0, 0, 2),
      ),
    );
    await pumpEventQueue();

    expect(
      controller.discoveredDevices.map((device) => device.deviceId),
      <String>['device-a', 'device-b'],
    );
    expect(controller.discoveredDevices.first.rssi, -45);
  });

  test('uses bluetoothStateStream for initial availability', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    expect(platform.calls, contains('bluetoothStateStream'));
    expect(controller.bluetoothState, BlueBluetoothState.poweredOn);
    expect(controller.bluetoothAvailable, isTrue);
    expect(controller.status, 'Bluetooth is ready.');
  });

  test('updates availability when Bluetooth state changes', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    platform.addBluetoothState(BlueBluetoothState.unauthorized);
    await pumpEventQueue();

    expect(controller.bluetoothState, BlueBluetoothState.unauthorized);
    expect(controller.bluetoothAvailable, isFalse);
    expect(controller.status, 'Bluetooth permission is missing.');
  });

  test('stops scanning when Bluetooth powers off', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    await controller.startScan();
    await pumpEventQueue();
    expect(controller.scanning, isTrue);

    platform.addBluetoothState(BlueBluetoothState.poweredOff);
    await pumpEventQueue();

    expect(controller.scanning, isFalse);
    expect(controller.status, 'Scan stopped because Bluetooth is off.');
    expect(platform.calls, contains('stopScan'));
  });

  test('startScan passes service UUID filters to the platform', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    controller.serviceFilterController.text = '180d, 180f';
    await controller.startScan();
    await pumpEventQueue();

    expect(platform.lastScanFilter?.serviceUuids, <String>['180d', '180f']);
  });

  test('selecting a different device clears discovered GATT state', () async {
    final controller = BleExplorerController();
    addTearDown(controller.dispose);
    await controller.initialBluetoothCheck;

    await controller.selectDevice('device-a');
    controller.services.add(
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
      ),
    );

    await controller.selectDevice('device-b');

    expect(controller.selectedDeviceId, 'device-b');
    expect(controller.services, isEmpty);
    expect(controller.latestValues, isEmpty);
  });
}
