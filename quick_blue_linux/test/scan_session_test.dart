import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:test/test.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  late _Client client;
  late _Adapter adapter;
  late _Device device;
  late QuickBlueLinux platform;
  late List<BlueScanResult> results;
  StreamSubscription<BlueScanResult>? subscription;

  setUp(() {
    adapter = _Adapter();
    device = _Device();
    client = _Client(adapter, device);
    platform = QuickBlueLinux.withClient(client);
    results = [];
    subscription = null;
  });
  tearDown(() async {
    adapter.stopError = null;
    await platform.stopScan();
    await subscription?.cancel();
    await device.properties.close();
    await client.added.close();
    await client.removed.close();
  });
  Future<void> listen() async {
    subscription = platform.scanResultStream.listen(results.add);
    await pumpEventQueue();
  }

  Future<void> change(String property) async {
    device.properties.add([property]);
    await pumpEventQueue();
  }

  test(
    'sets canonical native filters before discovery with option precedence',
    () async {
      await platform.startScan(
        scanFilter: ScanFilter(serviceUuids: ['180D'], rssi: -60),
        scanOptions: ScanOptions(
          allowDuplicates: true,
          linux: const LinuxScanOptions(
            rssi: -90,
            pathloss: 80,
            transport: LinuxScanTransport.bredr,
            duplicateData: false,
            discoverable: true,
            pattern: 'AA',
          ),
        ),
      );
      expect(adapter.calls, ['filter', 'start']);
      expect(adapter.filter, {
        'uuids': ['0000180d-0000-1000-8000-00805f9b34fb'],
        'rssi': -60,
        'pathloss': 80,
        'transport': 'bredr',
        'duplicateData': false,
        'discoverable': true,
        'pattern': 'AA',
      });
    },
  );

  test('default and common native options are preserved', () async {
    await platform.startScan();
    expect(adapter.filter['uuids'], isNull);
    expect(adapter.filter['transport'], 'le');
    expect(adapter.filter['duplicateData'], false);
    await platform.stopScan();
    await platform.startScan(
      scanOptions: ScanOptions(
        allowDuplicates: true,
        linux: const LinuxScanOptions(
          rssi: -75,
          transport: LinuxScanTransport.auto,
        ),
      ),
    );
    expect(adapter.filter['rssi'], -75);
    expect(adapter.filter['transport'], 'auto');
    expect(adapter.filter['duplicateData'], true);
  });

  test(
    'late listener replays cached devices and converts advertisements',
    () async {
      device.manufacturerData = {
        const BlueZManufacturerId(8): [8, 9],
        const BlueZManufacturerId(2): [2],
      };
      device.serviceData = {
        BlueZUUID.short(0x180d): [1, 2],
      };
      await platform.startScan();
      await listen();
      expect(results, hasLength(1));
      final result = results.single;
      expect(result.name, 'alias');
      expect(result.manufacturerDataHead, [2]);
      expect(result.manufacturerData, [2, 8, 9]);
      expect(result.serviceUuids, ['0000180d-0000-1000-8000-00805f9b34fb']);
      expect(result.serviceData.values.single, [1, 2]);
      device.alias = '';
      await change('Alias');
      expect(results.last.name, 'sensor');
    },
  );

  test(
    'existing listeners wait for device events rather than start replay',
    () async {
      await listen();
      await platform.startScan();
      await pumpEventQueue();
      expect(results, isEmpty);
      client.added.add(device);
      await pumpEventQueue();
      expect(results, hasLength(1));
      client.added.add(device);
      await pumpEventQueue();
      await change('RSSI');
      expect(results, hasLength(3));
      await change('Connected');
      expect(results, hasLength(3));
    },
  );

  test('service UUID filters match any canonical UUID', () async {
    await platform.startScan(
      scanFilter: ScanFilter(serviceUuids: ['180F', '0000180D']),
    );
    await listen();
    expect(results, hasLength(1));
    device.uuids = [BlueZUUID.short(0x1810)];
    await change('UUIDs');
    expect(results, hasLength(1));
  });

  test('all manufacturer prefixes and service data must match', () async {
    device.manufacturerData = {
      const BlueZManufacturerId(1): [1, 2],
      const BlueZManufacturerId(2): [3],
    };
    device.serviceData = {
      BlueZUUID.short(0x180d): [4, 5],
    };
    await platform.startScan(
      scanFilter: ScanFilter(
        manufacturerData: {
          1: Uint8List.fromList([1]),
          2: Uint8List.fromList([3]),
        },
        serviceData: {
          '180d': Uint8List.fromList([4]),
        },
      ),
    );
    await listen();
    expect(results, hasLength(1));
    device.manufacturerData[const BlueZManufacturerId(1)] = [];
    await change('ManufacturerData');
    expect(results, hasLength(1));
    device.manufacturerData[const BlueZManufacturerId(1)] = [9];
    await change('ManufacturerData');
    expect(results, hasLength(1));
    device.manufacturerData.remove(const BlueZManufacturerId(2));
    await change('ManufacturerData');
    expect(results, hasLength(1));
    device.manufacturerData = {
      const BlueZManufacturerId(1): [1],
      const BlueZManufacturerId(2): [3],
    };
    device.serviceData = {};
    await change('ServiceData');
    expect(results, hasLength(1));
  });

  test(
    'RSSI boundary is inclusive and scan filter overrides linux RSSI',
    () async {
      await platform.startScan(
        scanFilter: ScanFilter(rssi: -60),
        scanOptions: ScanOptions(linux: const LinuxScanOptions(rssi: -40)),
      );
      await listen();
      expect(results, hasLength(1));
      device.rssi = -61;
      await change('RSSI');
      expect(results, hasLength(1));
    },
  );

  test(
    'pathloss boundary is exclusive and unknown txPower bypasses it',
    () async {
      device.txPower = 10;
      await platform.startScan(
        scanOptions: ScanOptions(linux: const LinuxScanOptions(pathloss: 70)),
      );
      await listen();
      expect(results, isEmpty);
      device.rssi = -59;
      await change('RSSI');
      expect(results, hasLength(1));
      device.txPower = 0;
      device.rssi = -100;
      await change('RSSI');
      expect(results, hasLength(2));
    },
  );

  test('pattern matches address or name, not alias', () async {
    await platform.startScan(
      scanOptions: ScanOptions(linux: const LinuxScanOptions(pattern: 'sens')),
    );
    await listen();
    expect(results, hasLength(1));
    device.name = 'other';
    device.alias = 'sensor';
    await change('Name');
    expect(results, hasLength(1));
    await platform.stopScan();
    await platform.startScan(
      scanOptions: ScanOptions(linux: const LinuxScanOptions(pattern: 'AA')),
    );
    client.added.add(device);
    await pumpEventQueue();
    expect(results, hasLength(2));
  });

  test('stop failure cancels watches and next scan resets filters', () async {
    await platform.startScan(scanFilter: ScanFilter(rssi: -40));
    await listen();
    expect(device.properties.hasListener, isTrue);
    adapter.stopError = StateError('stop failed');
    await expectLater(platform.stopScan(), throwsStateError);
    expect(device.properties.hasListener, isFalse);
    client.added.add(device);
    await pumpEventQueue();
    expect(results, isEmpty);
    adapter.stopError = null;
    await platform.startScan();
    client.added.add(device);
    await pumpEventQueue();
    expect(results, hasLength(1));
  });

  test('removal and adapterless stop cancel property watches', () async {
    await platform.startScan();
    await listen();
    client.removed.add(device);
    await pumpEventQueue();
    expect(device.properties.hasListener, isFalse);
    client.added.add(device);
    await pumpEventQueue();
    expect(device.properties.hasListener, isTrue);
    client.adapters.clear();
    expect(await platform.isBluetoothAvailable(), isFalse);
    await platform.stopScan();
    expect(device.properties.hasListener, isFalse);
  });

  test('failed discovery never activates result emission', () async {
    adapter.startError = StateError('start failed');
    await expectLater(platform.startScan(), throwsStateError);
    await listen();
    client.added.add(device);
    await pumpEventQueue();
    expect(results, isEmpty);
    expect(device.properties.hasListener, isFalse);
  });

  test(
    'scan requires a powered adapter and validates UUIDs before discovery',
    () async {
      adapter.powered = false;
      await expectLater(
        platform.startScan(),
        throwsA(
          isA<QuickBlueException>().having(
            (e) => e.code,
            'code',
            QuickBlueErrorCode.unavailable,
          ),
        ),
      );
      adapter.powered = true;
      await expectLater(
        platform.startScan(scanFilter: ScanFilter(serviceUuids: ['bad'])),
        throwsArgumentError,
      );
      expect(adapter.calls, isEmpty);
    },
  );
}

