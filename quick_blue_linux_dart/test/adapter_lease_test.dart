import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_linux_dart/src/connection_lease.dart';
import 'package:test/test.dart';

import 'adapter_selection_test.dart' as fake;

void main() {
  for (final emit in [false, true]) {
    for (final closePeer in [false, true]) {
      test(
        'failed cleanup restores real membership ($emit, $closePeer)',
        () async {
          await (() async {
            final adapter = fake.Adapter('02:00:00:00:00:01');
            const remote = '02:00:00:00:00:03';
            final device = DisconnectEventDevice(adapter, remote)
              ..connected = false
              ..emit = emit;
            addTearDown(device.events.close);
            final owners = <String, String>{};
            final client = fake.Client([adapter])..deviceList = [device];
            addTearDown(client.removed.close);
            final bus = UnlockBus(owners, ':1.1');
            final a = QuickBlueLinux.withClient(
              client,
              connectionLease: DbusConnectionLease.withBus(bus),
            );
            addTearDown(a.close);
            final b = platform(
              [adapter],
              [device],
              adapter.address,
              owners,
              ':1.2',
            );
            await a.device(remote).connect();
            final nameA = owners.keys.single;
            bus.holdUnlock = true;
            final disconnect = a
                .device(remote)
                .disconnect()
                .then<Object?>((_) => null, onError: (Object error) => error);
            await bus.entered.future;
            await pumpEventQueue();
            bus.proceed.complete();
            expect((await disconnect).toString(), contains('unlock reply'));
            expect(owners, isEmpty);
            await a.device(remote).connect();
            expect(owners[nameA], ':1.1');
            await b.device(remote).connect();
            final before = device.disconnects;
            if (closePeer) {
              await b.close();
            } else {
              await b.device(remote).disconnect();
            }
            await pumpEventQueue();
            expect(device.connected, isTrue);
            expect(device.disconnects, before);
            expect(owners[nameA], ':1.1');
            await a.close();
            await b.close();
            expect(device.connected, isFalse);
            expect(device.disconnects, before + 1);
            expect(owners, isEmpty);
          })().timeout(const Duration(seconds: 5));
          print('SCENARIO_COMPLETED');
        },
      );
    }
  }
  for (final facade in [false, true]) {
    for (final mode in ['late failure', 'no event', 'success']) {
      test('pending native detach stays coherent ($facade, $mode)', () async {
        await (() async {
          final a = fake.Adapter('02:00:00:00:00:01');
          final b = fake.Adapter('02:00:00:00:00:02');
          const remote = '02:00:00:00:00:03';
          final da = DisconnectEventDevice(a, remote)
            ..connected = false
            ..emit = mode != 'no event';
          final db = fake.Device(b, remote)..connected = false;
          addTearDown(da.events.close);
          final owners = <String, String>{};
          final devices = <fake.Device>[da];
          final client = fake.Client([a, b])..deviceList = devices;
          addTearDown(client.removed.close);
          final bus = UnlockBus(owners, ':1.1')
            ..throwFailure = mode != 'success';
          final pa = QuickBlueLinux.withClient(
            client,
            connectionLease: DbusConnectionLease.withBus(bus),
          );
          addTearDown(pa.close);
          final pb = platform([a, b], [db], b.address, owners, ':1.2');
          await pa.device(remote).connect();
          await pb.device(remote).connect();
          bus.holdUnlock = true;
          final disconnect = pa
              .device(remote)
              .disconnect()
              .then<Object?>((_) => null, onError: (Object error) => error);
          await bus.entered.future;
          // Deliver Connected=false while the final lock reply is pending.
          await pumpEventQueue();
          bus.proceed.complete();
          final error = await disconnect;
          if (bus.throwFailure) {
            expect(error.toString(), contains('unlock reply'));
          } else {
            expect(error, isNull);
          }
          devices.add(db);
          await pa.connectedDevices();
          if (facade) {
            await pa.device(remote).connect();
          } else {
            await pa.connect(remote);
          }
          await pa.device(remote).disconnect();
          expect(db.connected, isTrue);
          expect(db.disconnects, 0);
          expect(owners.length, 1);
          await pa.close();
          await pb.close();
          expect(owners, isEmpty);
          expect(da.connected, isFalse);
          expect(db.connected, isFalse);
          expect(db.disconnects, 1);
        })().timeout(const Duration(seconds: 5));
        // An unresolved scenario must fail, never exit silently as a pass.
        print('SCENARIO_COMPLETED');
      });
    }
  }
  for (final closeOnly in [false, true]) {
    test(
      'default cache replacement retains native owner (closeOnly=$closeOnly)',
      () async {
        final a = fake.Adapter('02:00:00:00:00:01');
        final b = fake.Adapter('02:00:00:00:00:02');
        const remote = '02:00:00:00:00:03';
        final da = fake.Device(a, remote)..connected = false;
        final db = fake.Device(b, remote)..connected = false;
        final owners = <String, String>{};
        final devices = [da];
        final pa = platform([a, b], devices, null, owners, ':1.1');
        final pb = platform([a, b], [db], b.address, owners, ':1.2');
        await pa.device(remote).connect();
        await pb.device(remote).connect();
        devices.add(db);
        await pa.connectedDevices();
        if (closeOnly) {
          await pa.close();
        } else {
          await pa.device(remote).disconnect();
        }
        expect(da.disconnects, 1);
        expect(da.connected, isFalse);
        expect(db.disconnects, 0);
        expect(db.connected, isTrue);
        expect(owners.length, 1);
        await pa.close();
        await pb.close();
        expect(db.disconnects, 1);
        expect(owners, isEmpty);
      },
    );
  }
  for (final closeOnly in [false, true]) {
    test(
      'different adapters release independently (closeOnly=$closeOnly)',
      () async {
        final a = fake.Adapter('02:00:00:00:00:01');
        final b = fake.Adapter('02:00:00:00:00:02');
        const remote = '02:00:00:00:00:03';
        final da = fake.Device(a, remote)..connected = false;
        final db = fake.Device(b, remote)..connected = false;
        final owners = <String, String>{};
        final pa = platform([a, b], [da, db], a.address, owners, ':1.1');
        final pb = platform([a, b], [da, db], b.address, owners, ':1.2');
        await pa.device(remote).connect();
        await pb.device(remote).connect();
        expect(owners.length, 2);
        if (closeOnly) {
          await pa.close();
        } else {
          await pa.device(remote).disconnect();
        }
        expect(da.disconnects, 1);
        expect(da.connected, isFalse);
        expect(db.disconnects, 0);
        expect(db.connected, isTrue);
        expect(owners.length, 1);
        if (!closeOnly) await pb.device(remote).disconnect();
        await pa.close();
        await pb.close();
        expect(db.disconnects, 1);
        expect(db.connected, isFalse);
        expect(owners, isEmpty);
      },
    );
  }

  test(
    'default and explicit clients share the same adapter until final close',
    () async {
      final adapter = fake.Adapter('02:00:00:00:00:01');
      final device = fake.Device(adapter)..connected = false;
      final owners = <String, String>{};
      final a = platform([adapter], [device], null, owners, ':1.1');
      final b = platform([adapter], [device], adapter.address, owners, ':1.2');
      await a.device(device.address).connect();
      await b.device(device.address).connect();
      await a.device(device.address).disconnect();
      expect(device.disconnects, 0);
      expect(device.connected, isTrue);
      expect(owners.length, 1);
      await a.close();
      await b.close();
      await b.close();
      expect(device.disconnects, 1);
      expect(device.connected, isFalse);
      expect(owners, isEmpty);
    },
  );

  test('failed selected-adapter connect releases only its own lease', () async {
    final a = fake.Adapter('02:00:00:00:00:01');
    final b = fake.Adapter('02:00:00:00:00:02');
    const remote = '02:00:00:00:00:03';
    final da = fake.Device(a, remote)..connected = false;
    final db = FailingDevice(b, remote)..connected = false;
    final owners = <String, String>{};
    final pa = platform([a, b], [da, db], a.address, owners, ':1.1');
    final pb = platform([a, b], [da, db], b.address, owners, ':1.2');
    await pa.device(remote).connect();
    await expectLater(pb.connect(remote), throwsStateError);
    expect(owners.length, 1);
    await pb.close();
    expect(da.connected, isTrue);
    await pa.close();
    expect(da.disconnects, 1);
    expect(owners, isEmpty);
  });

  test(
    'failed detach keeps original native target through cache replacement',
    () async {
      final a = fake.Adapter('02:00:00:00:00:01');
      final b = fake.Adapter('02:00:00:00:00:02');
      const remote = '02:00:00:00:00:03';
      final da = fake.Device(a, remote)..connected = false;
      final db = fake.Device(b, remote)..connected = false;
      final owners = <String, String>{};
      final devices = [da];
      final client = fake.Client([a, b])..deviceList = devices;
      addTearDown(client.removed.close);
      final bus = RetryBus(owners, ':1.1');
      final pa = QuickBlueLinux.withClient(
        client,
        connectionLease: DbusConnectionLease.withBus(bus),
      );
      addTearDown(pa.close);
      final pb = platform([a, b], [db], b.address, owners, ':1.2');
      await pa.connect(remote);
      await pb.connect(remote);
      devices.add(db);
      await pa.connectedDevices();
      bus.failRelease = true;
      await expectLater(pa.disconnect(remote), throwsStateError);
      expect(owners.length, 2);
      expect(da.connected, isTrue);
      expect(db.connected, isTrue);
      await pa.connect(remote);
      await pa.disconnect(remote);
      expect(da.disconnects, 1);
      expect(db.disconnects, 0);
      await pa.close();
      await pb.close();
      expect(owners, isEmpty);
    },
  );

  test(
    'spontaneous release retires target before retry on replacement',
    () async {
      final a = fake.Adapter('02:00:00:00:00:01');
      final b = fake.Adapter('02:00:00:00:00:02');
      const remote = '02:00:00:00:00:03';
      final da = EventDevice(a, remote)..connected = false;
      final db = EventDevice(b, remote)..connected = false;
      addTearDown(da.events.close);
      addTearDown(db.events.close);
      final owners = <String, String>{};
      final devices = <fake.Device>[da];
      final client = fake.Client([a, b])..deviceList = devices;
      addTearDown(client.removed.close);
      final pa = QuickBlueLinux.withClient(
        client,
        connectionLease: DbusConnectionLease.withBus(Bus(owners, ':1.1')),
      );
      addTearDown(pa.close);
      final pb = platform([a, b], [db], b.address, owners, ':1.2');
      await pa.connect(remote);
      await pb.connect(remote);
      devices.add(db);
      await pa.connectedDevices();
      da.connected = false;
      // Foreign removal must not cancel A's property observer.
      client.removed.add(db);
      await pumpEventQueue();
      da.events.add(['Connected']);
      await pumpEventQueue();
      expect(owners.length, 1);
      expect(db.connected, isTrue);
      await pa.connect(remote);
      expect(owners.length, 2);
      expect(da.connects, 1);
      da.events.add(['Connected']);
      await pumpEventQueue();
      expect(owners.length, 2);
      await pa.close();
      expect(db.connected, isTrue);
      expect(db.disconnects, 0);
      await pb.close();
      expect(db.disconnects, 1);
      expect(owners, isEmpty);
    },
  );
  test(
    'failed default connect retires target before replacement retry',
    () async {
      final a = fake.Adapter('02:00:00:00:00:01');
      final b = fake.Adapter('02:00:00:00:00:02');
      const remote = '02:00:00:00:00:03';
      final da = FailingDevice(a, remote)..connected = false;
      final db = fake.Device(b, remote)..connected = false;
      final owners = <String, String>{};
      final devices = <fake.Device>[da];
      final pa = platform([a, b], devices, null, owners, ':1.1');
      final pb = platform([a, b], [db], b.address, owners, ':1.2');
      await pb.connect(remote);
      await expectLater(pa.connect(remote), throwsStateError);
      expect(owners.length, 1);
      devices.add(db);
      await pa.connectedDevices();
      await pa.connect(remote);
      expect(owners.length, 2);
      await pa.close();
      expect(db.connected, isTrue);
      expect(db.disconnects, 0);
      await pb.close();
      expect(db.disconnects, 1);
      expect(owners, isEmpty);
    },
  );
}

