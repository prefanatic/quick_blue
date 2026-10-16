import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;
import 'connect_transition_test.dart' show isCancelled;
import 'notification_disconnect_test.dart' as notify;

void main() {
  for (final boundary in ['gatt', 'scan', 'observer']) {
    for (final directFirst in [false, true]) {
      for (final directLast in [false, true]) {
        for (final intent in [
          'final',
          'duplicate-final',
          'newer',
          'reconnect',
          'no-event',
          'event-after',
          'cancel-error',
        ]) {
          test(
            'clear completion ($boundary, $directFirst, $directLast, $intent)',
            () async {
              await (() async {
                final adapter = fake.Adapter('02:00:00:00:00:01');
                final characteristic = ClearCharacteristic()..hold = false;
                final device = ClearDevice(adapter, characteristic)
                  ..emit = false;
                final gate = boundary == 'gatt'
                    ? characteristic.controlled
                    : device.controlled;
                gate.fail = intent == 'cancel-error';
                final owners = <String, String>{};
                final client = fake.Client([adapter])..deviceList = [device];
                final a = QuickBlueLinux.withClient(
                  client,
                  connectionLease: DbusConnectionLease.withBus(
                    lease.Bus(owners, ':1.1'),
                  ),
                );
                addTearDown(device.events.close);
                addTearDown(characteristic.events.close);
                addTearDown(client.removed.close);
                addTearDown(a.close);
                addTearDown(() {
                  if (!gate.proceed.isCompleted) gate.proceed.complete();
                });
                Future<Object?> result(Future<void> f) =>
                    f.then<Object?>((_) => null, onError: (Object e) => e);
                Future<void> connect() => a
                    .device(device.address)
                    .connect(timeout: const Duration(milliseconds: 500));
                Future<void> disconnect(bool direct) => direct
                    ? a.disconnect(device.address)
                    : a
                          .device(device.address)
                          .disconnect(
                            timeout: const Duration(milliseconds: 500),
                          );
                await connect();
                final nameA = owners.keys.single;
                final states = <BlueConnectionState>[];
                final stateSubscription = a.connectionStateStream.listen(
                  (event) => states.add(event.state),
                );
                addTearDown(stateSubscription.cancel);
                await a.setNotifiable(
                  device.address,
                  '180f',
                  '2a19',
                  BleInputProperty.notification,
                );
                StreamSubscription<BlueScanResult>? scan;
                gate.holdSubscription = boundary == 'gatt'
                    ? characteristic.controlled.listenCount
                    : device.controlled.listenCount;
                if (boundary == 'scan') {
                  final beforeScan = device.controlled.listenCount;
                  await a.startScan();
                  scan = a.scanResultStream.listen((_) {});
                  await pumpEventQueue();
                  expect(device.controlled.listenCount, beforeScan + 1);
                  gate.holdSubscription = device.controlled.listenCount;
                }
                // Arm only after setup has installed its final observers.
                gate.armed = true;
                final first = result(disconnect(directFirst));
                await gate.entered.future;
                expect(device.connected, isFalse);
                expect(owners, isEmpty);
                void emit() => device.events.add(['Connected']);
                if (intent != 'no-event' && intent != 'event-after') {
                  emit();
                  await pumpEventQueue();
                }
                var retrySettled = false;
                final retry = result(connect()).then((error) {
                  retrySettled = true;
                  return error;
                });
                await pumpEventQueue();
                final settledBeforeReply = retrySettled;
                final last = intent == 'reconnect'
                    ? Future<Object?>.value()
                    : result(disconnect(directLast));
                await pumpEventQueue();
                final duplicate = intent == 'duplicate-final'
                    ? result(disconnect(directLast))
                    : Future<Object?>.value();
                await pumpEventQueue();
                if (intent == 'event-after') {
                  emit();
                  await pumpEventQueue();
                }
                final newest = intent == 'newer'
                    ? result(directLast ? a.connect(device.address) : connect())
                    : Future<Object?>.value();
                await pumpEventQueue();
                final eventsBeforeReply = states.length;
                gate.proceed.complete();
                final errors = await Future.wait([
                  first,
                  retry,
                  last,
                  duplicate,
                  newest,
                ]);
                await pumpEventQueue();
                final live = intent == 'newer' || intent == 'reconnect';
                final attached = owners[nameA] == ':1.1';
                final connected = device.connected;
                final completionStates = states
                    .skip(eventsBeforeReply)
                    .toList();
                Object? restoreError;
                if (intent == 'cancel-error') {
                  restoreError = await result(connect());
                }
                final restored = owners[nameA] == ':1.1' && device.connected;
                if (live || intent == 'cancel-error') {
                  final b = lease.platform(
                    [adapter],
                    [device],
                    null,
                    owners,
                    ':1.2',
                  );
                  await b.connect(device.address);
                  await b.disconnect(device.address);
                  await b.close();
                  expect(owners[nameA], ':1.1');
                  expect(device.connected, isTrue);
                  await a.setNotifiable(
                    device.address,
                    '180f',
                    '2a19',
                    BleInputProperty.notification,
                  );
                  expect(characteristic.events.hasListener, isTrue);
                }
                await scan?.cancel();
                if (scan != null) await a.stopScan();
                await a.close();
                expect(owners, isEmpty);
                expect(device.connected, isFalse);
                expect(characteristic.notifying, isFalse);
                expect(characteristic.events.hasListener, isFalse);
                expect(device.events.hasListener, isFalse);
                print('SCENARIO_COMPLETED');
                expect(settledBeforeReply, isFalse);
                if (intent == 'cancel-error') {
                  expect(
                    errors[0],
                    directFirst ? isA<StateError>() : isCancelled,
                  );
                  expect(
                    errors[1],
                    directLast ? isA<StateError>() : isCancelled,
                  );
                  expect(errors[2], isA<StateError>());
                  expect(restoreError, isNull);
                  expect(restored, isTrue);
                } else {
                  expect(attached, live);
                  expect(connected, live);
                  expect(completionStates, [
                    BlueConnectionState.disconnected,
                    if (live) BlueConnectionState.connected,
                  ]);
                  expect(errors[0], directFirst ? isNull : isCancelled);
                  expect(
                    errors[1],
                    intent == 'reconnect' ? isNull : isCancelled,
                  );
                  expect(
                    errors[2],
                    intent == 'newer' && !directLast ? isCancelled : isNull,
                  );
                  expect(errors[3], isNull);
                  expect(errors[4], isNull);
                }
              })().timeout(const Duration(seconds: 5));
            },
          );
        }
      }
    }
  }
}

