import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BlueScanResult exposes advertising manufacturer bytes', () {
    final manufacturerDataHead = Uint8List.fromList(<int>[0x4c, 0x00, 1, 2]);
    final manufacturerData = Uint8List.fromList(<int>[1, 2]);
    final serviceData = <String, Uint8List>{
      '0000180d-0000-1000-8000-00805f9b34fb': Uint8List.fromList(<int>[3, 4]),
    };

    final result = BlueScanResult(
      name: 'device',
      deviceId: 'device-a',
      manufacturerDataHead: manufacturerDataHead,
      manufacturerData: manufacturerData,
      rssi: -42,
      serviceUuids: const <String>['180d'],
      serviceData: serviceData,
    );

    expect(result.manufacturerDataHead, manufacturerDataHead);
    expect(result.manufacturerData, manufacturerData);
    expect(result.serviceData, serviceData);
    expect(
      result.toMap(),
      containsPair('manufacturerDataHead', manufacturerDataHead),
    );
    expect(result.toMap(), containsPair('manufacturerData', manufacturerData));
    expect(result.toMap(), containsPair('serviceData', serviceData));
  });

  test('BlueScanResult keeps scan data from map payloads', () {
    final manufacturerDataHead = Uint8List.fromList(<int>[0x4c, 0x00, 1, 2]);
    final manufacturerData = Uint8List.fromList(<int>[1, 2]);
    final serviceData = <String, Uint8List>{
      '0000180d-0000-1000-8000-00805f9b34fb': Uint8List.fromList(<int>[3, 4]),
    };

    final result = BlueScanResult.fromMap(<String, dynamic>{
      'name': 'device',
      'deviceId': 'device-a',
      'manufacturerDataHead': manufacturerDataHead,
      'manufacturerData': manufacturerData,
      'rssi': -42,
      'serviceUuids': <String>['180d'],
      'serviceData': serviceData,
    });

    expect(result.manufacturerDataHead, manufacturerDataHead);
    expect(result.manufacturerData, manufacturerData);
    expect(result.serviceUuids, <String>['180d']);
    expect(result.serviceData, serviceData);
  });

  test(
    'bluetoothStateStream emits the current availability snapshot',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      expect(
        await platform.bluetoothStateStream.first,
        BlueBluetoothState.poweredOn,
      );
    },
  );

  test(
    'bluetoothStateStream supports concurrent listeners and replays latest',
    () async {
      final platform = _FakeBluetoothStatePlatform();
      addTearDown(platform.dispose);

      final stream = platform.bluetoothStateStream;
      expect(stream.isBroadcast, isTrue);

      final firstStates = <BlueBluetoothState>[];
      final firstSubscription = stream.listen(firstStates.add);

      await pumpEventQueue();
      expect(platform.bluetoothStateEventListenCount, 1);
      expect(firstStates, <BlueBluetoothState>[BlueBluetoothState.poweredOn]);

      platform.addBluetoothState(BlueBluetoothState.poweredOff);
      await pumpEventQueue();
      expect(firstStates, <BlueBluetoothState>[
        BlueBluetoothState.poweredOn,
        BlueBluetoothState.poweredOff,
      ]);

      final secondStates = <BlueBluetoothState>[];
      final secondSubscription = stream.listen(secondStates.add);

      await pumpEventQueue();
      expect(platform.bluetoothStateEventListenCount, 1);
      expect(secondStates, <BlueBluetoothState>[BlueBluetoothState.poweredOff]);

      platform.addBluetoothState(BlueBluetoothState.unauthorized);
      await pumpEventQueue();
      expect(firstStates, <BlueBluetoothState>[
        BlueBluetoothState.poweredOn,
        BlueBluetoothState.poweredOff,
        BlueBluetoothState.unauthorized,
      ]);
      expect(secondStates, <BlueBluetoothState>[
        BlueBluetoothState.poweredOff,
        BlueBluetoothState.unauthorized,
      ]);

      final thirdStates = <BlueBluetoothState>[];
      final thirdSubscription = platform.bluetoothStateStream.listen(
        thirdStates.add,
      );

      await pumpEventQueue();
      expect(platform.bluetoothStateEventListenCount, 1);
      expect(thirdStates, <BlueBluetoothState>[
        BlueBluetoothState.unauthorized,
      ]);

      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await thirdSubscription.cancel();
      expect(platform.bluetoothStateEventCancelCount, 1);

      final fourthStates = <BlueBluetoothState>[];
      final fourthSubscription = stream.listen(fourthStates.add);

      await pumpEventQueue();
      expect(platform.bluetoothStateEventListenCount, 2);
      expect(fourthStates, <BlueBluetoothState>[
        BlueBluetoothState.unauthorized,
      ]);

      await fourthSubscription.cancel();
    },
  );

  test('default platform reports missing implementation', () async {
    await expectLater(
      QuickBluePlatform.instance.isBluetoothAvailable(),
      throwsA(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.unsupported,
            )
            .having(
              (error) => error.operation,
              'operation',
              'isBluetoothAvailable',
            )
            .having(
              (error) => error.message,
              'message',
              'No QuickBlue platform implementation has been registered.',
            ),
      ),
    );
  });

  test('scan starts scanning, emits devices, and stops on cancel', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final devices = <String>[];
    final subscription = platform.scan().listen((device) {
      devices.add(device.id);
    });

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();
    expect(devices, <String>['device-a']);

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('scanResults rethrows startScan errors', () async {
    final platform = _FakeQuickBluePlatform(
      startScanError: StateError('scan failed'),
    );
    addTearDown(platform.dispose);

    await expectLater(
      platform.scanResults().drain<void>(),
      throwsA(isA<StateError>()),
    );
    expect(platform.calls, <String>['startScan']);
  });

  test('bluetoothDeviceStream is scan stream alias', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final ids = <String>[];
    final subscription = platform.bluetoothDeviceStream.listen((device) {
      ids.add(device.id);
    });

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();
    expect(ids, <String>['device-a']);

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test('platform singleton can be swapped for testing', () async {
    final original = QuickBluePlatform.instance;
    addTearDown(() {
      QuickBluePlatform.instance = original;
    });

    final fake = _FakeQuickBluePlatform();
    addTearDown(fake.dispose);

    QuickBluePlatform.instance = fake;

    expect(QuickBluePlatform.instance, same(fake));
  });

  test('connectedDevices returns BluetoothDevice objects', () async {
    final platform = _FakeQuickBluePlatform(
      connectedDeviceIds: const <String>['device-a', 'device-b'],
    );
    addTearDown(platform.dispose);

    final devices = await platform.connectedDevices(
      serviceUuids: const <String>['180d'],
    );

    expect(devices.map((device) => device.id), <String>[
      'device-a',
      'device-b',
    ]);
    expect(platform.calls, <String>['connectedDevices [180d]']);
  });

  test(
    'scanResults starts scanning, emits results, and stops on cancel',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final results = <BlueScanResult>[];
      final subscription = platform.scanResults().listen(results.add);

      await pumpEventQueue();
      expect(platform.calls, <String>['startScan']);

      platform.addScanResult('device-a');
      await pumpEventQueue();
      expect(results.single.deviceId, 'device-a');

      await subscription.cancel();
      expect(platform.calls, <String>['startScan', 'stopScan']);
    },
  );

  test('scanResults stream is single subscription', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final stream = platform.scanResults();
    final subscription = stream.listen((_) {});

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    expect(() => stream.listen((_) {}), throwsStateError);

    await subscription.cancel();
    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test(
    'scanResults calls share the active scan for matching filters',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final firstResults = <String>[];
      final secondResults = <String>[];
      final firstSubscription = platform.scanResults().listen(
        (result) => firstResults.add(result.deviceId),
      );
      final secondSubscription = platform.scanResults().listen(
        (result) => secondResults.add(result.deviceId),
      );

      await pumpEventQueue();
      expect(platform.calls, <String>['startScan']);

      platform.addScanResult('device-a');
      await pumpEventQueue();

      expect(firstResults, <String>['device-a']);
      expect(secondResults, <String>['device-a']);

      await firstSubscription.cancel();
      expect(platform.calls, <String>['startScan']);

      await secondSubscription.cancel();
      expect(platform.calls, <String>['startScan', 'stopScan']);
    },
  );

  test('scanResults filters results below the RSSI threshold', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final results = <String>[];

    final subscription = platform
        .scanResults(scanFilter: ScanFilter(rssi: -70))
        .listen((result) => results.add(result.deviceId));

    await pumpEventQueue();
    platform
      ..addScanResult('device-a', rssi: -80)
      ..addScanResult('device-b', rssi: -60);
    await pumpEventQueue();

    expect(results, <String>['device-b']);
    expect(platform.lastScanFilter!.rssi, -70);

    await subscription.cancel();
  });

  test(
    'scanResults drops duplicate devices when duplicates are disabled',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final results = <String>[];

      final subscription = platform
          .scanResults(scanOptions: const ScanOptions(allowDuplicates: false))
          .listen((result) => results.add(result.deviceId));

      await pumpEventQueue();
      platform
        ..addScanResult('device-a')
        ..addScanResult('device-a')
        ..addScanResult('device-b');
      await pumpEventQueue();

      expect(results, <String>['device-a', 'device-b']);

      await subscription.cancel();
    },
  );

  test('scanResults rejects a different filter while scanning', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final firstSubscription = platform
        .scanResults(scanFilter: ScanFilter(serviceUuids: <String>['a']))
        .listen((_) {});

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    final errors = <Object>[];
    final secondSubscription = platform
        .scanResults(scanFilter: ScanFilter(serviceUuids: <String>['b']))
        .listen((_) {}, onError: errors.add);

    await pumpEventQueue();

    expect(
      errors.single,
      isA<QuickBlueException>().having(
        (error) => error.code,
        'code',
        QuickBlueErrorCode.invalidState,
      ),
    );
    expect(platform.calls, <String>['startScan']);

    await firstSubscription.cancel();
    await secondSubscription.cancel();

    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

  test(
    'scanResults rejects another scan with mismatched manufacturer data length',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final firstSubscription = platform
          .scanResults(
            scanFilter: ScanFilter(
              manufacturerData: <int, Uint8List>{
                76: Uint8List.fromList(<int>[1]),
              },
            ),
          )
          .listen((_) {});
      await pumpEventQueue();
      expect(platform.calls, <String>['startScan']);

      final errors = <Object>[];
      final secondSubscription = platform
          .scanResults(
            scanFilter: ScanFilter(
              manufacturerData: <int, Uint8List>{
                76: Uint8List.fromList(<int>[1]),
                77: Uint8List.fromList(<int>[2]),
              },
            ),
          )
          .listen((_) {}, onError: errors.add);

      await pumpEventQueue();
      expect(
        errors.single,
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.invalidState,
        ),
      );
      expect(platform.calls, <String>['startScan']);

      await firstSubscription.cancel();
      await secondSubscription.cancel();
    },
  );

  test(
    'scanResults rejects another scan with mismatched manufacturer data values',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final firstSubscription = platform
          .scanResults(
            scanFilter: ScanFilter(
              manufacturerData: <int, Uint8List>{
                76: Uint8List.fromList(<int>[1]),
              },
            ),
          )
          .listen((_) {});
      await pumpEventQueue();
      expect(platform.calls, <String>['startScan']);

      final errors = <Object>[];
      final secondSubscription = platform
          .scanResults(
            scanFilter: ScanFilter(
              manufacturerData: <int, Uint8List>{
                76: Uint8List.fromList(<int>[2]),
              },
            ),
          )
          .listen((_) {}, onError: errors.add);

      await pumpEventQueue();
      expect(
        errors.single,
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.invalidState,
        ),
      );

      await firstSubscription.cancel();
      await secondSubscription.cancel();
    },
  );

  test('scanResults emits results after startScan completes', () async {
    final startScan = Completer<void>();
    final platform = _FakeQuickBluePlatform(
      startScanCompletions: <Completer<void>>[startScan],
    );
    addTearDown(platform.dispose);

    final results = <BlueScanResult>[];
    final subscription = platform.scanResults().listen(results.add);

    await pumpEventQueue();
    expect(platform.calls, <String>['startScan']);

    platform.addScanResult('device-a');
    await pumpEventQueue();
    expect(results, isEmpty);

    startScan.complete();
    await pumpEventQueue();
    expect(results, isEmpty);

    platform.addScanResult('device-b');
    await pumpEventQueue();
    expect(results.single.deviceId, 'device-b');

    await subscription.cancel();
  });

  test(
    'scanResults stops scanning after pending start completes on cancel',
    () async {
      final startScan = Completer<void>();
      final platform = _FakeQuickBluePlatform(
        startScanCompletions: <Completer<void>>[startScan],
      );
      addTearDown(platform.dispose);

      final subscription = platform.scanResults().listen((_) {});
      await pumpEventQueue();

      final cancel = subscription.cancel();
      var cancelCompleted = false;
      final cancelCompletedFuture = cancel.then((_) => cancelCompleted = true);
      await pumpEventQueue();

      expect(platform.calls, <String>['startScan']);
      expect(cancelCompleted, isFalse);

      startScan.complete();
      await cancelCompletedFuture;

      expect(platform.calls, <String>['startScan', 'stopScan']);
      expect(cancelCompleted, isTrue);
    },
  );

  test('scan forwards the scan filter to startScan', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final filter = ScanFilter(
      serviceUuids: const <String>['180d'],
      manufacturerData: <int, Uint8List>{
        76: Uint8List.fromList(<int>[1, 2, 3]),
      },
    );

    final subscription = platform.scan(scanFilter: filter).listen((_) {});

    await pumpEventQueue();
    expect(platform.lastScanFilter, isNot(same(filter)));
    expect(platform.lastScanFilter!.serviceUuids, filter.serviceUuids);
    expect(
      platform.lastScanFilter!.manufacturerData![76],
      orderedEquals(<int>[1, 2, 3]),
    );

    await subscription.cancel();
  });

  test('scan forwards scan options to startScan', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final solicitedServiceUuids = <String>['180d'];
    final options = ScanOptions(
      darwin: DarwinScanOptions(
        allowDuplicates: false,
        solicitedServiceUuids: solicitedServiceUuids,
      ),
      linux: const LinuxScanOptions(rssi: -80),
    );

    final subscription = platform.scan(scanOptions: options).listen((_) {});
    solicitedServiceUuids.add('180f');

    await pumpEventQueue();
    expect(platform.lastScanOptions, isNot(same(options)));
    expect(platform.lastScanOptions!.darwin.allowDuplicates, isFalse);
    expect(platform.lastScanOptions!.darwin.solicitedServiceUuids, <String>[
      '180d',
    ]);
    expect(platform.lastScanOptions!.linux.rssi, -80);

    await subscription.cancel();
  });

  test(
    'scanResults rejects another scan with mismatched scan options',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final firstSubscription = platform
          .scanResults(
            scanOptions: const ScanOptions(linux: LinuxScanOptions(rssi: -80)),
          )
          .listen((_) {});

      await pumpEventQueue();
      expect(platform.calls, <String>['startScan']);

      final error = await platform
          .scanResults(
            scanOptions: const ScanOptions(linux: LinuxScanOptions(rssi: -70)),
          )
          .drain<void>()
          .then<Object?>((_) => null, onError: (Object error) => error);

      expect(
        error,
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.invalidState,
        ),
      );
      expect(platform.calls, <String>['startScan']);

      await firstSubscription.cancel();
      expect(platform.calls, <String>['startScan', 'stopScan']);
    },
  );

  test('device streams only emit events for that device', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final device = platform.device('device-a');

    final connection = expectLater(
      device.connectionStateStream.map((event) => event.state),
      emits(BlueConnectionState.connected),
    );
    final service = expectLater(
      device.serviceDiscoveryStream.map((event) => event.uuid),
      emits('service-a'),
    );
    final value = expectLater(
      device.characteristicValueStream.map((event) => event.value),
      emits(Uint8List.fromList(<int>[1, 2, 3])),
    );

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    platform.handleServiceDiscovered('device-b', 'service-b', const []);
    platform.handleCharacteristicValueChanged(
      'device-b',
      'service-b',
      'characteristic-b',
      Uint8List.fromList(<int>[9]),
    );

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    platform.handleServiceDiscovered('device-a', 'service-a', [
      BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
    ]);
    platform.handleCharacteristicValueChanged(
      'device-a',
      'service-a',
      'characteristic-a',
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    await Future.wait(<Future<void>>[connection, service, value]);
  });

  test(
    'legacy callbacks are still called while streams receive events',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final legacyConnectionEvents = <BluetoothConnectionStateChange>[];
      final streamEvent = platform.connectionStateStream.first;

      platform.onConnectionChanged = (deviceId, state, status) {
        legacyConnectionEvents.add(
          BluetoothConnectionStateChange(
            deviceId: deviceId,
            state: state,
            status: status,
          ),
        );
      };

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.success,
      );

      expect((await streamEvent).deviceId, 'device-a');
      expect(legacyConnectionEvents, hasLength(1));
      expect(legacyConnectionEvents.single.deviceId, 'device-a');
      expect(
        legacyConnectionEvents.single.state,
        BlueConnectionState.connected,
      );
      expect(legacyConnectionEvents.single.status, BleStatus.success);
    },
  );

  test(
    'default service discovery callback maps raw ids to characteristics',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final services = <BluetoothService>[];
      final sub = platform.serviceDiscoveryStream.listen(services.add);

      platform.onServiceDiscovered?.call(
        'device-a',
        'service-a',
        const <String>['characteristic-a'],
      );
      await pumpEventQueue();

      expect(services, <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      ]);

      await sub.cancel();
    },
  );

  test('service discovery stream delivery remains asynchronous', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final services = <BluetoothService>[];
    final sub = platform.serviceDiscoveryStream.listen(services.add);

    platform.handleServiceDiscovered(
      'device-a',
      'service-a',
      <BluetoothCharacteristicInfo>[
        BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
      ],
    );

    expect(services, isEmpty);

    await pumpEventQueue();
    expect(services.map((service) => service.uuid), <String>['service-a']);

    await sub.cancel();
  });

  test('custom onServiceDiscovered callback receives callbacks', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final services = <BluetoothService>[];
    final customServices = <BluetoothService>[];
    final sub = platform.serviceDiscoveryStream.listen(services.add);

    platform.onServiceDiscovered = (deviceId, serviceId, characteristicIds) {
      customServices.add(
        BluetoothService(
          deviceId: deviceId,
          uuid: serviceId,
          characteristics: characteristicIds,
        ),
      );
    };

    platform.handleServiceDiscovered(
      'device-a',
      'service-a',
      <BluetoothCharacteristicInfo>[
        BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
      ],
    );
    await pumpEventQueue();

    expect(services, hasLength(1));
    expect(customServices, hasLength(1));
    expect(customServices.single.deviceId, 'device-a');
    expect(customServices.single.uuid, 'service-a');
    expect(customServices.single.characteristics, ['characteristic-a']);

    await sub.cancel();
  });

  test('default onValueChanged emits stream events', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final characteristicValues = <BluetoothCharacteristicValue>[];
    final sub = platform.characteristicValueStream.listen(
      characteristicValues.add,
    );

    final defaultCallback = platform.onValueChanged;
    defaultCallback?.call(
      'device-a',
      'characteristic-a',
      Uint8List.fromList(<int>[1]),
    );
    await pumpEventQueue();

    expect(characteristicValues.single.serviceId, isEmpty);
    expect(characteristicValues.single.characteristicId, 'characteristic-a');
    expect(characteristicValues.single.value, Uint8List.fromList(<int>[1]));

    await sub.cancel();
  });

  test(
    'custom onValueChanged receives callbacks in addition to stream events',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final events = <BluetoothCharacteristicValue>[];
      final characteristicValues = <BluetoothCharacteristicValue>[];
      final sub = platform.characteristicValueStream.listen(
        characteristicValues.add,
      );

      platform.onValueChanged = (deviceId, characteristicId, value) {
        events.add(
          BluetoothCharacteristicValue(
            deviceId: deviceId,
            serviceId: 'custom-service',
            characteristicId: characteristicId,
            value: value,
          ),
        );
      };

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[2]),
      );
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.deviceId, 'device-a');
      expect(events.single.serviceId, 'custom-service');
      expect(events.single.characteristicId, 'characteristic-a');
      expect(events.single.value, Uint8List.fromList(<int>[2]));
      expect(characteristicValues, hasLength(1));
      expect(characteristicValues.single.serviceId, 'service-a');
      expect(characteristicValues.single.characteristicId, 'characteristic-a');
      expect(characteristicValues.single.value, Uint8List.fromList(<int>[2]));

      await sub.cancel();
    },
  );

  test('BluetoothDevice delegates commands to platform', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final value = Uint8List.fromList(<int>[1, 2, 3]);

    await device.connect();
    await device.bondState();
    await device.pair();
    await device.discoverServices();
    await device.setNotifiable(
      'service-a',
      'characteristic-a',
      BleInputProperty.notification,
    );
    await device.writeValue(
      'service-a',
      'characteristic-a',
      value,
      BleOutputProperty.withResponse,
    );
    await device.requestMtu(128);
    await device.openL2cap(25);
    await device.disconnect();

    expect(platform.calls, <String>[
      'connect device-a',
      'bondState device-a',
      'pair device-a',
      'discoverServices device-a',
      'setNotifiable device-a service-a characteristic-a notification',
      'writeValue device-a service-a characteristic-a withResponse [1, 2, 3]',
      'requestMtu device-a 128',
      'openL2cap device-a 25',
      'disconnect device-a',
    ]);
  });

  test('BluetoothDevice.bondStateStream filters device transitions', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final events = <BluetoothBondStateChange>[];
    final subscription = platform
        .device('device-a')
        .bondStateStream
        .listen(events.add);

    platform
      ..addBondStateChange(
        'device-b',
        BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      )
      ..addBondStateChange(
        'device-a',
        BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      );
    await pumpEventQueue();

    expect(events, const <BluetoothBondStateChange>[
      BluetoothBondStateChange(
        deviceId: 'device-a',
        state: BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      ),
    ]);
    await subscription.cancel();
  });

  test('BluetoothDevice.waitForBondState returns an existing state', () async {
    final platform = _FakeQuickBluePlatform(
      currentBondState: BluetoothBondState.bonded,
    );
    addTearDown(platform.dispose);

    final state = await platform
        .device('device-a')
        .waitForBondState(BluetoothBondState.bonded);

    expect(state, BluetoothBondState.bonded);
    expect(platform.calls, <String>['bondState device-a']);
  });

  test('BluetoothDevice.waitForBondState awaits a matching event', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final waiting = platform
        .device('device-a')
        .waitForBondState(BluetoothBondState.bonded);

    await pumpEventQueue();
    expect(platform.calls, <String>['bondState device-a']);

    platform
      ..addBondStateChange(
        'device-b',
        BluetoothBondState.bonded,
        previousState: BluetoothBondState.bonding,
      )
      ..addBondStateChange(
        'device-a',
        BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      );
    await pumpEventQueue();

    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonded,
      previousState: BluetoothBondState.bonding,
    );
    expect(await waiting, BluetoothBondState.bonded);
  });

  test('BluetoothDevice.connect waits for connected state', () async {
    final platform = _FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);

    final connect = platform.device('device-a').connect();
    var connectCompleted = false;
    final connectCompletedFuture = connect.then((_) => connectCompleted = true);

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);
    expect(connectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await pumpEventQueue();
    expect(connectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await connectCompletedFuture;

    expect(connectCompleted, isTrue);
  });

  test('BluetoothDevice.connect completes with an error on failure', () async {
    final platform = _FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);

    final connect = platform.device('device-a').connect();
    final connectExpectation = expectLater(
      connect,
      throwsA(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.operationFailed,
            )
            .having((error) => error.operation, 'operation', 'connect')
            .having(
              (error) => error.message,
              'message',
              'Failed to connect to Bluetooth device device-a.',
            ),
      ),
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.failure,
    );

    await connectExpectation;
  });

  test('BluetoothDevice.connect retries a busy shared connection', () async {
    final platform = _FakeQuickBluePlatform(
      connectErrors: <Object>[
        const QuickBlueException(
          code: QuickBlueErrorCode.deviceBusy,
          message: 'busy',
        ),
      ],
    );
    addTearDown(platform.dispose);

    await platform.device('device-a').connect();

    expect(platform.calls, <String>['connect device-a', 'connect device-a']);
  });

  test('BluetoothDevice.connect ignores other-device failure events', () async {
    final platform = _FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);

    final connect = platform.device('device-a').connect();
    var connectCompleted = false;
    Object? connectError;
    final connectCompletedFuture = connect.then<void>(
      (_) => connectCompleted = true,
      onError: (Object error) => connectError = error,
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.disconnected,
      BleStatus.failure,
    );
    await pumpEventQueue();

    expect(connectCompleted, isFalse);
    expect(connectError, isNull);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await connectCompletedFuture;

    expect(connectCompleted, isTrue);
    expect(connectError, isNull);
  });

  test('BluetoothDevice.disconnect waits for disconnected state', () async {
    final platform = _FakeQuickBluePlatform(disconnectsImmediately: false);
    addTearDown(platform.dispose);

    final disconnect = platform.device('device-a').disconnect();
    var disconnectCompleted = false;
    final disconnectCompletedFuture = disconnect.then(
      (_) => disconnectCompleted = true,
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['disconnect device-a']);
    expect(disconnectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await pumpEventQueue();
    expect(disconnectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await disconnectCompletedFuture;

    expect(disconnectCompleted, isTrue);
  });

  test(
    'BluetoothDevice.disconnect completes with an error on failure',
    () async {
      final platform = _FakeQuickBluePlatform(disconnectsImmediately: false);
      addTearDown(platform.dispose);

      final disconnect = platform.device('device-a').disconnect();
      final disconnectExpectation = expectLater(
        disconnect,
        throwsA(
          isA<QuickBlueException>()
              .having(
                (error) => error.code,
                'code',
                QuickBlueErrorCode.operationFailed,
              )
              .having((error) => error.operation, 'operation', 'disconnect')
              .having(
                (error) => error.message,
                'message',
                'Failed to disconnect Bluetooth device device-a.',
              ),
        ),
      );

      await pumpEventQueue();
      expect(platform.calls, <String>['disconnect device-a']);

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.failure,
      );

      await disconnectExpectation;
    },
  );

  test(
    'BluetoothDevice.disconnect ignores other-device failure events',
    () async {
      final platform = _FakeQuickBluePlatform(disconnectsImmediately: false);
      addTearDown(platform.dispose);

      final disconnect = platform.device('device-a').disconnect();
      var disconnectCompleted = false;
      Object? disconnectError;
      final disconnectCompletedFuture = disconnect.then<void>(
        (_) => disconnectCompleted = true,
        onError: (Object error) => disconnectError = error,
      );

      await pumpEventQueue();
      expect(platform.calls, <String>['disconnect device-a']);

      platform.onConnectionChanged!(
        'device-b',
        BlueConnectionState.connected,
        BleStatus.failure,
      );
      await pumpEventQueue();

      expect(disconnectCompleted, isFalse);
      expect(disconnectError, isNull);

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      await disconnectCompletedFuture;

      expect(disconnectCompleted, isTrue);
      expect(disconnectError, isNull);
    },
  );

  test(
    'BluetoothDevice.disconnect supersedes a timed-out connect and permits retry',
    () async {
      final platform = _FakeQuickBluePlatform(connectsImmediately: false);
      addTearDown(platform.dispose);

      final device = platform.device('device-a');
      final connect = device.connect();
      await expectLater(
        connect.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );

      await device.disconnect();
      await expectLater(
        connect,
        throwsA(
          isA<QuickBlueException>()
              .having(
                (error) => error.code,
                'code',
                QuickBlueErrorCode.cancelled,
              )
              .having((error) => error.operation, 'operation', 'connect'),
        ),
      );
      expect(platform.calls, <String>[
        'connect device-a',
        'disconnect device-a',
      ]);

      final retry = device.connect();
      await pumpEventQueue();
      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      await retry;

      expect(platform.calls, <String>[
        'connect device-a',
        'disconnect device-a',
        'connect device-a',
      ]);
    },
  );

  test('BluetoothDevice.disconnect stops an automatic busy retry', () async {
    final platform = _FakeQuickBluePlatform(
      connectErrors: <Object>[
        const QuickBlueException(
          code: QuickBlueErrorCode.deviceBusy,
          message: 'busy',
        ),
      ],
    );
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final connect = device.connect();
    await pumpEventQueue();

    await device.disconnect();
    await expectLater(
      connect,
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(platform.calls, <String>['connect device-a', 'disconnect device-a']);
  });

  test('BluetoothDevice rejects overlapping disconnect operations', () async {
    final platform = _FakeQuickBluePlatform(disconnectsImmediately: false);
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final firstDisconnect = device.disconnect();
    await pumpEventQueue();

    await expectLater(
      device.disconnect(),
      throwsA(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.invalidState,
            )
            .having((error) => error.operation, 'operation', 'disconnect')
            .having((error) => error.details, 'details', 'disconnect'),
      ),
    );

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await firstDisconnect;
  });

  test(
    'BluetoothDevice allows concurrent operations for different devices',
    () async {
      final platform = _FakeQuickBluePlatform(connectsImmediately: false);
      addTearDown(platform.dispose);

      final firstConnect = platform.device('device-a').connect();
      final secondConnect = platform.device('device-b').connect();
      await pumpEventQueue();

      expect(platform.calls, <String>['connect device-a', 'connect device-b']);

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      platform.onConnectionChanged!(
        'device-b',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      await Future.wait(<Future<void>>[firstConnect, secondConnect]);
    },
  );

  test(
    'BluetoothDevice.discoverServices completes with discovered services',
    () async {
      final platform = _FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-b',
            characteristics: const <String>['characteristic-b'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-c',
            characteristics: const <String>['characteristic-c'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final services = await platform.device('device-a').discoverServices();

      expect(services.map((service) => service.uuid), <String>[
        'service-a',
        'service-b',
        'service-c',
      ]);
    },
  );

  test('BluetoothDevice.discoverGatt exposes discovered services', () async {
    final discoveredServices = <BluetoothService>[
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
      ),
    ];
    final platform = _FakeQuickBluePlatform(
      discoveredServices: discoveredServices,
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(gatt.deviceId, 'device-a');
    expect(gatt.services, discoveredServices);
    expect(platform.calls, <String>['discoverServices device-a']);
  });

  test(
    'BluetoothGatt.characteristic resolves a discovered characteristic',
    () async {
      final platform = _FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[1, 2, 3]),
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();
      final value = await gatt.characteristic('characteristic-a').read();

      expect(value, Uint8List.fromList(<int>[1, 2, 3]));
      expect(platform.calls, <String>[
        'discoverServices device-a',
        'readValue device-a service-a characteristic-a',
      ]);
    },
  );

  test('BluetoothGatt.characteristic matches short and full UUIDs', () async {
    final platform = _FakeQuickBluePlatform(
      readValueResult: Uint8List.fromList(<int>[4, 5, 6]),
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: '0000180d-0000-1000-8000-00805f9b34fb',
          characteristics: const <String>[
            '00002a37-0000-1000-8000-00805f9b34fb',
          ],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();
    final value = await gatt.characteristic('2a37', service: '180d').read();

    expect(value, Uint8List.fromList(<int>[4, 5, 6]));
    expect(platform.calls, <String>[
      'discoverServices device-a',
      'readValue device-a '
          '0000180d-0000-1000-8000-00805f9b34fb '
          '00002a37-0000-1000-8000-00805f9b34fb',
    ]);
  });

  test('BluetoothGatt.characteristic exposes characteristic info', () async {
    final platform = _FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
          characteristicDetails: <BluetoothCharacteristicInfo>[
            BluetoothCharacteristicInfo(
              uuid: 'characteristic-a',
              canRead: true,
            ),
          ],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(gatt.characteristicInfo('characteristic-a').canRead, isTrue);
  });

  test(
    'BluetoothGatt.hasCharacteristic returns true when discovered',
    () async {
      final platform = _FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(gatt.hasCharacteristic('characteristic-a'), isTrue);
    },
  );

  test(
    'BluetoothGatt.hasCharacteristic returns false when not found',
    () async {
      final platform = _FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(gatt.hasCharacteristic('missing-characteristic'), isFalse);
    },
  );

  test('BluetoothGatt.hasCharacteristic applies service filters', () async {
    final platform = _FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-b',
          characteristics: const <String>['characteristic-b'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(
      gatt.hasCharacteristic('characteristic-a', service: 'service-a'),
      isTrue,
    );
    expect(
      gatt.hasCharacteristic('characteristic-a', service: 'service-b'),
      isFalse,
    );
  });

  test(
    'BluetoothGatt.hasCharacteristic matches short and full UUIDs',
    () async {
      final platform = _FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            characteristics: const <String>[
              '00002a37-0000-1000-8000-00805f9b34fb',
            ],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(gatt.hasCharacteristic('2a37', service: '180d'), isTrue);
    },
  );

  test('BluetoothGatt.hasCharacteristic returns true when ambiguous', () async {
    final platform = _FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-b',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(gatt.hasCharacteristic('characteristic-a'), isTrue);
  });

  test('BluetoothGatt.characteristic throws with service filter and missing '
      'characteristic context', () async {
    final platform = _FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-b',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();
    expect(
      () => gatt.characteristic('characteristic-a', service: 'service-a'),
      throwsA(
        isA<QuickBlueException>()
            .having((error) => error.code, 'code', QuickBlueErrorCode.notFound)
            .having(
              (error) => error.message,
              'message',
              contains('under service service-a'),
            ),
      ),
    );
  });

  test('BluetoothGatt.characteristic throws when not found', () async {
    final platform = _FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(
      () => gatt.characteristic('missing-characteristic'),
      throwsA(
        isA<QuickBlueException>()
            .having((error) => error.code, 'code', QuickBlueErrorCode.notFound)
            .having(
              (error) => error.message,
              'message',
              contains('Characteristic missing-characteristic not found'),
            ),
      ),
    );
  });

  test(
    'BluetoothGatt.characteristic throws when characteristic is ambiguous',
    () async {
      final platform = _FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-b',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(
        () => gatt.characteristic('characteristic-a'),
        throwsA(
          isA<QuickBlueException>()
              .having(
                (error) => error.code,
                'code',
                QuickBlueErrorCode.ambiguous,
              )
              .having(
                (error) => error.message,
                'message',
                allOf(contains('multiple services'), contains('service-a')),
              ),
        ),
      );
    },
  );

  test(
    'BluetoothGatt.characteristic resolves ambiguous characteristic by service',
    () async {
      final platform = _FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[7, 8, 9]),
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-b',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();
      final value = await gatt
          .characteristic('characteristic-a', service: 'service-b')
          .read();

      expect(value, Uint8List.fromList(<int>[7, 8, 9]));
      expect(platform.calls, <String>[
        'discoverServices device-a',
        'readValue device-a service-b characteristic-a',
      ]);
    },
  );

  test('BluetoothDevice.discoverServices propagates platform errors', () async {
    final error = StateError('discover failed');
    final platform = _FakeQuickBluePlatform(discoverServicesError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform.device('device-a').discoverServices(),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>['discoverServices device-a']);
  });

  test(
    'BluetoothDevice.discoverServices coalesces concurrent device requests',
    () async {
      final discovery = Completer<void>();
      final platform = _FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
        discoverServicesCompletion: discovery,
      );
      addTearDown(platform.dispose);

      final device = platform.device('device-a');
      final firstDiscovery = device.discoverServices();
      final secondDiscovery = device.discoverServices();
      await pumpEventQueue();

      expect(platform.calls, <String>['discoverServices device-a']);

      discovery.complete();
      final results = await Future.wait(<Future<List<BluetoothService>>>[
        firstDiscovery,
        secondDiscovery,
      ]);

      expect(results[0].map((service) => service.uuid), <String>['service-a']);
      expect(results[1].map((service) => service.uuid), <String>['service-a']);
      expect(results[0], same(results[1]));
    },
  );

  test('BluetoothDevice.discoverServices can retry after failure', () async {
    final error = StateError('discover failed');
    final platform = _FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
      discoverServicesError: error,
    );
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    await expectLater(device.discoverServices(), throwsA(same(error)));

    platform.discoverServicesError = null;
    final services = await device.discoverServices();

    expect(services.map((service) => service.uuid), <String>['service-a']);
    expect(platform.calls, <String>[
      'discoverServices device-a',
      'discoverServices device-a',
    ]);
  });

  test('BluetoothDevice.setNotifiable propagates platform errors', () async {
    final error = StateError('notify failed');
    final platform = _FakeQuickBluePlatform(setNotifiableError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform
          .device('device-a')
          .setNotifiable(
            'service-a',
            'characteristic-a',
            BleInputProperty.notification,
          ),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>[
      'setNotifiable device-a service-a characteristic-a notification',
    ]);
  });

  test(
    'BluetoothDevice.readValue completes with the matching value event',
    () async {
      final platform = _FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[4, 5, 6]),
      );
      addTearDown(platform.dispose);

      final device = platform.device('device-a');

      await expectLater(
        device.readValue('service-a', 'characteristic-a'),
        completion(Uint8List.fromList(<int>[4, 5, 6])),
      );
    },
  );

  test(
    'BluetoothCharacteristic.valueStream matches short and full UUIDs',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('180d', '2a37');

      final value = expectLater(
        characteristic.valueStream,
        emits(Uint8List.fromList(<int>[1, 2, 3])),
      );

      platform.handleCharacteristicValueChanged(
        'device-a',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '00002a37-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[1, 2, 3]),
      );

      await value;
    },
  );

  test(
    'BluetoothCharacteristic.valueStream receives direct and legacy values',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final device = platform.device('device-a');
      final characteristic = device.characteristic('180d', '2a37');
      final otherCharacteristic = device.characteristic('180d', '2a38');
      final values = <Uint8List>[];
      final otherValues = <Uint8List>[];
      final subscription = characteristic.valueStream.listen(values.add);
      final otherSubscription = otherCharacteristic.valueStream.listen(
        otherValues.add,
      );

      platform.handleCharacteristicValueChanged(
        'device-a',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '00002a37-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      platform.onValueChanged?.call(
        'device-a',
        '00002a37-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[4, 5, 6]),
      );
      platform.handleCharacteristicValueChanged(
        'device-a',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '00002a38-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[7, 8, 9]),
      );
      await pumpEventQueue();

      expect(values.map((value) => value.toList()), [
        <int>[1, 2, 3],
        <int>[4, 5, 6],
      ]);
      expect(otherValues.map((value) => value.toList()), [
        <int>[7, 8, 9],
      ]);

      await subscription.cancel();
      await otherSubscription.cancel();
    },
  );

  test('BluetoothCharacteristic.setNotifiable delegates to platform', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final characteristic = platform
        .device('device-a')
        .characteristic('service-a', 'characteristic-a');

    await characteristic.setNotifiable(BleInputProperty.notification);
    await characteristic.setNotifiable(BleInputProperty.disabled);

    expect(platform.calls, <String>[
      'setNotifiable device-a service-a characteristic-a notification',
      'setNotifiable device-a service-a characteristic-a disabled',
    ]);
  });

  test(
    'BluetoothCharacteristic.setNotifiable propagates platform errors',
    () async {
      final error = StateError('notify failed');
      final platform = _FakeQuickBluePlatform(setNotifiableError: error);
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      await expectLater(
        characteristic.setNotifiable(BleInputProperty.notification),
        throwsA(same(error)),
      );
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
    },
  );

  test('BluetoothDevice.readValue propagates platform errors', () async {
    final error = StateError('read failed');
    final platform = _FakeQuickBluePlatform(readValueError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform.device('device-a').readValue('service-a', 'characteristic-a'),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>[
      'readValue device-a service-a characteristic-a',
    ]);
  });

  test('BluetoothDevice.writeValue propagates platform errors', () async {
    final error = StateError('write failed');
    final platform = _FakeQuickBluePlatform(writeValueError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform
          .device('device-a')
          .writeValue(
            'service-a',
            'characteristic-a',
            Uint8List.fromList(<int>[1, 2, 3]),
            BleOutputProperty.withResponse,
          ),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>[
      'writeValue device-a service-a characteristic-a withResponse [1, 2, 3]',
    ]);
  });

  test(
    'BluetoothCharacteristic notifications enable and disable notify',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final values = <Uint8List>[];
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen(values.add);
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[7, 8, 9]),
      );
      await pumpEventQueue();

      expect(values.single, Uint8List.fromList(<int>[7, 8, 9]));

      await subscription.cancel();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic notifications emits notify setup errors',
    () async {
      final error = StateError('notify failed');
      final platform = _FakeQuickBluePlatform(setNotifiableError: error);
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');
      final errors = <Object>[];
      final subscription = characteristic.notifications().listen(
        (_) {},
        onError: errors.add,
      );

      await pumpEventQueue();
      await subscription.cancel();

      expect(errors, <Object>[error]);
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic notifications waits for notify before forwarding',
    () async {
      final enableNotify = Completer<void>();
      final platform = _FakeQuickBluePlatform(
        setNotifiableCompletions: <Completer<void>>[enableNotify],
      );
      addTearDown(platform.dispose);

      final values = <Uint8List>[];
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen(values.add);
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[7, 8, 9]),
      );
      await pumpEventQueue();

      expect(values, isEmpty);

      enableNotify.complete();
      await pumpEventQueue();

      expect(values.single, Uint8List.fromList(<int>[7, 8, 9]));

      await subscription.cancel();
    },
  );

  test(
    'BluetoothCharacteristic notifications disables after pending enable',
    () async {
      final enableNotify = Completer<void>();
      final disableNotify = Completer<void>();
      final platform = _FakeQuickBluePlatform(
        setNotifiableCompletions: <Completer<void>>[
          enableNotify,
          disableNotify,
        ],
      );
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();

      final cancel = subscription.cancel();
      var cancelCompleted = false;
      final cancelCompletedFuture = cancel.then((_) => cancelCompleted = true);
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
      expect(cancelCompleted, isFalse);

      enableNotify.complete();
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
      expect(cancelCompleted, isFalse);

      disableNotify.complete();
      await cancelCompletedFuture;

      expect(cancelCompleted, isTrue);
    },
  );

  test(
    'BluetoothCharacteristic notifications share native listener ownership',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final firstValues = <Uint8List>[];
      final secondValues = <Uint8List>[];
      final device = platform.device('device-a');
      final firstCharacteristic = device.characteristic(
        'service-a',
        'characteristic-a',
      );
      final secondCharacteristic = device.characteristic(
        'service-a',
        'characteristic-a',
      );

      final firstSubscription = firstCharacteristic.notifications().listen(
        firstValues.add,
      );
      final secondSubscription = secondCharacteristic.notifications().listen(
        secondValues.add,
      );
      await pumpEventQueue();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      await firstSubscription.cancel();
      expect(platform.calls, hasLength(1));

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      await pumpEventQueue();

      expect(firstValues, isEmpty);
      expect(secondValues.single, Uint8List.fromList(<int>[1, 2, 3]));

      await secondSubscription.cancel();
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic notifications can retry failed setup',
    () async {
      final error = StateError('notify failed');
      final platform = _FakeQuickBluePlatform(setNotifiableError: error);
      addTearDown(platform.dispose);
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final errors = <Object>[];
      final failedSubscription = characteristic.notifications().listen(
        (_) {},
        onError: errors.add,
      );
      await pumpEventQueue();
      await failedSubscription.cancel();
      expect(errors, <Object>[error]);

      platform.setNotifiableError = null;
      final retrySubscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();
      await retrySubscription.cancel();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );

  test(
    'BluetoothCharacteristic rejects conflicting notification properties',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final notificationSubscription = characteristic.notifications().listen(
        (_) {},
      );
      await pumpEventQueue();

      final errors = <Object>[];
      final indicationSubscription = characteristic
          .notifications(bleInputProperty: BleInputProperty.indication)
          .listen((_) {}, onError: errors.add);
      await pumpEventQueue();
      await indicationSubscription.cancel();

      expect(
        errors.single,
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.invalidState,
            )
            .having((error) => error.operation, 'operation', 'notifications'),
      );
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);

      await notificationSubscription.cancel();
      expect(platform.calls.last, contains('disabled'));
    },
  );

  test(
    'BluetoothCharacteristic can re-enable after failed final disable',
    () async {
      final platform = _FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      final subscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();

      final disableError = StateError('disable failed');
      platform.setNotifiableError = disableError;
      await expectLater(subscription.cancel(), throwsA(same(disableError)));

      platform.setNotifiableError = null;
      final retrySubscription = characteristic.notifications().listen((_) {});
      await pumpEventQueue();
      await retrySubscription.cancel();

      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
        'setNotifiable device-a service-a characteristic-a notification',
        'setNotifiable device-a service-a characteristic-a disabled',
      ]);
    },
  );
}

