// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:quick_blue_darwin/src/darwin_models.dart' as models;
import 'package:quick_blue_darwin/src/quick_blue_darwin.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => QuickBlueInstrumentation.observer = null);

  test('registers as platform implementation', () {
    final previous = QuickBluePlatform.instance;
    try {
      QuickBlueDarwin.registerWith();
      expect(QuickBluePlatform.instance, isA<QuickBlueDarwin>());
    } finally {
      QuickBluePlatform.instance = previous;
    }
  });

  test('forwards configuration and scan options', () async {
    final api = _FakeDarwinApi();
    final platform = QuickBlueDarwin(api: api);
    await platform.configure(maintainState: true);
    await platform.startScan(
      scanFilter: ScanFilter(serviceUuids: const ['180d'], rssi: -60),
      scanOptions: const ScanOptions(allowDuplicates: false),
    );
    expect(api.maintainState, isTrue);
    expect(api.serviceUuids, ['180d']);
    expect(api.rssi, -60);
    expect(api.allowDuplicates, isFalse);
    await platform.stopScan();
    expect(api.stoppedScan, isTrue);
    await api.close();
  });

  test('maps state and scan events', () async {
    final api = _FakeDarwinApi();
    final platform = QuickBlueDarwin(api: api);
    final state = platform.bluetoothStateStream.first;
    api.states.add(models.PlatformBluetoothState.poweredOn);
    expect(await state, BlueBluetoothState.poweredOn);

    final scan = platform.scanResultStream.first;
    api.scans.add(
      models.PlatformScanResult(
        name: 'Device',
        deviceId: 'device-a',
        manufacturerDataHead: Uint8List.fromList([1, 2]),
        manufacturerData: Uint8List.fromList([3]),
        rssi: -42,
        serviceUuids: const ['180d'],
        serviceData: {
          '180d': Uint8List.fromList([7]),
        },
      ),
    );
    final result = await scan;
    expect(result.deviceId, 'device-a');
    expect(result.rssi, -42);
    expect(result.serviceData['180d'], Uint8List.fromList([7]));
    await api.close();
  });

  test('filters scan events by service data', () async {
    final api = _FakeDarwinApi();
    final platform = QuickBlueDarwin(api: api);
    await platform.startScan(
      scanFilter: ScanFilter(
        serviceData: {
          '180a': Uint8List.fromList([1, 2]),
        },
      ),
    );
    final scan = platform.scanResultStream.first;
    api.scans.add(
      _scan('miss', {
        '180f': Uint8List.fromList([1, 2]),
      }),
    );
    api.scans.add(
      _scan('match', {
        '0000180a-0000-1000-8000-00805f9b34fb': Uint8List.fromList([1, 2, 3]),
      }),
    );
    expect((await scan).deviceId, 'match');
    await api.close();
  });

  test('reports a restoration event once', () async {
    final api = _FakeDarwinApi();
    final observer = _RestorationObserver();
    QuickBlueInstrumentation.observer = observer;
    final platform = QuickBlueDarwin(api: api);
    platform.startObservingDarwinRestoration();
    api.restorations.add(
      models.PlatformDarwinRestorationEvent(
        restoredPeripheralCount: 2,
        disconnectedPeripheralCount: 0,
        connectingPeripheralCount: 1,
        connectedPeripheralCount: 1,
        disconnectingPeripheralCount: 0,
        unknownPeripheralCount: 0,
        scanningRestored: true,
        restoredScanServiceCount: 1,
      ),
    );
    await pumpEventQueue();
    platform.startObservingDarwinRestoration();
    expect(observer.events, hasLength(1));
    expect(observer.events.single.connectedPeripheralCount, 1);
    await api.close();
  });

  test('maps a native read error to a security error', () async {
    final api = _FakeDarwinApi();
    final platform = QuickBlueDarwin(api: api);
    await expectLater(
      platform.readCharacteristicValue('device-a', '180d', '2a37'),
      throwsA(isA<QuickBlueException>()),
    );
    await api.close();
  });

  test('reports an L2CAP open error without a timeout', () async {
    final api = _FakeDarwinApi();
    final platform = QuickBlueDarwin(api: api);
    await expectLater(
      platform.openL2cap('device-a', 25),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.message,
          'message',
          'Open failed.',
        ),
      ),
    );
    await api.close();
  });
}

models.PlatformScanResult _scan(
  String id,
  Map<String, Uint8List> serviceData,
) => models.PlatformScanResult(
  name: id,
  deviceId: id,
  manufacturerDataHead: Uint8List(0),
  manufacturerData: Uint8List(0),
  rssi: -40,
  serviceUuids: const [],
  serviceData: serviceData,
);

class _FakeDarwinApi implements DarwinApi {
  final states = StreamController<models.PlatformBluetoothState>.broadcast();
  final scans = StreamController<models.PlatformScanResult>.broadcast();
  final restorations =
      StreamController<models.PlatformDarwinRestorationEvent>.broadcast();
  final sockets = StreamController<models.PlatformL2CapSocketEvent>.broadcast();
  bool? maintainState;
  List<String>? serviceUuids;
  int? rssi;
  bool? allowDuplicates;
  bool stoppedScan = false;

  @override
  Stream<models.PlatformBluetoothState> get bluetoothStateEvents =>
      states.stream;
  @override
  Stream<models.PlatformScanResult> get scanResults => scans.stream;
  @override
  Stream<models.PlatformDarwinRestorationEvent> get restorationEvents =>
      restorations.stream;
  @override
  Stream<models.PlatformL2CapSocketEvent> get l2CapEvents => sockets.stream;
  @override
  void bootstrapIfEnabled() {}
  @override
  Future<void> configure(
    models.PlatformDarwinConfiguration configuration,
  ) async {
    maintainState = configuration.maintainState;
  }

  @override
  Future<void> startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
    int? rssi,
    models.PlatformDarwinScanOptions? options,
  }) async {
    this.serviceUuids = serviceUuids;
    this.rssi = rssi;
    allowDuplicates = options?.allowDuplicates;
  }

  @override
  Future<void> stopScan() async => stoppedScan = true;
  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async => throw PlatformException(
    code: 'ReadFailed',
    details: {'domain': 'CBATTErrorDomain', 'code': 5},
  );

  @override
  Future<void> openL2cap(String deviceId, int psm) async {
    sockets.add(
      models.PlatformL2CapSocketEvent(
        deviceId: deviceId,
        error: 'Open failed.',
      ),
    );
  }

  Future<void> close() async {
    await states.close();
    await scans.close();
    await restorations.close();
    await sockets.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RestorationObserver
    implements QuickBlueObserver, QuickBlueDarwinRestorationObserver {
  final events = <QuickBlueDarwinRestorationEvent>[];
  @override
  QuickBlueOperationObservation? onOperationStarted(
    QuickBlueOperation operation,
  ) => null;
  @override
  void onDarwinStateRestored(QuickBlueDarwinRestorationEvent event) {
    events.add(event);
  }
}