class _Client implements BlueZClient {
  _Client(_Adapter adapter, _Device device)
    : adapters = [adapter],
      devices = [device];
  @override
  final List<BlueZAdapter> adapters;
  @override
  final List<BlueZDevice> devices;
  final added = StreamController<BlueZDevice>.broadcast();
  final removed = StreamController<BlueZDevice>.broadcast();
  @override
  Stream<BlueZDevice> get deviceAdded => added.stream;
  @override
  Stream<BlueZDevice> get deviceRemoved => removed.stream;
  @override
  Future<void> connect() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements BlueZAdapter {
  @override
  bool powered = true;
  final calls = <String>[];
  Map<String, Object?> filter = {};
  Object? stopError;
  Object? startError;
  @override
  Future<void> setDiscoveryFilter({
    List<String>? uuids,
    int? rssi,
    int? pathloss,
    String? transport,
    bool? duplicateData,
    bool? discoverable,
    String? pattern,
  }) async {
    calls.add('filter');
    filter = {
      'uuids': uuids,
      'rssi': rssi,
      'pathloss': pathloss,
      'transport': transport,
      'duplicateData': duplicateData,
      'discoverable': discoverable,
      'pattern': pattern,
    };
  }

  @override
  Future<void> startDiscovery() async {
    calls.add('start');
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stopDiscovery() async {
    calls.add('stop');
    if (stopError != null) throw stopError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Device implements BlueZDevice {
  final properties = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get propertiesChanged => properties.stream;
  @override
  String get address => 'AA:BB:CC:DD:EE:FF';
  @override
  String alias = 'alias';
  @override
  String name = 'sensor';
  @override
  int rssi = -60;
  @override
  int txPower = 0;
  @override
  List<BlueZUUID> uuids = [BlueZUUID.short(0x180d)];
  @override
  Map<BlueZUUID, List<int>> serviceData = {};
  @override
  Map<BlueZManufacturerId, List<int>> manufacturerData = {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