class _FakeQuickBluePlatform extends QuickBluePlatform {
  _FakeQuickBluePlatform({
    Uint8List? readValueResult,
    List<BluetoothService> discoveredServices = const <BluetoothService>[],
    this.connectedDeviceIds = const <String>[],
    this.startScanError,
    List<Completer<void>> startScanCompletions = const <Completer<void>>[],
    List<Completer<void>> setNotifiableCompletions = const <Completer<void>>[],
    this.discoverServicesCompletion,
    this.discoverServicesError,
    this.setNotifiableError,
    this.readValueError,
    this.writeValueError,
    this.currentBondState = BluetoothBondState.notBonded,
    this.connectsImmediately = true,
    this.disconnectsImmediately = true,
    List<Object> connectErrors = const <Object>[],
  }) : readValueResult = readValueResult ?? Uint8List(0),
       discoveredServices = discoveredServices,
       startScanCompletions = startScanCompletions,
       setNotifiableCompletions = setNotifiableCompletions,
       connectErrors = List<Object>.of(connectErrors);

  final StreamController<BlueScanResult> _scanResultController =
      StreamController<BlueScanResult>.broadcast();
  final List<String> calls = <String>[];
  final Uint8List readValueResult;
  final List<BluetoothService> discoveredServices;
  final List<String> connectedDeviceIds;
  final Object? startScanError;
  final List<Completer<void>> startScanCompletions;
  final List<Completer<void>> setNotifiableCompletions;
  final Completer<void>? discoverServicesCompletion;
  Object? discoverServicesError;
  Object? setNotifiableError;
  final Object? readValueError;
  final Object? writeValueError;
  BluetoothBondState currentBondState;
  final bool connectsImmediately;
  final bool disconnectsImmediately;
  final List<Object> connectErrors;
  ScanFilter? lastScanFilter;
  ScanOptions? lastScanOptions;
  int _startScanCallCount = 0;
  int _setNotifiableCallCount = 0;

