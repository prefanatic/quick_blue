import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;
import 'connect_transition_test.dart' show isCancelled;

void main() {
  for (final direct in [false, true]) {
    for (final emit in [false, true]) {
      for (final intent in [
        'reconnect',
        'settle-first',
        'no-reconnect',
        'final-disconnect',
        'newer-reconnect',
        'duplicate',
        'stop-error',
        'detach-error',
        'peer-disconnect',
        'peer-close',
        'early-event',
        'delayed-event',
      ]) {
        test('notification disconnect ($direct, $emit, $intent)', () async {
          await (() async {
            final adapter = fake.Adapter('02:00:00:00:00:01');
            final characteristic = HeldCharacteristic()
              ..fail = intent == 'stop-error';
            final notificationErrors = <Object?>[];
            final logs = Logger.root.onRecord.listen((record) {
              if (record.message.contains('notification for')) {
                notificationErrors.add(record.error);
              }
            });
            addTearDown(logs.cancel);
            final device = NotificationDevice(adapter, characteristic)
              ..connected = false
              ..emit = emit;
            addTearDown(device.events.close);
            addTearDown(characteristic.events.close);
            final owners = <String, String>{};
            final client = fake.Client([adapter])..deviceList = [device];
            addTearDown(client.removed.close);
            final bus = lease.UnlockBus(owners, ':1.1');
            final a = QuickBlueLinux.withClient(
              client,
              connectionLease: DbusConnectionLease.withBus(bus),
            );
            addTearDown(a.close);
            addTearDown(() {
              if (!characteristic.proceed.isCompleted) {
                characteristic.proceed.complete();
              }
              if (!bus.proceed.isCompleted) bus.proceed.complete();
            });
            Future<void> connect() => direct
                ? a.connect(device.address)
                : a
                      .device(device.address)
                      .connect(timeout: const Duration(milliseconds: 500));
            Future<void> disconnect() => direct
                ? a.disconnect(device.address)
                : a.device(device.address).disconnect();
            Future<Object?> result(Future<void> future) =>
                future.then<Object?>((_) => null, onError: (Object e) => e);
            await connect();
            final nameA = owners.keys.single;
            await a.setNotifiable(
              device.address,
              '180f',
              '2a19',
              BleInputProperty.notification,
            );
            bus.holdUnlock = intent == 'detach-error';
            final first = result(disconnect());
            await characteristic.entered.future;
            if (intent == 'early-event') {
              device.connected = false;
              device.events.add(['Connected']);
              await pumpEventQueue();
            }
            if (intent == 'settle-first') {
              characteristic.proceed.complete();
              expect(await first, isNull);
            }
            var retrySettled = false;
            final retry = intent == 'no-reconnect'
                ? Future<Object?>.value()
                : result(connect()).then((error) {
                    retrySettled = true;
                    return error;
                  });
            final duplicate = intent == 'duplicate'
                ? result(connect())
                : Future<Object?>.value();
            await pumpEventQueue();
            final settledBeforeReply = retrySettled;
            if (intent == 'delayed-event') {
              device.connected = false;
              device.events.add(['Connected']);
              await pumpEventQueue();
            }
            final last =
                intent == 'final-disconnect' || intent == 'newer-reconnect'
                ? result(disconnect())
                : Future<Object?>.value();
            await pumpEventQueue();
            final newest = intent == 'newer-reconnect'
                ? result(connect())
                : Future<Object?>.value();
            if (!characteristic.proceed.isCompleted) {
              characteristic.proceed.complete();
            }
            if (intent == 'detach-error') {
              await bus.entered.future;
              bus.proceed.complete();
            }
            final errors = await Future.wait([first, retry, last, newest]);
            final duplicateError = await duplicate;
            await pumpEventQueue();
            final attached = owners[nameA] == ':1.1';
            final connected = device.connected;
            Object? restoreError;
            if (intent == 'detach-error') {
              restoreError = await result(connect());
            }
            final restoredAfterFailure =
                owners[nameA] == ':1.1' && device.connected;
            final live =
                intent != 'no-reconnect' && intent != 'final-disconnect';
            if (live && owners.containsKey(nameA)) {
              final b = lease.platform(
                [adapter],
                [device],
                null,
                owners,
                ':1.2',
              );
              await b.connect(device.address);
              final before = device.disconnects;
              if (intent == 'peer-disconnect') {
                await b.disconnect(device.address);
              }
              await b.close();
              expect(owners[nameA], ':1.1');
              expect(device.connected, isTrue);
              expect(device.disconnects, before);
              // A replacement watch/notification must survive old state cleanup.
              await a.setNotifiable(
                device.address,
                '180f',
                '2a19',
                BleInputProperty.notification,
              );
              expect(characteristic.notifying, isTrue);
              expect(characteristic.events.hasListener, isTrue);
            }
            await a.close();
            expect(owners, isEmpty);
            expect(device.connected, isFalse);
            expect(characteristic.notifying, isFalse);
            expect(characteristic.events.hasListener, isFalse);
            expect(device.events.hasListener, isFalse);
            print('SCENARIO_COMPLETED');
            if (intent == 'stop-error') {
              expect(notificationErrors, contains(isA<StateError>()));
            }
            if (intent == 'detach-error') {
              expect(errors[0], direct ? isA<StateError>() : isCancelled);
              expect(errors[1], isA<StateError>());
              expect(restoreError, isNull);
              expect(restoredAfterFailure, isTrue);
            } else {
              expect(attached, live);
              expect(connected, live);
              expect(
                errors[0],
                !direct && intent != 'no-reconnect' && intent != 'settle-first'
                    ? isCancelled
                    : isNull,
              );
              expect(
                errors[1],
                intent == 'final-disconnect' || intent == 'newer-reconnect'
                    ? isCancelled
                    : isNull,
              );
              expect(
                errors[2],
                !direct && intent == 'newer-reconnect' ? isCancelled : isNull,
              );
              expect(errors[3], isNull);
              expect(duplicateError, isNull);
            }
            if (intent != 'settle-first') {
              expect(settledBeforeReply, isFalse);
            }
          })().timeout(const Duration(seconds: 5));
        });
      }
    }
  }
}

class HeldCharacteristic implements BlueZGattCharacteristic {
  @override
  final uuid = BlueZUUID.fromString('00002a19-0000-1000-8000-00805f9b34fb');
  @override
  Set<BlueZGattCharacteristicFlag> get flags => {
    BlueZGattCharacteristicFlag.notify,
  };
  @override
  bool notifying = false;
  @override
  List<int> get value => [0];
  final events = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get propertiesChanged => events.stream;
  final entered = Completer<void>();
  final proceed = Completer<void>();
  bool hold = true;
  bool fail = false;
  @override
  Future<void> startNotify() async => notifying = true;
  @override
  Future<void> stopNotify() async {
    if (hold) {
      hold = false;
      entered.complete();
      await proceed.future;
    }
    notifying = false;
    if (fail) {
      fail = false;
      throw StateError('late StopNotify reply');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NotificationService implements BlueZGattService {
  NotificationService(this.characteristics);
  @override
  final uuid = BlueZUUID.fromString('0000180f-0000-1000-8000-00805f9b34fb');
  @override
  final List<BlueZGattCharacteristic> characteristics;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NotificationDevice extends lease.DisconnectEventDevice {
  NotificationDevice(BlueZAdapter adapter, HeldCharacteristic characteristic)
    : gattServices = [
        NotificationService([characteristic]),
      ],
      super(adapter, '02:00:00:00:00:03');
  @override
  final List<BlueZGattService> gattServices;
}