class EventDevice extends fake.Device {
  EventDevice(super.adapter, super.remoteAddress);
  final events = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get propertiesChanged => events.stream;
}

class RetryBus extends Bus {
  RetryBus(super.owners, super.uniqueName);
  bool failRelease = false;
  @override
  Future<void> releaseName(String name) async {
    if (failRelease) {
      failRelease = false;
      throw StateError('release');
    }
    await super.releaseName(name);
  }
}

class DisconnectEventDevice extends EventDevice {
  DisconnectEventDevice(super.adapter, super.remoteAddress);
  bool emit = true;
  @override
  Future<void> disconnect() async {
    await super.disconnect();
    if (emit) events.add(['Connected']);
  }
}

class UnlockBus extends Bus {
  UnlockBus(super.owners, super.uniqueName);
  bool holdUnlock = false;
  bool throwFailure = true;
  final entered = Completer<void>();
  final proceed = Completer<void>();
  @override
  Future<void> releaseName(String name) async {
    if (holdUnlock && name.endsWith('.Lock')) {
      holdUnlock = false;
      entered.complete();
      await proceed.future;
      await super.releaseName(name);
      if (throwFailure) throw StateError('injected unlock reply failure');
      return;
    }
    await super.releaseName(name);
  }
}

QuickBlueLinux platform(
  List<fake.Adapter> adapters,
  List<fake.Device> devices,
  String? address,
  Map<String, String> owners,
  String uniqueName,
) {
  final client = fake.Client(adapters)..deviceList = devices;
  addTearDown(client.removed.close);
  final result = QuickBlueLinux.withClient(
    client,
    adapterAddress: address,
    connectionLease: DbusConnectionLease.withBus(Bus(owners, uniqueName)),
  );
  addTearDown(result.close);
  return result;
}

class FailingDevice extends fake.Device {
  FailingDevice(super.adapter, super.remoteAddress);
  @override
  Future<void> connect() async => throw StateError('connect');
}

class Bus implements ConnectionLeaseBus {
  Bus(this.owners, this.uniqueName);
  final Map<String, String> owners;
  @override
  final String uniqueName;
  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    if (owners[name] == uniqueName) return DBusRequestNameReply.alreadyOwner;
    if (owners.containsKey(name)) return DBusRequestNameReply.exists;
    owners[name] = uniqueName;
    return DBusRequestNameReply.primaryOwner;
  }

  @override
  Future<void> releaseName(String name) async {
    if (owners[name] == uniqueName) owners.remove(name);
  }

  @override
  Future<List<String>> listNames() async => owners.keys.toList();
}