// Cancel the real subscription before holding its asynchronous cleanup reply.
// No event can be delivered to that cancelled listener while the reply is held.
class HeldCancelStream<T> extends Stream<T> {
  HeldCancelStream(this.source);
  final Stream<T> source;
  final entered = Completer<void>();
  final proceed = Completer<void>();
  int listenCount = 0;
  int holdSubscription = 1;
  bool armed = false;
  bool fail = false;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => HeldCancelSubscription(
    source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
    this,
    ++listenCount,
  );
}

class HeldCancelSubscription<T> implements StreamSubscription<T> {
  HeldCancelSubscription(this.inner, this.owner, this.index);
  final StreamSubscription<T> inner;
  final HeldCancelStream<T> owner;
  final int index;

  @override
  Future<void> cancel() async {
    await inner.cancel();
    if (owner.armed && index == owner.holdSubscription) {
      owner.armed = false;
      owner.entered.complete();
      await owner.proceed.future;
      if (owner.fail) throw StateError('subscription cleanup reply');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClearCharacteristic extends notify.HeldCharacteristic {
  late final controlled = HeldCancelStream(events.stream);
  @override
  Stream<List<String>> get propertiesChanged => controlled;
}

class ClearDevice extends notify.NotificationDevice {
  ClearDevice(super.adapter, super.characteristic);
  late final controlled = HeldCancelStream(events.stream);
  @override
  Stream<List<String>> get propertiesChanged => controlled;
  @override
  String get alias => 'clear-test';
  @override
  int get rssi => -50;
  @override
  Map<BlueZManufacturerId, List<int>> get manufacturerData => {};
  @override
  Map<BlueZUUID, List<int>> get serviceData => {};
  @override
  List<BlueZUUID> get uuids => [];
}
