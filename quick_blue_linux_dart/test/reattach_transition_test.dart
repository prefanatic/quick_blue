import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;

void main() {
  test(
    'retired disconnect event cannot release pending native reconnect',
    () async {
      await (() async {
        final adapter = fake.Adapter('02:00:00:00:00:01');
        final device = DelayedDevice(adapter, '02:00:00:00:00:03')
          ..connected = false
          ..emit = false;
        addTearDown(device.events.close);
        final owners = <String, String>{};
        final client = fake.Client([adapter])..deviceList = [device];
        addTearDown(client.removed.close);
        final bus = lease.UnlockBus(owners, ':1.1');
        final a = QuickBlueLinux.withClient(
          client,
          connectionLease: DbusConnectionLease.withBus(bus),
        );
        addTearDown(a.close);
        final b = lease.platform(
          [adapter],
          [device],
          adapter.address,
          owners,
          ':1.2',
        );
        await a.device(device.address).connect();
        final nameA = owners.keys.single;
        bus.holdUnlock = true;
        final disconnect = a
            .device(device.address)
            .disconnect()
            .then<Object?>((_) => null, onError: (Object e) => e);
        await bus.entered.future;
        bus.proceed.complete();
        expect(await disconnect, isA<StateError>());
        device.holdConnect = true;
        final reconnect = a.device(device.address).connect();
        await device.connectEntered.future;
        device.events.add(['Connected']);
        await pumpEventQueue();
        final pendingOwner = owners[nameA];
        device.connectProceed.complete();
        await reconnect;
        expect(pendingOwner, ':1.1');
        expect(owners[nameA], ':1.1');
        await b.connect(device.address);
        await b.close();
        expect(device.connected, isTrue);
        expect(device.disconnects, 1);
        await a.close();
        expect(device.disconnects, 2);
        expect(owners, isEmpty);
      })().timeout(const Duration(seconds: 5));
      print('SCENARIO_COMPLETED');
    },
  );
  for (final unlock in [false, true]) {
    for (final fail in [false, true]) {
      test(
        'initial registration joins, waits and retries ($unlock, $fail)',
        () async {
          await (() async {
            final adapter = fake.Adapter('02:00:00:00:00:01');
            final device =
                lease.DisconnectEventDevice(adapter, '02:00:00:00:00:03')
                  ..connected = false
                  ..emit = false;
            addTearDown(device.events.close);
            final owners = <String, String>{};
            final client = fake.Client([adapter])..deviceList = [device];
            addTearDown(client.removed.close);
            final bus = ReattachBus(owners, ':1.1')
              ..holdAttach = true
              ..unlock = unlock;
            final a = QuickBlueLinux.withClient(
              client,
              connectionLease: DbusConnectionLease.withBus(bus),
            );
            addTearDown(a.close);
            addTearDown(() {
              if (!bus.attachProceed.isCompleted) bus.attachProceed.complete();
            });
            var completed = 0;
            final attempts = [
              for (var i = 0; i < 2; i++)
                a.connect(device.address).then<Object?>((_) {
                  completed++;
                  return null;
                }, onError: (Object e) => e),
            ];
            await bus.attachEntered.future;
            await pumpEventQueue();
            final pending = completed;
            bus.failAttach = fail;
            bus.attachProceed.complete();
            final errors = await Future.wait(attempts);
            expect(pending, 0);
            expect(errors, everyElement(fail ? isA<StateError>() : isNull));
            if (fail) {
              expect(owners, isEmpty);
              await a.connect(device.address);
            }
            expect(device.connects, 1);
            expect(owners.length, 1);
            await a.close();
            expect(device.disconnects, 1);
            expect(owners, isEmpty);
          })().timeout(const Duration(seconds: 5));
          print('SCENARIO_COMPLETED');
        },
      );
    }
  }
  for (final lock in [false, true]) {
    for (final accepted in [false, true]) {
      test(
        'request error keeps primary failure and no names ($lock, $accepted)',
        () async {
          final owners = <String, String>{};
          final bus = RequestErrorBus(
            owners,
            ':1.1',
            lock: lock,
            accepted: accepted,
          );
          final connection = DbusConnectionLease.withBus(bus);
          await expectLater(
            connection.attach('adapter/device'),
            throwsA(same(bus.failure)),
          );
          expect(owners, isEmpty);
          await connection.attach('adapter/device');
          expect(owners.length, 1);
          await connection.detach('adapter/device', () async {});
          expect(owners, isEmpty);
        },
      );
    }
  }
  for (final unlock in [false, true]) {
    for (final mode in [
      'event',
      'no event',
      'early event',
      'success first',
      'reply error',
    ]) {
      for (final closePeer in [false, true]) {
        test(
          'pending reattach protects actual membership ($unlock, $mode, $closePeer)',
          () async {
            await (() async {
              final adapter = fake.Adapter('02:00:00:00:00:01');
              const remote = '02:00:00:00:00:03';
              final device = lease.DisconnectEventDevice(adapter, remote)
                ..connected = false
                ..emit = false;
              addTearDown(device.events.close);
              final owners = <String, String>{};
              final client = fake.Client([adapter])..deviceList = [device];
              addTearDown(client.removed.close);
              final bus = ReattachBus(owners, ':1.1')
                ..throwFailure = mode != 'success first'
                ..unlock = unlock;
              final a = QuickBlueLinux.withClient(
                client,
                connectionLease: DbusConnectionLease.withBus(bus),
              );
              addTearDown(a.close);
              final b = lease.platform(
                [adapter],
                [device],
                adapter.address,
                owners,
                ':1.2',
              );
              addTearDown(() {
                if (!bus.attachProceed.isCompleted) {
                  bus.attachProceed.complete();
                }
              });
              await a.device(remote).connect();
              final nameA = owners.keys.single;
              bus.holdUnlock = true;
              final disconnected = a
                  .device(remote)
                  .disconnect()
                  .then<Object?>((_) => null, onError: (Object e) => e);
              await bus.entered.future;
              bus.proceed.complete();
              final error = await disconnected;
              expect(error == null, mode == 'success first');
              if (mode == 'early event') {
                device.events.add(['Connected']);
                await pumpEventQueue();
              }
              bus.holdAttach = true;
              var completed = 0;
              // Direct platform calls must join too, not only facade requests.
              final attempts = [
                for (var i = 0; i < 2; i++)
                  a.connect(remote).then<Object?>((_) {
                    completed++;
                    return null;
                  }, onError: (Object e) => e),
              ];
              await bus.attachEntered.future;
              final beforeReply = completed;
              final acceptedName = owners[nameA];
              if (mode == 'event' || mode == 'reply error') {
                device.events.add(['Connected']);
              }
              await pumpEventQueue();
              final afterEvent = completed;
              bus.failAttach = mode == 'reply error';
              bus.attachProceed.complete();
              final errors = await Future.wait(attempts);
              expect(beforeReply, 0);
              expect(afterEvent, 0);
              expect(acceptedName, ':1.1');
              expect(
                errors,
                everyElement(
                  mode == 'reply error' ? isA<StateError>() : isNull,
                ),
              );
              if (mode == 'reply error') {
                expect(completed, 0);
                expect(owners, isEmpty);
                await a.device(remote).connect();
              } else {
                expect(completed, 2);
              }
              expect(owners[nameA], ':1.1');
              expect(device.connected, isTrue);
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
  }
}

class ReattachBus extends lease.UnlockBus {
  ReattachBus(super.owners, super.uniqueName);
  bool holdAttach = false;
  bool unlock = false;
  bool failAttach = false;
  final attachEntered = Completer<void>();
  final attachProceed = Completer<void>();

  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    final result = await super.requestName(name, flags: flags);
    if (holdAttach && !unlock && !name.endsWith('.Lock')) {
      holdAttach = false;
      attachEntered.complete();
      await attachProceed.future;
      // A rejected registration did not acquire a Client name.
      if (failAttach) {
        await super.releaseName(name);
        return DBusRequestNameReply.exists;
      }
    }
    return result;
  }

  @override
  Future<void> releaseName(String name) async {
    if (holdAttach && unlock && name.endsWith('.Lock')) {
      holdAttach = false;
      attachEntered.complete();
      await attachProceed.future;
      await super.releaseName(name);
      if (failAttach) throw StateError('reattach unlock reply');
      return;
    }
    await super.releaseName(name);
  }
}

class DelayedDevice extends lease.DisconnectEventDevice {
  DelayedDevice(super.adapter, super.remoteAddress);
  bool holdConnect = false;
  final connectEntered = Completer<void>();
  final connectProceed = Completer<void>();
  @override
  Future<void> connect() async {
    if (holdConnect) {
      holdConnect = false;
      connectEntered.complete();
      await connectProceed.future;
    }
    await super.connect();
  }
}

class RequestErrorBus extends lease.Bus {
  RequestErrorBus(
    super.owners,
    super.uniqueName, {
    required this.lock,
    required this.accepted,
  });
  final bool lock;
  final bool accepted;
  final failure = StateError('request transport reply');
  bool armed = true;
  @override
  Future<DBusRequestNameReply> requestName(
    String name, {
    Set<DBusRequestNameFlag> flags = const {},
  }) async {
    if (armed && name.endsWith('.Lock') == lock) {
      armed = false;
      if (accepted) await super.requestName(name, flags: flags);
      throw failure;
    }
    return super.requestName(name, flags: flags);
  }
}
