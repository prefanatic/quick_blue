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
    expect(platform.lastScanFilter, same(filter));

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
    platform.onServiceDiscovered!('device-b', 'service-b', <String>[]);
    platform.onValueChanged!(
      'device-b',
      'characteristic-b',
      Uint8List.fromList(<int>[9]),
    );

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    platform.onServiceDiscovered!('device-a', 'service-a', <String>[
      'characteristic-a',
    ]);
    platform.onValueChanged!(
      'device-a',
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
    unawaited(connect.then((_) => connectCompleted = true));

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
    await connect;

    expect(connectCompleted, isTrue);
  });

  test('BluetoothDevice.disconnect waits for disconnected state', () async {
    final platform = _FakeQuickBluePlatform(disconnectsImmediately: false);
    addTearDown(platform.dispose);

    final disconnect = platform.device('device-a').disconnect();
    var disconnectCompleted = false;
    unawaited(disconnect.then((_) => disconnectCompleted = true));

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
    await disconnect;

    expect(disconnectCompleted, isTrue);
  });

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

      platform.onValueChanged!(
        'device-a',
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

      platform.onValueChanged!(
        'device-a',
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
      unawaited(cancel.then((_) => cancelCompleted = true));
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
      await cancel;

      expect(cancelCompleted, isTrue);
    },
  );
}

class _FakeQuickBluePlatform extends QuickBluePlatform {
  _FakeQuickBluePlatform({
    Uint8List? readValueResult,
    List<BluetoothService> discoveredServices = const <BluetoothService>[],
    List<Completer<void>> setNotifiableCompletions = const <Completer<void>>[],
    this.connectsImmediately = true,
    this.disconnectsImmediately = true,
  }) : readValueResult = readValueResult ?? Uint8List(0),
       discoveredServices = discoveredServices,
       setNotifiableCompletions = setNotifiableCompletions;

  final StreamController<BlueScanResult> _scanResultController =
      StreamController<BlueScanResult>.broadcast();
  final List<String> calls = <String>[];
  final Uint8List readValueResult;
  final List<BluetoothService> discoveredServices;
  final List<Completer<void>> setNotifiableCompletions;
  final bool connectsImmediately;
  final bool disconnectsImmediately;
  ScanFilter? lastScanFilter;
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
  Future<void> startScan({ScanFilter scanFilter = const ScanFilter()}) async {
    lastScanFilter = scanFilter;
    calls.add('startScan');
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
    for (final service in discoveredServices) {
      onServiceDiscovered!(deviceId, service.uuid, service.characteristics);
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
    onValueChanged!(deviceId, characteristic, readValueResult);
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
