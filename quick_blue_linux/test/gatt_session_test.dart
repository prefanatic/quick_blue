import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_linux/src/device_property.dart';
import 'package:quick_blue_linux/src/gatt_session.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/future_gate.dart';

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() async {
    await f.session.clearDevice(f.device.address);
    await f.device.properties.close();
    await f.characteristic.properties.close();
  });

  test(
    'discovery waits, coalesces concurrent calls and reports flags',
    () async {
      f.device.servicesResolved = false;
      final first = f.session.discoverServices(f.device);
      final second = f.session.discoverServices(f.device);
      expect(f.discoveries, isEmpty);
      f.device.servicesResolved = true;
      f.device.properties.add(['ServicesResolved']);
      await Future.wait([first, second]);
      expect(f.completions, [f.device.address]);
      expect(f.discoveries.single.$2, '0000180f-0000-1000-8000-00805f9b34fb');
      expect(
        f.discoveries.single.$3.single,
        BluetoothCharacteristicInfo(
          uuid: '00002a19-0000-1000-8000-00805f9b34fb',
          canRead: true,
          canWriteWithResponse: true,
          canWriteWithoutResponse: true,
          canNotify: true,
          canIndicate: true,
        ),
      );
      expect(f.device.properties.hasListener, isFalse);
      await f.session.discoverServices(f.device);
      expect(f.completions.length, 2);
    },
  );

  // Characterizations of 0596865a0a46e18f7dc6d56561a79f538cf7bcea.
  // These passing assertions describe gaps, not desired teardown guarantees.
  test('characterization: old discovery survives clear and reconnect', () async {
    f.device.servicesResolved = false;
    var oldCompleted = false;
    final old = f.session.discoverServices(f.device).then((_) {
      oldCompleted = true;
    });
    expect(f.device.properties.hasListener, isTrue);
    await f.session.clearDevice(f.device.address);
    expect(oldCompleted, isFalse);
    expect(f.device.properties.hasListener, isTrue);

    // A replacement BlueZ object at the same address represents reconnect.
    final replacement = _Device()..gattServices = f.device.gattServices;
    addTearDown(replacement.properties.close);
    await f.session.discoverServices(replacement);
    expect(f.completions, [f.device.address]);
    expect(oldCompleted, isFalse);
    f.device.servicesResolved = true;
    f.device.properties.add(['ServicesResolved']);
    await old;
    expect(f.completions, [f.device.address, f.device.address]);
    expect(f.discoveries.length, 2);
    expect(f.device.properties.hasListener, isFalse);
    // Desired correction: cleared discovery must not emit into a new lifetime.
  });

  test(
    'characterization: suspended StartNotify installs watch after clear',
    () async {
      final gate = FutureGate();
      f.characteristic.startGate = gate;
      final setup = f.notify();
      await gate.entered;
      expect(f.characteristic.starts, 1);
      expect(f.characteristic.properties.hasListener, isFalse);
      await f.session.stopNotificationsForClient(f.device.address);
      await f.session.clearDevice(f.device.address);
      expect(f.characteristic.stops, 0);
      expect(f.values, isEmpty);
      gate.release();
      await setup;
      expect(f.characteristic.notifying, isTrue);
      expect(f.characteristic.properties.hasListener, isTrue);
      expect(f.values.single.$4, [0]);
      f.characteristic.value = [6];
      f.characteristic.properties.add(['Value']);
      await pumpEventQueue();
      expect(f.values.last.$4, [6]);
      expect(f.values.length, 2);
      // The cleared cache also prevents release of the late native reference.
      await f.session.stopNotificationsForClient(f.device.address);
      expect(f.characteristic.stops, 0);
      await f.session.clearDevice(f.device.address);
      expect(f.characteristic.properties.hasListener, isFalse);
      // Desired correction: late setup cannot resurrect delivery or ownership.
    },
  );

  test(
    'characterization: cache invalidation loses last notification release',
    () async {
      f.session.watchDevice(f.device);
      await f.notify();
      expect(f.characteristic.starts, 1);
      f.device.servicesResolved = false;
      f.session.servicesResolvedChanged(f.device);
      expect(f.changes, [f.device.address]);
      expect(f.characteristic.properties.hasListener, isTrue);
      await f.session.stopNotificationsForClient(f.device.address);
      expect(f.characteristic.stops, 0);
      expect(f.characteristic.notifying, isTrue);
      await f.session.clearDevice(f.device.address);
      expect(f.characteristic.properties.hasListener, isFalse);
      expect(f.characteristic.stops, 0);
      // Control: with the cache intact, the same final-client release reaches BlueZ.
      f.device.servicesResolved = true;
      await f.notify();
      await f.session.stopNotificationsForClient(f.device.address);
      expect(f.characteristic.stops, 1);
      expect(f.characteristic.notifying, isFalse);
      // Desired correction: release ownership must survive cache invalidation.
    },
  );

  test('failed discovery releases waiter and allows retry', () async {
    f.device.servicesResolved = false;
    final pending = f.session.discoverServices(f.device);
    final error = StateError('property stream');
    final expectation = expectLater(pending, throwsA(same(error)));
    f.device.properties.addError(error);
    await expectation;
    expect(f.device.properties.hasListener, isFalse);
    f.device.servicesResolved = true;
    await f.session.discoverServices(f.device);
    expect(f.completions, [f.device.address]);
  });

  test(
    'read returns fresh data and emits canonical IDs, not cached Value',
    () async {
      f.characteristic.value = [9];
      f.characteristic.readData = [1, 2];
      final value = await f.read();
      expect(value, [1, 2]);
      expect(f.values.single, (
        f.device.address,
        '0000180f-0000-1000-8000-00805f9b34fb',
        '00002a19-0000-1000-8000-00805f9b34fb',
        value,
      ));
      expect(f.connections, 1);
    },
  );

  test('UUID aliases reuse resolution until explicitly cleared', () async {
    await f.read();
    final replacement = _Characteristic()..readData = [7];
    addTearDown(replacement.properties.close);
    f.device.gattServices = [
      _Service([replacement]),
    ];
    expect(
      await f.session.readCharacteristicValue(
        f.device.address,
        '0000180f-0000-1000-8000-00805f9b34fb',
        '00002a19',
      ),
      [1, 2],
    );
    f.session.clearResolvedCharacteristics(f.device.address);
    expect(await f.read(), [7]);
  });

  test(
    'service and characteristic lookup failures retain error context',
    () async {
      await expectLater(
        f.session.readCharacteristicValue(f.device.address, '1800', '2A19'),
        throwsA(
          isA<QuickBlueException>()
              .having((e) => e.code, 'code', QuickBlueErrorCode.notFound)
              .having((e) => e.operation, 'operation', 'resolveCharacteristic')
              .having((e) => e.serviceId, 'service', '1800'),
        ),
      );
      await expectLater(
        f.session.readCharacteristicValue(f.device.address, '180F', '2A00'),
        throwsA(
          isA<QuickBlueException>().having(
            (e) => e.characteristicId,
            'characteristic',
            '2A00',
          ),
        ),
      );
    },
  );

  for (final property in [
    BleOutputProperty.withResponse,
    BleOutputProperty.withoutResponse,
  ]) {
    test('write maps ${property.value} to BlueZ write type', () async {
      await f.session.writeValue(
        f.device.address,
        '180F',
        '2A19',
        Uint8List.fromList([3]),
        property,
      );
      expect(f.characteristic.writes.single.$1, [3]);
      expect(
        f.characteristic.writes.single.$2,
        property == BleOutputProperty.withResponse
            ? BlueZGattCharacteristicWriteType.request
            : BlueZGattCharacteristicWriteType.command,
      );
    });
  }

  for (final operation in ['readValue', 'writeValue', 'setNotifiable']) {
    test(
      '$operation maps NotAuthorized with complete security context',
      () async {
        f.characteristic.error = BlueZNotAuthorizedException(
          DBusMethodErrorResponse('org.bluez.Error.NotAuthorized', [
            DBusString('denied'),
          ]),
        );
        final Future<Object?> pending;
        switch (operation) {
          case 'readValue':
            pending = f.read();
          case 'writeValue':
            pending = f.session.writeValue(
              f.device.address,
              '180F',
              '2A19',
              Uint8List(0),
              BleOutputProperty.withResponse,
            );
          default:
            pending = f.notify();
        }
        await expectLater(
          pending,
          throwsA(
            isA<QuickBlueSecurityException>()
                .having((e) => e.operation, 'operation', operation)
                .having((e) => e.deviceId, 'device', f.device.address)
                .having(
                  (e) => e.serviceId,
                  'service',
                  operation == 'readValue' ? '180f' : '180F',
                )
                .having(
                  (e) => e.characteristicId,
                  'characteristic',
                  operation == 'readValue' ? '2a19' : '2A19',
                )
                .having(
                  (e) => e.nativeDomain,
                  'domain',
                  'org.bluez.Error.NotAuthorized',
                )
                .having(
                  (e) => e.reason,
                  'reason',
                  QuickBlueSecurityErrorReason.insufficientAuthorization,
                )
                .having((e) => e.message, 'message', 'denied'),
          ),
        );
      },
    );
  }

  test('non-authorization BlueZ failures propagate unchanged', () async {
    final error = StateError('read failed');
    f.characteristic.error = error;
    await expectLater(f.read(), throwsA(same(error)));
  });

  test('notify starts for this client even when globally notifying', () async {
    f.characteristic.notifying = true;
    await f.notify();
    await f.notify();
    expect(f.characteristic.starts, 2);
    expect(f.values.length, 2);
    f.characteristic.value = [5];
    f.characteristic.properties.add(['Value']);
    await pumpEventQueue();
    expect(f.values.length, 3);
    expect(f.values.last.$4, [5]);
    await f.session.setNotifiable(
      f.device.address,
      '180F',
      '2A19',
      BleInputProperty.disabled,
    );
    expect(f.characteristic.stops, 1);
    expect(f.characteristic.properties.hasListener, isFalse);
  });

  test('AlreadyExists still installs the notification watch', () async {
    f.characteristic.error = BlueZAlreadyExistsException(
      DBusMethodErrorResponse('org.bluez.Error.AlreadyExists'),
    );
    await f.notify();
    expect(f.characteristic.properties.hasListener, isTrue);
    expect(f.values.length, 1);
  });

  test('notification mode requires matching flag', () async {
    f.characteristic.flags = {BlueZGattCharacteristicFlag.indicate};
    await expectLater(
      f.notify(),
      throwsA(
        isA<QuickBlueException>().having(
          (e) => e.code,
          'code',
          QuickBlueErrorCode.unsupported,
        ),
      ),
    );
    expect(f.characteristic.starts, 0);
    await f.session.setNotifiable(
      f.device.address,
      '180F',
      '2A19',
      BleInputProperty.indication,
    );
    expect(f.characteristic.starts, 1);
  });

  test('Notifying=false removes subscription without StopNotify', () async {
    await f.notify();
    f.characteristic.notifying = false;
    f.characteristic.properties.add(['Notifying']);
    await pumpEventQueue();
    expect(f.characteristic.properties.hasListener, isFalse);
    expect(f.characteristic.stops, 0);
  });

  test(
    'client notification release logs failures and preserves cleanup',
    () async {
      await f.notify();
      f.characteristic.error = StateError('stop failed');
      await f.session.stopNotificationsForClient(f.device.address);
      expect(f.characteristic.stops, 1);
      await f.session.clearDevice(f.device.address);
      expect(f.characteristic.properties.hasListener, isFalse);
    },
  );

  test('ServicesResolved=false invalidates characteristic cache', () async {
    f.session.watchDevice(f.device);
    await f.read();
    f.device.servicesResolved = false;
    f.session.servicesResolvedChanged(f.device);
    expect(f.changes, [f.device.address]);
    final replacement = _Characteristic()..readData = [8];
    addTearDown(replacement.properties.close);
    f.device.gattServices = [
      _Service([replacement]),
    ];
    f.device.servicesResolved = true;
    expect(await f.read(), [8]);
  });

  test('fingerprints ignore ordering but detect database changes', () async {
    final other = _Characteristic(uuid: '2A00');
    addTearDown(other.properties.close);
    f.device.gattServices = [
      _Service([f.characteristic, other]),
    ];
    await f.session.discoverServices(f.device);
    f.device.gattServices = [
      _Service([other, f.characteristic]),
    ];
    f.session.servicesResolvedChanged(f.device);
    expect(f.changes, isEmpty);
    f.device.gattServices = [
      _Service([other]),
    ];
    f.session.servicesResolvedChanged(f.device);
    expect(f.changes, [f.device.address]);
  });

  test('clearDevice clears cache, discovery state and watches', () async {
    await f.session.discoverServices(f.device);
    await f.notify();
    await f.session.clearDevice(f.device.address);
    expect(f.characteristic.properties.hasListener, isFalse);
    f.device.gattServices = [];
    f.session.servicesResolvedChanged(f.device);
    expect(f.changes, isEmpty);
    await expectLater(f.read(), throwsA(isA<QuickBlueException>()));
  });

  test(
    'shared property wait cancels on timeout and succeeds when already ready',
    () async {
      await expectLater(
        waitForDeviceProperty(
          f.device,
          propertyName: 'ServicesResolved',
          isReady: () => false,
          timeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(f.device.properties.hasListener, isFalse);
      await waitForDeviceProperty(
        f.device,
        propertyName: 'ServicesResolved',
        isReady: () => true,
        timeout: Duration.zero,
      );
      expect(f.device.properties.hasListener, isFalse);
    },
  );

  test(
    'platform delegates discovery/read/write and disconnect cleanup',
    () async {
      final client = _Client(f.device);
      final platform = QuickBlueLinux.withClient(
        client,
        connectionLease: _Lease(),
      );
      final services = <String>[];
      platform.onServiceDiscovered = (_, service, _) => services.add(service);
      await platform.connect(f.device.address);
      await platform.discoverServices(f.device.address);
      expect(services, ['0000180f-0000-1000-8000-00805f9b34fb']);
      expect(
        await platform.readCharacteristicValue(
          f.device.address,
          '180F',
          '2A19',
        ),
        [1, 2],
      );
      await platform.readValue(f.device.address, '180F', '2A19');
      expect(f.characteristic.reads, 2);
      await platform.writeValue(
        f.device.address,
        '180F',
        '2A19',
        Uint8List.fromList([4]),
        BleOutputProperty.withResponse,
      );
      await platform.setNotifiable(
        f.device.address,
        '180F',
        '2A19',
        BleInputProperty.notification,
      );
      await platform.disconnect(f.device.address);
      expect(f.characteristic.writes.single.$1, [4]);
      expect(f.characteristic.stops, 1);
      expect(f.characteristic.properties.hasListener, isFalse);
      expect(f.device.properties.hasListener, isFalse);
    },
  );
}

class _Fixture {
  _Fixture() {
    device.gattServices = [
      _Service([characteristic]),
    ];
    session = LinuxGattSession(
      getDevice: (_) => device,
      ensureConnected: (_) async {
        connections++;
      },
      handleServiceDiscovered: (d, s, c) => discoveries.add((d, s, c)),
      onServiceDiscoveryComplete: completions.add,
      handleCharacteristicValueChanged: (d, s, c, v) =>
          values.add((d, s, c, v)),
      handleGattServicesChanged: changes.add,
      logger: Logger('GattTest'),
    );
  }
  final device = _Device();
  final characteristic = _Characteristic();
  late final LinuxGattSession session;
  final discoveries = <(String, String, List<BluetoothCharacteristicInfo>)>[];
  final completions = <String>[];
  final changes = <String>[];
  final values = <(String, String, String, Uint8List)>[];
  int connections = 0;
  Future<Uint8List> read() =>
      session.readCharacteristicValue(device.address, '180f', '2a19');
  Future<void> notify() => session.setNotifiable(
    device.address,
    '180F',
    '2A19',
    BleInputProperty.notification,
  );
}

class _Device implements BlueZDevice {
  @override
  final address = 'AA:BB:CC:DD:EE:FF';
  @override
  bool connected = true;
  @override
  bool servicesResolved = true;
  @override
  List<BlueZGattService> gattServices = [];
  final properties = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get propertiesChanged => properties.stream;
  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements BlueZGattService {
  _Service(this.characteristics);
  @override
  final uuid = BlueZUUID.fromString('0000180f-0000-1000-8000-00805f9b34fb');
  @override
  final List<BlueZGattCharacteristic> characteristics;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Characteristic implements BlueZGattCharacteristic {
  _Characteristic({String uuid = '2A19'})
    : uuid = BlueZUUID.fromString('0000$uuid-0000-1000-8000-00805f9b34fb');
  @override
  final BlueZUUID uuid;
  @override
  Set<BlueZGattCharacteristicFlag> flags = {
    BlueZGattCharacteristicFlag.read,
    BlueZGattCharacteristicFlag.write,
    BlueZGattCharacteristicFlag.writeWithoutResponse,
    BlueZGattCharacteristicFlag.notify,
    BlueZGattCharacteristicFlag.indicate,
  };
  @override
  bool notifying = false;
  @override
  List<int> value = [0];
  List<int> readData = [1, 2];
  final properties = StreamController<List<String>>.broadcast();
  final writes = <(List<int>, BlueZGattCharacteristicWriteType?)>[];
  Object? error;
  FutureGate? startGate;
  int starts = 0;
  int stops = 0;
  int reads = 0;
  @override
  Stream<List<String>> get propertiesChanged => properties.stream;
  void _checkError() {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<List<int>> readValue({int? offset}) async {
    reads++;
    _checkError();
    return readData;
  }

  @override
  Future<void> writeValue(
    Iterable<int> data, {
    int? offset,
    BlueZGattCharacteristicWriteType? type,
    bool? prepareAuthorize,
  }) async {
    _checkError();
    writes.add((data.toList(), type));
  }

  @override
  Future<void> startNotify() async {
    starts++;
    _checkError();
    final gate = startGate;
    if (gate != null) {
      await gate.suspend();
    }
    notifying = true;
  }

  @override
  Future<void> stopNotify() async {
    stops++;
    _checkError();
    notifying = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BlueZClient {
  _Client(this.device);
  final BlueZDevice device;
  @override
  Future<void> connect() async {}
  @override
  List<BlueZDevice> get devices => [device];
  @override
  List<BlueZAdapter> get adapters => [];
  @override
  Stream<BlueZDevice> get deviceAdded => const Stream.empty();
  @override
  Stream<BlueZDevice> get deviceRemoved => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lease implements QuickBlueLinuxConnectionLease {
  @override
  Future<void> attach(String deviceId) async {}
  @override
  Future<void> detach(String deviceId, Future<void> Function() onLastClient) =>
      onLastClient();
}