  void addScanResult(String deviceId, {int rssi = -40}) {
    _scanResultController.add(
      BlueScanResult(name: 'Device $deviceId', deviceId: deviceId, rssi: rssi),
    );
  }

  void addBondStateChange(
    String deviceId,
    BluetoothBondState state, {
    required BluetoothBondState previousState,
  }) {
    if (deviceId == 'device-a') {
      currentBondState = state;
    }
    handleBondStateChanged(deviceId, state, previousState);
  }

  Future<void> dispose() {
    return _scanResultController.close();
  }

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultController.stream;

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    lastScanFilter = scanFilter;
    lastScanOptions = scanOptions;
    calls.add('startScan');
    final error = startScanError;
    if (error != null) {
      if (error is Error) {
        throw error;
      }
      throw StateError(error.toString());
    }
    if (_startScanCallCount < startScanCompletions.length) {
      await startScanCompletions[_startScanCallCount++].future;
    }
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    calls.add('connectedDevices $serviceUuids');
    return connectedDeviceIds.map(device).toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) async {
    calls.add('connect $deviceId');
    if (connectErrors.isNotEmpty) {
      throw connectErrors.removeAt(0);
    }
    if (connectsImmediately) {
      onConnectionChanged!(
        deviceId,
        BlueConnectionState.connected,
        BleStatus.success,
      );
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    calls.add('disconnect $deviceId');
    if (disconnectsImmediately) {
      onConnectionChanged!(
        deviceId,
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
    }
  }

  @override
  Future<BluetoothBondState> bondState(String deviceId) async {
    calls.add('bondState $deviceId');
    return currentBondState;
  }

  @override
  Future<void> pair(String deviceId) async {
    calls.add('pair $deviceId');
  }

  @override
  Future<bool> isCompanionAssociationSupported() async {
    calls.add('isCompanionAssociationSupported');
    return false;
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    calls.add('companionAssociate');
    return null;
  }

  @override
  Future<void> companionDisassociate(int associationId) async {
    calls.add('companionDisassociate $associationId');
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    calls.add('getCompanionAssociations');
    return const <CompanionAssociation>[];
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    calls.add('discoverServices $deviceId');
    final error = discoverServicesError;
    if (error != null) {
      throw error;
    }
    await discoverServicesCompletion?.future;
    for (final service in discoveredServices) {
      handleServiceDiscovered(
        deviceId,
        service.uuid,
        service.characteristicDetails,
      );
    }
    onServiceDiscoveryComplete(deviceId);
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    calls.add(
      'setNotifiable $deviceId $service $characteristic ${bleInputProperty.value}',
    );
    final error = setNotifiableError;
    if (error != null) {
      throw error;
    }
    if (_setNotifiableCallCount < setNotifiableCompletions.length) {
      await setNotifiableCompletions[_setNotifiableCallCount++].future;
    }
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    calls.add('readValue $deviceId $service $characteristic');
    final error = readValueError;
    if (error != null) {
      throw error;
    }
    handleCharacteristicValueChanged(
      deviceId,
      service,
      characteristic,
      readValueResult,
    );
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    calls.add(
      'writeValue $deviceId $service $characteristic '
      '${bleOutputProperty.value} ${value.toList()}',
    );
    final error = writeValueError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    calls.add('requestMtu $deviceId $expectedMtu');
    return expectedMtu;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    calls.add('openL2cap $deviceId $psm');
    return BleL2capSocket(
      sink: _NoopSink(),
      stream: const Stream<BleL2CapSocketEvent>.empty(),
    );
  }
}

class _FakeBluetoothStatePlatform extends _FakeQuickBluePlatform {
  final _bluetoothStateController =
      StreamController<BlueBluetoothState>.broadcast();
  var bluetoothState = BlueBluetoothState.poweredOn;
  var bluetoothStateEventListenCount = 0;
  var bluetoothStateEventCancelCount = 0;

  void addBluetoothState(BlueBluetoothState state) {
    bluetoothState = state;
    _bluetoothStateController.add(state);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _bluetoothStateController.close();
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    return bluetoothState == BlueBluetoothState.poweredOn;
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateEvents {
    return Stream.multi((controller) {
      bluetoothStateEventListenCount += 1;
      final subscription = _bluetoothStateController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller
        ..add(bluetoothState)
        ..onCancel = () async {
          bluetoothStateEventCancelCount += 1;
          await subscription.cancel();
        };
    });
  }
}

class _NoopSink implements EventSink<Uint8List> {
  @override
  void add(Uint8List event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void close() {}
}
