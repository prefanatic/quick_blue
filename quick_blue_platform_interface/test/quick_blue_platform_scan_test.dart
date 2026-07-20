import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

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
      final platform = FakeQuickBluePlatform();
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
      final platform = FakeBluetoothStatePlatform();
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
    final platform = FakeQuickBluePlatform();
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
    final platform = FakeQuickBluePlatform(
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
    final platform = FakeQuickBluePlatform();
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

    final fake = FakeQuickBluePlatform();
    addTearDown(fake.dispose);

    QuickBluePlatform.instance = fake;

    expect(QuickBluePlatform.instance, same(fake));
  });

  test('connectedDevices returns BluetoothDevice objects', () async {
    final platform = FakeQuickBluePlatform(
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
      final platform = FakeQuickBluePlatform();
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
    final platform = FakeQuickBluePlatform();
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
      final platform = FakeQuickBluePlatform();
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
    final platform = FakeQuickBluePlatform();
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

  test('scanResults filters service data by UUID and payload prefix', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final results = <String>[];

    final subscription = platform
        .scanResults(
          scanFilter: ScanFilter(
            serviceData: <String, Uint8List>{
              '180a': Uint8List.fromList(<int>[1, 2]),
            },
          ),
        )
        .listen((result) => results.add(result.deviceId));

    await pumpEventQueue();
    platform
      ..addScanResult(
        'device-a',
        serviceData: <String, Uint8List>{
          '0000180a-0000-1000-8000-00805f9b34fb': Uint8List.fromList(<int>[
            1,
            2,
            3,
          ]),
        },
      )
      ..addScanResult(
        'device-b',
        serviceData: <String, Uint8List>{
          '180a': Uint8List.fromList(<int>[1, 3]),
        },
      )
      ..addScanResult(
        'device-c',
        serviceData: <String, Uint8List>{'180f': Uint8List(0)},
      );
    await pumpEventQueue();

    expect(results, <String>['device-a']);

    await subscription.cancel();
  });

  test(
    'scanResults accepts any payload for an empty service-data prefix',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      final results = <String>[];

      final subscription = platform
          .scanResults(
            scanFilter: ScanFilter(
              serviceData: <String, Uint8List>{'180a': Uint8List(0)},
            ),
          )
          .listen((result) => results.add(result.deviceId));

      await pumpEventQueue();
      platform.addScanResult(
        'device-a',
        serviceData: <String, Uint8List>{
          '180a': Uint8List.fromList(<int>[9, 8, 7]),
        },
      );
      await pumpEventQueue();

      expect(results, <String>['device-a']);

      await subscription.cancel();
    },
  );

  test(
    'scanResults drops duplicate devices when duplicates are disabled',
    () async {
      final platform = FakeQuickBluePlatform();
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
    final platform = FakeQuickBluePlatform();
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
      final platform = FakeQuickBluePlatform();
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
      final platform = FakeQuickBluePlatform();
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
    final platform = FakeQuickBluePlatform(
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
      final platform = FakeQuickBluePlatform(
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
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final filter = ScanFilter(
      serviceUuids: const <String>['180d'],
      serviceData: <String, Uint8List>{
        '180a': Uint8List.fromList(<int>[4, 5]),
      },
      manufacturerData: <int, Uint8List>{
        76: Uint8List.fromList(<int>[1, 2, 3]),
      },
    );

    final subscription = platform.scan(scanFilter: filter).listen((_) {});

    await pumpEventQueue();
    expect(platform.lastScanFilter, isNot(same(filter)));
    expect(platform.lastScanFilter!.serviceUuids, filter.serviceUuids);
    expect(
      platform.lastScanFilter!.serviceData!['180a'],
      orderedEquals(<int>[4, 5]),
    );
    expect(
      platform.lastScanFilter!.manufacturerData![76],
      orderedEquals(<int>[1, 2, 3]),
    );

    await subscription.cancel();
  });

  test('scan forwards scan options to startScan', () async {
    final platform = FakeQuickBluePlatform();
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
      final platform = FakeQuickBluePlatform();
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
}
