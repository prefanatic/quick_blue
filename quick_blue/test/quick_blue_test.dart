import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuickBluePlatform previousPlatform;
  late _FakeQuickBluePlatform platform;

  setUp(() {
    previousPlatform = QuickBluePlatform.instance;
    platform = _FakeQuickBluePlatform();
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

  test('isBluetoothAvailable delegates to the platform', () async {
    platform.isAvailable = false;

    expect(await QuickBlue.isBluetoothAvailable(), isFalse);
    expect(platform.calls, <String>['isBluetoothAvailable']);
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

  test('device returns a BluetoothDevice for the id', () {
    final device = QuickBlue.device('device-a');

    expect(device.id, 'device-a');
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

  test('discoverServices returns discovered services', () async {
    platform.discoveredServices = <BluetoothService>[
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
      ),
    ];

    final services = await QuickBlue.discoverServices('device-a');

    expect(platform.calls, <String>['discoverServices device-a']);
    expect(services.map((service) => service.uuid), <String>['service-a']);
  });

  test('readValue returns the characteristic value', () async {
    platform.readValueResult = Uint8List.fromList(<int>[1, 2, 3]);

    final value = await QuickBlue.readValue(
      'device-a',
      'service-a',
      'characteristic-a',
    );

    expect(platform.calls, <String>[
      'readValue device-a service-a characteristic-a',
    ]);
    expect(value, Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('setNotifiable delegates through the device API', () async {
    await QuickBlue.setNotifiable(
      'device-a',
      'service-a',
      'characteristic-a',
      BleInputProperty.indication,
    );

    expect(platform.calls, <String>[
      'setNotifiable device-a service-a characteristic-a indication',
    ]);
  });

  test('writeValue delegates through the device API', () async {
    final value = Uint8List.fromList(<int>[4, 5, 6]);

    await QuickBlue.writeValue(
      'device-a',
      'service-a',
      'characteristic-a',
      value,
      BleOutputProperty.withoutResponse,
    );

    expect(platform.calls, <String>[
      'writeValue device-a service-a characteristic-a withoutResponse [4, 5, 6]',
    ]);
  });

  test('requestMtu delegates through the device API', () async {
    final mtu = await QuickBlue.requestMtu('device-a', 247);

    expect(mtu, 247);
    expect(platform.calls, <String>['requestMtu device-a 247']);
  });

  test('openL2cap delegates through the device API', () async {
    final socket = await QuickBlue.openL2cap('device-a', 25);

    socket.sink.add(Uint8List.fromList(<int>[1, 2, 3]));
    expect(await socket.stream.toList(), isEmpty);
    expect(platform.calls, <String>['openL2cap device-a 25']);
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

  test('companionDisassociate delegates to the platform', () async {
    await QuickBlue.companionDisassociate(42);

    expect(platform.calls, <String>['companionDisassociate 42']);
  });

  test('companion isSupported delegates to the platform', () async {
    expect(await QuickBlue.companion.isSupported(), isTrue);

    expect(platform.calls, <String>['isCompanionAssociationSupported']);
  });

  test('companion associate delegates to the platform', () async {
    platform.companionAssociation = CompanionAssociation(
      id: 42,
      deviceId: 'device-a',
      displayName: 'Device A',
    );

    final association = await QuickBlue.companion.associate(
      CompanionAssociationRequest.ble(
        filters: <BleCompanionFilter>[
          BleCompanionFilter(
            deviceId: 'device-a',
            serviceUuids: const <String>['180d'],
          ),
        ],
      ),
    );

    expect(association, platform.companionAssociation);
    expect(platform.calls, <String>['companionAssociate device-a [180d]']);
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
}

class _FakeQuickBluePlatform extends QuickBluePlatform {
  final List<String> calls = <String>[];
  var isAvailable = true;
  var connectsImmediately = true;
  var disconnectsImmediately = true;
  var readValueResult = Uint8List(0);
  var discoveredServices = <BluetoothService>[];
  CompanionAssociation? companionAssociation;
  List<CompanionAssociation> companionAssociations =
      const <CompanionAssociation>[];
  final _scanResultController = StreamController<BlueScanResult>.broadcast();
  final _bluetoothStateController =
      StreamController<BlueBluetoothState>.broadcast();

  Future<void> dispose() async {
    await _scanResultController.close();
    await _bluetoothStateController.close();
  }

  void addScanResult(String deviceId) {
    _scanResultController.add(
      BlueScanResult(name: 'Device $deviceId', deviceId: deviceId, rssi: -40),
    );
  }

  void addBluetoothState(BlueBluetoothState state) {
    _bluetoothStateController.add(state);
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    calls.add('isBluetoothAvailable');
    return isAvailable;
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateStream {
    calls.add('bluetoothStateStream');
    return _bluetoothStateController.stream;
  }

  @override
  Stream<BlueScanResult> get scanResultStream => _scanResultController.stream;

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) async {
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
  Future<bool> isCompanionAssociationSupported() async {
    calls.add('isCompanionAssociationSupported');
    return true;
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    final filter = request.filters.isEmpty ? null : request.filters.first;
    calls.add(
      'companionAssociate ${filter?.deviceId} '
      '${filter?.serviceUuids ?? <String>[]}',
    );
    return companionAssociation;
  }

  @override
  Future<void> companionDisassociate(int associationId) async {
    calls.add('companionDisassociate $associationId');
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    calls.add('getCompanionAssociations');
    return companionAssociations;
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    calls.add('discoverServices $deviceId');
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
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    calls.add('readValue $deviceId $service $characteristic');
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
