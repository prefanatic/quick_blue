import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
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

    expect(errors.single, isA<StateError>());
    expect(platform.calls, <String>['startScan']);

    await firstSubscription.cancel();
    await secondSubscription.cancel();

    expect(platform.calls, <String>['startScan', 'stopScan']);
  });

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

  test('device streams only emit events for that device', () {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final device = platform.device('device-a');

    expectLater(
      device.connectionStateStream.map((event) => event.state),
      emits(BlueConnectionState.connected),
    );
    expectLater(
      device.serviceDiscoveryStream.map((event) => event.uuid),
      emits('service-a'),
    );
    expectLater(
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

  test('BluetoothDevice delegates commands to platform', () async {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final value = Uint8List.fromList(<int>[1, 2, 3]);

    await device.connect();
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
      'discoverServices device-a',
      'setNotifiable device-a service-a characteristic-a notification',
      'writeValue device-a service-a characteristic-a withResponse [1, 2, 3]',
      'requestMtu device-a 128',
      'openL2cap device-a 25',
      'disconnect device-a',
    ]);
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
        isA<StateError>().having(
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
          isA<StateError>().having(
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
        ],
      );
      addTearDown(platform.dispose);

      final services = await platform.device('device-a').discoverServices();

      expect(services.map((service) => service.uuid), <String>[
        'service-a',
        'service-b',
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

  test('BluetoothDevice.readValue completes with the matching value event', () {
    final platform = _FakeQuickBluePlatform(
      readValueResult: Uint8List.fromList(<int>[4, 5, 6]),
    );
    addTearDown(platform.dispose);

    final device = platform.device('device-a');

    expectLater(
      device.readValue('service-a', 'characteristic-a'),
      completion(Uint8List.fromList(<int>[4, 5, 6])),
    );
  });

  test('BluetoothCharacteristic.valueStream matches short and full UUIDs', () {
    final platform = _FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final characteristic = platform
        .device('device-a')
        .characteristic('180d', '2a37');

    expectLater(
      characteristic.valueStream,
      emits(Uint8List.fromList(<int>[1, 2, 3])),
    );

    platform.handleCharacteristicValueChanged(
      'device-a',
      '0000180d-0000-1000-8000-00805f9b34fb',
      '00002a37-0000-1000-8000-00805f9b34fb',
      Uint8List.fromList(<int>[1, 2, 3]),
    );
  });

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
}

class _FakeQuickBluePlatform extends QuickBluePlatform {
  _FakeQuickBluePlatform({
    Uint8List? readValueResult,
    List<BluetoothService> discoveredServices = const <BluetoothService>[],
    List<Completer<void>> startScanCompletions = const <Completer<void>>[],
    List<Completer<void>> setNotifiableCompletions = const <Completer<void>>[],
    this.discoverServicesError,
    this.setNotifiableError,
    this.readValueError,
    this.writeValueError,
    this.connectsImmediately = true,
    this.disconnectsImmediately = true,
  }) : readValueResult = readValueResult ?? Uint8List(0),
       discoveredServices = discoveredServices,
       startScanCompletions = startScanCompletions,
       setNotifiableCompletions = setNotifiableCompletions;

  final StreamController<BlueScanResult> _scanResultController =
      StreamController<BlueScanResult>.broadcast();
  final List<String> calls = <String>[];
  final Uint8List readValueResult;
  final List<BluetoothService> discoveredServices;
  final List<Completer<void>> startScanCompletions;
  final List<Completer<void>> setNotifiableCompletions;
  final Object? discoverServicesError;
  final Object? setNotifiableError;
  final Object? readValueError;
  final Object? writeValueError;
  final bool connectsImmediately;
  final bool disconnectsImmediately;
  ScanFilter? lastScanFilter;
  int _startScanCallCount = 0;
  int _setNotifiableCallCount = 0;

  void addScanResult(String deviceId) {
    _scanResultController.add(
      BlueScanResult(name: 'Device $deviceId', deviceId: deviceId, rssi: -40),
    );
  }

  Future<void> dispose() {
    return _scanResultController.close();
  }

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultController.stream;

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) async {
    lastScanFilter = scanFilter;
    calls.add('startScan');
    if (_startScanCallCount < startScanCompletions.length) {
      await startScanCompletions[_startScanCallCount++].future;
    }
  }

  @override
  Future<void> stopScan() async {
    calls.add('stopScan');
  }

  @override
  Future<void> connect(String deviceId) async {
    calls.add('connect $deviceId');
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
  Future<CompanionDevice?> companionAssociate({
    String? deviceId,
    ScanFilter? scanFilter,
  }) async {
    calls.add('companionAssociate');
    return null;
  }

  @override
  Future<void> companionDisassociate(int associationId) async {
    calls.add('companionDisassociate $associationId');
  }

  @override
  Future<List<CompanionDevice>?> getCompanionAssociations() async {
    calls.add('getCompanionAssociations');
    return const <CompanionDevice>[];
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    calls.add('discoverServices $deviceId');
    final error = discoverServicesError;
    if (error != null) {
      throw error;
    }
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

class _NoopSink implements EventSink<Uint8List> {
  @override
  void add(Uint8List event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void close() {}
}
