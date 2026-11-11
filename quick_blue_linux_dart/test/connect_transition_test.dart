import 'dart:async';

import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;
import 'reattach_transition_test.dart' as reattach;

void main() {
  for (final direct in [false, true]) {
    for (final emit in [false, true]) {
      for (final intent in [
        'final-disconnect',
        'no-second',
        'settle-first',
        'no-reconnect',
        'newer-reconnect',
        'failed-detach',
      ]) {
        test('queued reconnect intent ($direct, $emit, $intent)', () async {
          await (() async {
            final adapter = fake.Adapter('02:00:00:00:00:01');
            final device =
                lease.DisconnectEventDevice(adapter, '02:00:00:00:00:03')
                  ..connected = false
                  ..emit = emit;
            addTearDown(device.events.close);
            final owners = <String, String>{};
            final client = fake.Client([adapter])..deviceList = [device];
            addTearDown(client.removed.close);
            final bus = lease.UnlockBus(owners, ':1.1')
              ..throwFailure = intent == 'failed-detach';
            final a = QuickBlueLinux.withClient(
              client,
              connectionLease: DbusConnectionLease.withBus(bus),
            );
            addTearDown(a.close);
            addTearDown(() {
              if (!bus.proceed.isCompleted) bus.proceed.complete();
            });
            Future<void> connect() => direct
                ? a.connect(device.address)
                : a.device(device.address).connect();
            Future<void> disconnect() => direct
                ? a.disconnect(device.address)
                : a.device(device.address).disconnect();
            Future<Object?> result(Future<void> future) =>
                future.then<Object?>((_) => null, onError: (Object e) => e);
            await connect();
            final nameA = owners.keys.single;
            bus.holdUnlock = true;
            final first = result(disconnect());
            await bus.entered.future;
            final retry = intent == 'no-reconnect'
                ? Future<Object?>.value()
                : result(connect());
            final duplicate = intent == 'no-second'
                ? result(connect())
                : Future<Object?>.value();
            await pumpEventQueue();
            expect(owners.containsKey(nameA), isFalse);
            expect(device.connected, isFalse);
            expect(device.connects, 1);
            if (intent == 'settle-first') {
              bus.proceed.complete();
              expect(await retry, isNull);
            }
            var finalSettled = false;
            final last = intent == 'no-second'
                ? Future<Object?>.value()
                : result(disconnect()).then((error) {
                    finalSettled = true;
                    return error;
                  });
            await pumpEventQueue();
            if (intent != 'no-second' && intent != 'settle-first') {
              expect(finalSettled, isFalse, reason: 'unlock is still pending');
            }
            final newest = intent == 'newer-reconnect'
                ? result(connect())
                : Future<Object?>.value();
            await pumpEventQueue();
            if (!bus.proceed.isCompleted) bus.proceed.complete();
            final errors = await Future.wait([first, retry, last, newest]);
            expect(await duplicate, isNull);
            expect(
              errors[0],
              !direct && intent != 'no-reconnect'
                  ? isCancelled
                  : intent == 'failed-detach'
                  ? isA<StateError>()
                  : isNull,
            );
            await pumpEventQueue();
            final live = intent == 'no-second' || intent == 'newer-reconnect';
            expect(owners.containsKey(nameA), live);
            expect(device.connected, live);
            expect(device.connects, live || intent == 'settle-first' ? 2 : 1);
            if (intent == 'failed-detach') {
              expect(errors[2], isA<StateError>());
              expect(errors[1], direct ? isA<StateError>() : isCancelled);
              // The failed old teardown remains observable and retryable.
              await connect();
              expect(owners[nameA], ':1.1');
              expect(device.connected, isTrue);
            } else {
              expect(
                errors[2],
                !direct && intent == 'newer-reconnect' ? isCancelled : isNull,
              );
              expect(errors[3], isNull);
              if (intent == 'final-disconnect' || intent == 'newer-reconnect') {
                expect(errors[1], isCancelled);
              } else {
                expect(errors[1], isNull);
              }
            }
            if (live || intent == 'failed-detach') {
              final b = lease.platform(
                [adapter],
                [device],
                null,
                owners,
                ':1.2',
              );
              await b.connect(device.address);
              final before = device.disconnects;
              await b.close();
              expect(owners[nameA], ':1.1');
              expect(device.connected, isTrue);
              expect(device.disconnects, before);
            }
            await a.close();
            expect(owners, isEmpty);
            expect(device.connected, isFalse);
          })().timeout(const Duration(seconds: 5));
          print('SCENARIO_COMPLETED');
        });
      }
    }
  }

  for (final direct in [false, true]) {
    for (final emit in [false, true]) {
      for (final failOld in [false, true]) {
        for (final closePeer in [false, true]) {
          test(
            'detach retires native connect ($direct, $emit, $failOld, $closePeer)',
            () async {
              await (() async {
                final adapter = fake.Adapter('02:00:00:00:00:01');
                final device = ReplyDevice(adapter, '02:00:00:00:00:03')
                  ..connected = false
                  ..emit = emit;
                addTearDown(device.events.close);
                final owners = <String, String>{};
                final a = lease.platform(
                  [adapter],
                  [device],
                  null,
                  owners,
                  ':1.1',
                );
                final b = lease.platform(
                  [adapter],
                  [device],
                  null,
                  owners,
                  ':1.2',
                );
                addTearDown(() {
                  if (!device.proceed.isCompleted) device.proceed.complete();
                });
                Future<void> connect() => direct
                    ? a.connect(device.address)
                    : a.device(device.address).connect();
                final first = connect().then<Object?>(
                  (_) => null,
                  onError: (Object e) => e,
                );
                await device.entered.future;
                final nameA = owners.keys.single;
                await b.device(device.address).connect();
                if (direct) {
                  await a.disconnect(device.address);
                } else {
                  await a.device(device.address).disconnect();
                }
                expect(owners.containsKey(nameA), isFalse);
                // The replacement must register before the retired reply arrives.
                var completed = false;
                final retry = connect().then<Object?>((_) {
                  completed = true;
                  return null;
                }, onError: (Object e) => e);
                await pumpEventQueue();
                final registeredBeforeOldReply = owners[nameA] == ':1.1';
                final completedBeforeOldReply = completed;
                device.failReply = failOld;
                device.proceed.complete();
                final retryError = await retry;
                final firstError = await first;
                expect(retryError, isNull);
                expect(completed, isTrue);
                expect(registeredBeforeOldReply, isTrue);
                expect(completedBeforeOldReply, isTrue);
                expect(owners[nameA], ':1.1');
                if (direct && failOld) {
                  expect(firstError, same(device.failure));
                } else {
                  expect(
                    firstError,
                    isA<QuickBlueException>().having(
                      (e) => e.code,
                      'code',
                      QuickBlueErrorCode.cancelled,
                    ),
                  );
                }
                final before = device.disconnects;
                if (closePeer) {
                  await b.close();
                } else {
                  await b.device(device.address).disconnect();
                }
                await pumpEventQueue();
                expect(device.connected, isTrue);
                expect(device.disconnects, before);
                expect(owners[nameA], ':1.1');
                await a.close();
                await b.close();
                expect(owners, isEmpty);
                expect(device.connected, isFalse);
                expect(device.disconnects, before + 1);
              })().timeout(const Duration(seconds: 5));
              print('SCENARIO_COMPLETED');
            },
          );
        }
      }
    }
  }

  for (final failOld in [false, true]) {
    test(
      'retired native reply cannot touch a different adapter ($failOld)',
      () async {
        await (() async {
          final aa = fake.Adapter('02:00:00:00:00:01');
          final ab = fake.Adapter('02:00:00:00:00:02');
          final old = ReplyDevice(aa, '02:00:00:00:00:03')..connected = false;
          final next = lease.DisconnectEventDevice(ab, old.address)
            ..connected = false;
          addTearDown(old.events.close);
          addTearDown(next.events.close);
          final owners = <String, String>{};
          final devices = <fake.Device>[old];
          final a = lease.platform([aa, ab], devices, null, owners, ':1.1');
          final peer = lease.platform([aa], [old], aa.address, owners, ':1.2');
          addTearDown(() {
            if (!old.proceed.isCompleted) old.proceed.complete();
          });
          final first = a
              .connect(old.address)
              .then<Object?>((_) => null, onError: (Object e) => e);
          await old.entered.future;
          await peer.connect(old.address);
          await a.disconnect(old.address);
          devices.add(next);
          await a.connectedDevices();
          final reconnect = a
              .connect(next.address)
              .then<Object?>((_) => null, onError: (Object e) => e);
          await pumpEventQueue();
          old.failReply = failOld;
          old.proceed.complete();
          expect(await reconnect, isNull);
          expect(
            await first,
            failOld ? same(old.failure) : isA<QuickBlueException>(),
          );
          // The new observer must still observe the replacement native object.
          next.connected = false;
          next.events.add(['Connected']);
          await pumpEventQueue();
          expect(owners.length, 1);
          expect(old.connected, isTrue);
          expect(old.disconnects, 0);
          await a.connect(next.address);
          await a.close();
          expect(next.connected, isFalse);
          expect(next.disconnects, 1);
          expect(old.connected, isTrue);
          await peer.close();
          expect(old.disconnects, 1);
          expect(owners, isEmpty);
        })().timeout(const Duration(seconds: 5));
        print('SCENARIO_COMPLETED');
      },
    );
  }

  for (final settleFirst in [false, true]) {
    test('same-lifetime duplicate/settled control ($settleFirst)', () async {
      await (() async {
        final adapter = fake.Adapter('02:00:00:00:00:01');
        final device = ReplyDevice(adapter, '02:00:00:00:00:03')
          ..connected = false;
        addTearDown(device.events.close);
        addTearDown(() {
          if (!device.proceed.isCompleted) device.proceed.complete();
        });
        final owners = <String, String>{};
        final a = lease.platform([adapter], [device], null, owners, ':1.1');
        var completed = 0;
        final first = a.connect(device.address).then((_) {
          completed++;
        });
        await device.entered.future;
        if (settleFirst) {
          device.proceed.complete();
          await first;
        }
        final second = a.connect(device.address).then((_) {
          completed++;
        });
        await pumpEventQueue();
        if (!settleFirst) {
          expect(completed, 0);
          device.proceed.complete();
        }
        await Future.wait([first, second]);
        expect(completed, 2);
        expect(device.connects, 1);
        expect(owners.length, 1);
        await a.close();
        expect(owners, isEmpty);
        expect(device.disconnects, 1);
      })().timeout(const Duration(seconds: 5));
      print('SCENARIO_COMPLETED');
    });
  }

  for (final failOld in [false, true]) {
    test('retired reply cannot remove pending replacement ($failOld)', () async {
      await (() async {
        final adapter = fake.Adapter('02:00:00:00:00:01');
        final device = ReplyDevice(adapter, '02:00:00:00:00:03')
          ..connected = false;
        addTearDown(device.events.close);
        addTearDown(() {
          if (!device.proceed.isCompleted) device.proceed.complete();
        });
        final owners = <String, String>{};
        final client = fake.Client([adapter])..deviceList = [device];
        addTearDown(client.removed.close);
        final bus = reattach.ReattachBus(owners, ':1.1');
        final a = QuickBlueLinux.withClient(
          client,
          connectionLease: DbusConnectionLease.withBus(bus),
        );
        addTearDown(a.close);
        final b = lease.platform([adapter], [device], null, owners, ':1.2');
        addTearDown(() {
          if (!bus.attachProceed.isCompleted) bus.attachProceed.complete();
        });
        final states = <BlueConnectionState>[];
        a.onConnectionChanged = (_, state, _) => states.add(state);
        final first = a
            .connect(device.address)
            .then<Object?>((_) => null, onError: (Object e) => e);
        await device.entered.future;
        await b.connect(device.address);
        await a.disconnect(device.address);
        bus.holdAttach = true;
        var completed = 0;
        final next = a.connect(device.address).then<Object?>((_) {
          completed++;
          return null;
        }, onError: (Object e) => e);
        await pumpEventQueue();
        // Release the retired reply with replacement registration still pending.
        device.failReply = failOld;
        device.proceed.complete();
        final oldError = await first;
        expect(
          oldError,
          failOld ? same(device.failure) : isA<QuickBlueException>(),
        );
        expect(completed, 0);
        final beforeStates = List.of(states);
        final duplicate = a.connect(device.address).then<Object?>((_) {
          completed++;
          return null;
        }, onError: (Object e) => e);
        await pumpEventQueue();
        expect(states, beforeStates);
        // Both Client names are real; the registration also holds the Lock.
        expect(owners.keys.where((name) => !name.endsWith('.Lock')).length, 2);
        bus.attachProceed.complete();
        expect(await Future.wait([next, duplicate]), everyElement(isNull));
        expect(completed, 2);
        expect(device.connects, 1);
        await b.close();
        expect(device.connected, isTrue);
        await a.close();
        expect(owners, isEmpty);
      })().timeout(const Duration(seconds: 5));
      print('SCENARIO_COMPLETED');
    });
  }

  for (final failDetach in [false, true]) {
    test(
      'explicit detach during reattach does not resurrect requester ($failDetach)',
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
          final bus = DetachBus(owners, ':1.1');
          final a = QuickBlueLinux.withClient(
            client,
            connectionLease: DbusConnectionLease.withBus(bus),
          );
          addTearDown(a.close);
          addTearDown(() {
            if (!bus.attachProceed.isCompleted) bus.attachProceed.complete();
          });
          await a.connect(device.address);
          bus.holdUnlock = true;
          final failed = a
              .disconnect(device.address)
              .then<Object?>((_) => null, onError: (Object e) => e);
          await bus.entered.future;
          bus.proceed.complete();
          expect(await failed, isA<StateError>());
          bus.holdAttach = true;
          final retry = a
              .connect(device.address)
              .then<Object?>((_) => null, onError: (Object e) => e);
          await bus.attachEntered.future;
          bus.failRelease = failDetach;
          final detach = a
              .disconnect(device.address)
              .then<Object?>((_) => null, onError: (Object e) => e);
          await pumpEventQueue();
          bus.attachProceed.complete();
          expect(await detach, failDetach ? isA<StateError>() : isNull);
          expect(await retry, isA<QuickBlueException>());
          if (failDetach) {
            // Failed cleanup stays explicit and retryable, not a successful connect.
            await a.connect(device.address);
            expect(owners.length, 1);
            await a.disconnect(device.address);
          }
          expect(owners, isEmpty);
          expect(device.connected, isFalse);
          await a.close();
        })().timeout(const Duration(seconds: 5));
        print('SCENARIO_COMPLETED');
      },
    );
  }
}

final isCancelled = isA<QuickBlueException>().having(
  (e) => e.code,
  'code',
  QuickBlueErrorCode.cancelled,
);

class ReplyDevice extends lease.DisconnectEventDevice {
  ReplyDevice(super.adapter, super.remoteAddress);
  final entered = Completer<void>();
  final proceed = Completer<void>();
  final failure = StateError('retired native Connect reply');
  bool failReply = false;
  bool first = true;
  @override
  Future<void> connect() async {
    await super.connect();
    if (first) {
      first = false;
      entered.complete();
      await proceed.future;
      if (failReply) throw failure;
    }
  }
}

class DetachBus extends reattach.ReattachBus {
  DetachBus(super.owners, super.uniqueName);
  bool failRelease = false;
  @override
  Future<void> releaseName(String name) async {
    if (failRelease && !name.endsWith('.Lock')) {
      failRelease = false;
      throw StateError('detach Client release');
    }
    await super.releaseName(name);
  }
}
