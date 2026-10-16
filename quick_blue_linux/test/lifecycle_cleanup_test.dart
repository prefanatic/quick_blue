import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_linux/src/connection_lease.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';
import 'adapter_selection_test.dart' as adapter_fake;

void main() {
  for (final stage in ['before-start', 'lease', 'native']) {
    test(
      'caller cancellation at $stage preserves join/retry and explicit lease cleanup',
      () async {
        final bus = Bus();
        final device = Device('02:00:00:00:00:01')..connected = false;
        if (stage == 'lease') bus.attachGate = Completer<void>();
        if (stage == 'native') device.connectGate = Completer<void>();
        final client = Client()..deviceList = [device];
        final platform = QuickBlueLinux.withClient(
          client,
          connectionLease: DbusConnectionLease.withBus(bus),
        );
        final handle = platform.device(device.address);
        final token = QuickBlueCancellationToken();
        if (stage == 'before-start') token.cancel();
        final pending = handle.connect(cancellationToken: token);
        final canceled = expectLater(
          pending.timeout(watchdog),
          throwsA(
            isA<QuickBlueException>().having(
              (e) => e.code,
              'code',
              QuickBlueErrorCode.cancelled,
            ),
          ),
        );
        await pumpEventQueue();
        token.cancel();
        await canceled;
        if (stage == 'before-start') {
          expect(bus.requests, isEmpty);
          expect(device.connects, 0);
        } else if (stage == 'lease') {
          expect(bus.owners.length, 1, reason: 'Only the lock is acquired');
          expect(device.connects, 0);
        } else {
          expect(
            bus.owners.length,
            1,
            reason: 'Client lease retained until explicit disconnect',
          );
          expect(device.connects, 1);
        }
        final retry = handle.connect();
        bus.attachGate?.complete();
        device.connectGate?.complete();
        await retry.timeout(watchdog);
        expect(device.connects, 1);
        expect(bus.owners.length, 1);
        await handle.disconnect().timeout(watchdog);
        expect(bus.owners, isEmpty);
        expect(device.disconnects, 1);
        expect(device.properties.hasListener, isFalse);
        await platform.close();
        await client.dispose();
        await device.properties.close();
      },
    );
  }

  test(
    'primary client-registration error survives lock cleanup error',
    () async {
      final bus = Bus()
        ..clientError = StateError('registration')
        ..releaseError = StateError('release');
      await expectLater(
        DbusConnectionLease.withBus(bus).attach('02:00:00:00:00:01'),
        throwsA(same(bus.clientError)),
      );
      expect(bus.owners, isEmpty);
    },
  );

  test('failure after client acquisition rolls back its name', () async {
    final bus = Bus()..releaseError = StateError('release');
    await expectLater(
      DbusConnectionLease.withBus(bus).attach('02:00:00:00:00:01'),
      throwsA(same(bus.releaseError)),
    );
    expect(bus.owners, isEmpty);
  });

  for (final stage in ['connect', 'adapters', 'added', 'removed', 'devices']) {
    test(
      'initialization failure at $stage releases acquired resources',
      () async {
        final client = Client()..failureStage = stage;
        final platform = QuickBlueLinux.withClient(
          client,
          connectionLease: Lease(),
        );
        await expectLater(
          platform.isBluetoothAvailable().timeout(watchdog),
          throwsA(same(client.failure)),
        );
        expect(client.added.hasListener, isFalse);
        expect(client.removed.hasListener, isFalse);
        expect(client.closes, 1);
        await platform.close().timeout(watchdog);
        await platform.close().timeout(watchdog);
        expect(client.closes, 1);
        await client.dispose();
      },
    );
  }

  test(
    'initialization primary error survives transport cleanup error',
    () async {
      final client = Client()
        ..failureStage = 'devices'
        ..closeError = StateError('close');
      final platform = QuickBlueLinux.withClient(
        client,
        connectionLease: Lease(),
      );
      await expectLater(
        platform.isBluetoothAvailable(),
        throwsA(same(client.failure)),
      );
      expect(client.added.hasListener, isFalse);
      expect(client.removed.hasListener, isFalse);
      await client.dispose();
    },
  );

  test('close is idempotent and disconnects only owned devices', () async {
    final owned = Device('02:00:00:00:00:01');
    final unrelated = Device('02:00:00:00:00:02');
    final client = Client()..deviceList = [owned, unrelated];
    final lease = Lease();
    final platform = QuickBlueLinux.withClient(client, connectionLease: lease);
    await platform.connect(owned.address);
    expect(lease.owners, {'${owned.adapter.address}/${owned.address}'});
    await platform.close().timeout(watchdog);
    await platform.close().timeout(watchdog);
    expect(client.closes, 1);
    expect(owned.disconnects, 1);
    expect(unrelated.disconnects, 0);
    expect(owned.properties.hasListener, isFalse);
    expect(lease.owners, isEmpty);
    expect(client.added.hasListener, isFalse);
    expect(client.removed.hasListener, isFalse);
    await expectLater(
      platform.isBluetoothAvailable(),
      throwsA(isA<QuickBlueException>()),
    );
    await client.dispose();
    await owned.properties.close();
    await unrelated.properties.close();
  });

  test(
    'lease permission denial submits no native connect and leaks no name',
    () async {
      final bus = Bus()..deny = true;
      final device = Device('02:00:00:00:00:01')..connected = false;
      final client = Client()..deviceList = [device];
      final platform = QuickBlueLinux.withClient(
        client,
        connectionLease: DbusConnectionLease.withBus(bus),
      );
      await expectLater(
        platform.connect(device.address).timeout(watchdog),
        throwsA(isA<StateError>()),
      );
      expect(device.connects, 0);
      expect(bus.owners, isEmpty);
      bus.deny = false;
      await platform.connect(device.address).timeout(watchdog);
      expect(device.connects, 1);
      expect(bus.owners.length, 1);
      await platform.disconnect(device.address).timeout(watchdog);
      expect(bus.owners, isEmpty);
      await platform.close();
      await client.dispose();
      await device.properties.close();
    },
  );

  test('failed native connect releases DBus owner and allows retry', () async {
    final bus = Bus();
    final device = Device('02:00:00:00:00:01')
      ..connected = false
      ..connectError = StateError('connect');
    final client = Client()..deviceList = [device];
    final platform = QuickBlueLinux.withClient(
      client,
      connectionLease: DbusConnectionLease.withBus(bus),
    );
    await expectLater(
      platform.connect(device.address).timeout(watchdog),
      throwsA(same(device.connectError)),
    );
    expect(device.connects, 1);
    expect(bus.owners, isEmpty);
    device.connectError = null;
    await platform.connect(device.address).timeout(watchdog);
    expect(device.connects, 2);
    expect(bus.owners.length, 1);
    await platform.close();
    expect(bus.owners, isEmpty);
    await client.dispose();
    await device.properties.close();
  });
}

