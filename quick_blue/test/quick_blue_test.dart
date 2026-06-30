import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

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

  test('connect waits for the connected state', () async {
    platform.connectsImmediately = false;

    final connect = QuickBlue.connect('device-a');
    var connectCompleted = false;
    final connectCompletedFuture = connect.then((_) => connectCompleted = true);

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);
    expect(connectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await connectCompletedFuture;

    expect(connectCompleted, isTrue);
  });

  test('deprecated scanResultStream returns platform stream', () async {
    final results = <BlueScanResult>[];
    final subscription = QuickBlue.scanResultStream.listen(results.add);

    await pumpEventQueue();
    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(results.single.deviceId, 'device-a');
    expect(platform.calls, isEmpty);

    await subscription.cancel();
  });

  test('deprecated bluetoothDeviceStream returns platform stream', () async {
    final devices = <BluetoothDevice>[];
    final subscription = QuickBlue.bluetoothDeviceStream.listen(devices.add);

    await pumpEventQueue();
    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(devices.single.id, 'device-a');
    expect(platform.calls, <String>['startScan']);
    await subscription.cancel();
    await pumpEventQueue();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('bluetoothStateStream delegates to the platform', () async {
    final states = <BlueBluetoothState>[];
    final subscription = QuickBlue.bluetoothStateStream.listen(states.add);

    await pumpEventQueue();
    platform.addBluetoothState(BlueBluetoothState.poweredOff);
    await pumpEventQueue();

    expect(states, <BlueBluetoothState>[BlueBluetoothState.poweredOff]);
    expect(platform.calls, <String>['bluetoothStateStream']);

    await subscription.cancel();
  });

  test('disconnect waits for the disconnected state', () async {
    platform.disconnectsImmediately = false;

    final disconnect = QuickBlue.disconnect('device-a');
    var disconnectCompleted = false;
    final disconnectCompletedFuture = disconnect.then(
      (_) => disconnectCompleted = true,
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['disconnect device-a']);
    expect(disconnectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await disconnectCompletedFuture;

    expect(disconnectCompleted, isTrue);
  });

  test('bondState delegates to the platform device', () async {
    final state = await QuickBlue.bondState('device-a');

    expect(state, BluetoothBondState.notBonded);
    expect(platform.calls, <String>['bondState device-a']);
  });

  test('pair delegates to the platform device', () async {
    await QuickBlue.pair('device-a');

    expect(platform.calls, <String>['pair device-a']);
  });

  test('discoverGatt returns a discovered GATT view', () async {
    platform.discoveredServices = <BluetoothService>[
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
      ),
    ];

    final gatt = await QuickBlue.discoverGatt('device-a');

    expect(platform.calls, <String>['discoverServices device-a']);
    expect(gatt.deviceId, 'device-a');
    expect(gatt.services.map((service) => service.uuid), <String>['service-a']);
  });

  test('scanResults starts and stops scanning', () async {
    final results = <BlueScanResult>[];
    final subscription = QuickBlue.scanResults().listen(results.add);

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(results.single.deviceId, 'device-a');

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('scanResults forwards scan options', () async {
    final subscription = QuickBlue.scanResults(
      scanOptions: const ScanOptions(scanMode: ScanMode.balanced),
    ).listen((_) {});

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);
    expect(platform.lastScanOptions!.scanMode, ScanMode.balanced);

    await subscription.cancel();
  });

  test('scan emits BluetoothDevice objects', () async {
    final devices = <BluetoothDevice>[];
    final subscription = QuickBlue.scan().listen(devices.add);

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();

    expect(devices.single.id, 'device-a');

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('scanResults stream is single subscription', () async {
    final stream = QuickBlue.scanResults();
    final subscription = stream.listen((_) {});

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    expect(() => stream.listen((_) {}), throwsStateError);

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test(
    'notifications waits for setNotifiable before emitting values',
    () async {
      final setNotifiable = Completer<void>();
      platform.nextSetNotifiable = setNotifiable;
      final values = <Uint8List>[];
      final errors = <Object>[];
      final characteristic = QuickBlue.device(
        'device-a',
      ).characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen(
        values.add,
        onError: errors.add,
      );
      await pumpEventQueue();

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
      expect(values, isEmpty);
      expect(errors, isEmpty);

      setNotifiable.complete();
      await pumpEventQueue();

      expect(values, <Uint8List>[
        Uint8List.fromList(<int>[1, 2, 3]),
      ]);
      expect(errors, isEmpty);

      await subscription.cancel();
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test('legacy companionDissassociate delegates to the platform', () async {
    await QuickBlue.companionDissassociate(42);

    expect(platform.calls, <String>['companionDisassociate 42']);
  });

  test('companionAssociate delegates to the platform', () async {
    platform.companionAssociation = CompanionAssociation(
      id: 42,
      deviceId: 'device-a',
      displayName: 'Device A',
    );

    final device = await QuickBlue.companionAssociate(
      deviceId: 'device-a',
      scanFilter: ScanFilter(serviceUuids: const <String>['180d']),
    );

    expect(
      device,
      // ignore: deprecated_member_use
      CompanionDevice(id: 'device-a', name: 'Device A', associationId: 42),
    );
    expect(platform.calls, <String>['companionAssociate device-a [180d]']);
  });

  test('companionAssociate omits filter when no criteria passed', () async {
    platform.companionAssociation = null;

    final device = await QuickBlue.companionAssociate();

    expect(device, isNull);
    expect(platform.calls, <String>['companionAssociate null []']);
  });

  test(
    'companionAssociate keeps manufacturer data when service UUIDs are empty',
    () async {
      final manufacturerData = <int, Uint8List>{
        76: Uint8List.fromList(<int>[1, 2, 3]),
      };
      platform.companionAssociation = CompanionAssociation(id: 42);

      final device = await QuickBlue.companionAssociate(
        scanFilter: ScanFilter(
          serviceUuids: const <String>[],
          manufacturerData: manufacturerData,
        ),
      );

      expect(
        device,
        // ignore: deprecated_member_use
        CompanionDevice(id: '', name: '', associationId: 42),
      );
      final request = platform.lastCompanionAssociateRequest;
      expect(request, isNotNull);
      expect(
        request!.filters.single,
        BleCompanionFilter(
          serviceUuids: const <String>[],
          manufacturerData: manufacturerData,
        ),
      );
    },
  );

  test('getCompanionAssociations delegates to the platform', () async {
    platform.companionAssociations = <CompanionAssociation>[
      CompanionAssociation(
        id: 42,
        deviceId: 'device-a',
        displayName: 'Device A',
      ),
    ];

    final associations = await QuickBlue.getCompanionAssociations();

    // ignore: deprecated_member_use
    expect(associations, <CompanionDevice>[
      // ignore: deprecated_member_use
      CompanionDevice(id: 'device-a', name: 'Device A', associationId: 42),
    ]);
    expect(platform.calls, <String>['getCompanionAssociations']);
  });

  test(
    'getCompanionAssociations maps missing fields in legacy model',
    () async {
      platform.companionAssociations = <CompanionAssociation>[
        CompanionAssociation(id: 42),
      ];

      final associations = await QuickBlue.getCompanionAssociations();

      // ignore: deprecated_member_use
      expect(associations, <CompanionDevice>[
        // ignore: deprecated_member_use
        CompanionDevice(id: '', name: '', associationId: 42),
      ]);
      expect(platform.calls, <String>['getCompanionAssociations']);
    },
  );
}