const watchdog = Duration(seconds: 2);

class Lease implements QuickBlueLinuxConnectionLease {
  final owners = <String>{};
  @override
  Future<void> attach(String id) async {
    owners.add(id);
  }

  @override
  Future<void> detach(String id, Future<void> Function() onLastClient) async {
    owners.remove(id);
    await onLastClient();
  }
}

class Bus implements ConnectionLeaseBus {
  final owners = <String>{};
  final requests = <String>[];
  Completer<void>? attachGate;
  bool deny = false;
  Object? clientError;
  Object? releaseError;
  @override
  String get uniqueName => ':1.42';
  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    requests.add(name);
    if (!name.endsWith('.Lock')) await attachGate?.future;
    if (!name.endsWith('.Lock')) {
      if (clientError case final error?) throw error;
    }
    if (deny) throw StateError('permission denied');
    owners.add(name);
    return DBusRequestNameReply.primaryOwner;
  }

  @override
  Future<void> releaseName(String name) async {
    owners.remove(name);
    if (releaseError case final error?) throw error;
  }

  @override
  Future<List<String>> listNames() async => owners.toList();
}

class Client implements BlueZClient {
  final added = StreamController<BlueZDevice>.broadcast();
  final removed = StreamController<BlueZDevice>.broadcast();
  final failure = StateError('setup');
  String? failureStage;
  Object? closeError;
  int closes = 0;
  List<BlueZDevice> deviceList = [];
  void check(String stage) {
    if (stage == failureStage) throw failure;
  }

  @override
  Future<void> connect() async {
    check('connect');
  }

  @override
  List<BlueZAdapter> get adapters {
    check('adapters');
    return [];
  }

  @override
  List<BlueZDevice> get devices {
    check('devices');
    return deviceList;
  }

  @override
  Stream<BlueZDevice> get deviceAdded {
    check('added');
    return added.stream;
  }

  @override
  Stream<BlueZDevice> get deviceRemoved {
    check('removed');
    return removed.stream;
  }

  @override
  Future<void> close() async {
    closes++;
    if (closeError case final error?) throw error;
  }

  Future<void> dispose() async {
    await added.close();
    await removed.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Device implements BlueZDevice {
  Device(this.address);
  @override
  BlueZAdapter get adapter => adapter_fake.Adapter('02:00:00:00:00:00');
  @override
  final String address;
  @override
  bool connected = true;
  @override
  bool servicesResolved = true;
  @override
  List<BlueZGattService> get gattServices => [];
  final properties = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get propertiesChanged => properties.stream;
  int connects = 0;
  int disconnects = 0;
  Object? connectError;
  Completer<void>? connectGate;
  @override
  Future<void> connect() async {
    connects++;
    await connectGate?.future;
    if (connectError case final error?) throw error;
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    connected = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
