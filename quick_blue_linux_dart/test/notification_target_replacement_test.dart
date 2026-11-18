import 'dart:async';

import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;
import 'notification_disconnect_test.dart' as notify;

void main() {
  for (final mode in ['same-target', 'replacement', 'obsolete-target']) {
    for (final order in [
      'settled',
      'pending',
      'setup-error',
      'confirmation-error',
    ]) {
      if (mode == 'same-target' &&
          (order == 'setup-error' || order == 'confirmation-error')) {
        continue;
      }
      test('disconnect releases native target: $mode $order', () async {
        final adapter = fake.Adapter('02:00:00:00:00:01');
        final old = Target();
        final current = mode == 'same-target' ? old : Target();
        final device = Device(adapter, old)..connected = false;
        final owners = <String, String>{};
        final client = fake.Client([adapter])..deviceList = [device];
        final a = QuickBlueLinux.withClient(
          client,
          connectionLease: DbusConnectionLease.withBus(
            lease.UnlockBus(owners, ':1.1'),
          ),
        );
        final b = lease.platform([adapter], [device], null, owners, ':1.2');
        addTearDown(() async {
          if (!current.reply.isCompleted) current.reply.complete();
          await a.close();
          await b.close();
          await client.removed.close();
          await device.events.close();
          await old.events.close();
          if (!identical(old, current)) await current.events.close();
        });
        await a.device(device.address).connect();
        await b.connect(device.address);
        Future<void> enable() => a.setNotifiable(
          device.address,
          '180f',
          '2a19',
          BleInputProperty.notification,
        );
        await enable();
        expect(old.clientClaim, isTrue);
        device.resolved = false;
        device.events.add(['ServicesResolved']);
        await pumpEventQueue();
        if (!identical(old, current)) {
          // Keep the old native claim live in the success control: replacing
          // resolution alone must not discard ownership of either endpoint.
          old.removed = mode == 'obsolete-target';
          if (old.removed) old.clientClaim = false;
          device.gattServices
            ..clear()
            ..add(notify.NotificationService([current]));
        }
        device.resolved = true;
        device.events.add(['ServicesResolved']);
        await pumpEventQueue();
        await a.discoverServices(device.address);
        current.holdSetup = true;
        current.failSetup = order == 'setup-error';
        current.failConfirmation = order == 'confirmation-error';
        final setup = enable().then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
        await current.setupEntered.future;
        if (order == 'settled' || order == 'confirmation-error') {
          current.reply.complete();
          expect(
            await setup,
            order == 'confirmation-error' ? isA<StateError>() : isNull,
          );
          if (order == 'confirmation-error') {
            expect(
              current.clientClaim,
              isFalse,
              reason: 'failed setup must release even without disconnect',
            );
          }
          if (!identical(old, current)) {
            expect(
              old.stops,
              mode == 'obsolete-target' && order == 'confirmation-error'
                  ? 2
                  : 1,
              reason: 'retire the obsolete acquisition',
            );
          }
        }
        var disconnected = false;
        final disconnect = a.device(device.address).disconnect().then((_) {
          disconnected = true;
        });
        await pumpEventQueue();
        if (order != 'settled' && order != 'confirmation-error') {
          expect(disconnected, isFalse);
          current.reply.complete();
        }
        final error = await setup;
        expect(
          error,
          order == 'setup-error' || order == 'confirmation-error'
              ? isA<StateError>()
              : isNull,
        );
        await disconnect;
        expect(disconnected, isTrue);
        expect(device.connected, isTrue);
        expect(device.disconnects, 0);
        expect(old.clientClaim, isFalse);
        expect(current.peerClaim, isTrue);
        expect(current.stops, order == 'setup-error' ? 0 : 1);
        expect(current.clientClaim, isFalse);
        expect(current.events.hasListener, isFalse);
        expect(old.events.hasListener, isFalse);
      }, timeout: const Timeout(Duration(seconds: 5)));
    }
  }
}

class Target extends notify.HeldCharacteristic {
  final setupEntered = Completer<void>();
  final reply = Completer<void>();
  var starts = 0;
  var stops = 0;
  var clientClaim = false;
  var removed = false;
  var failSetup = false;
  var failConfirmation = false;
  bool holdSetup = false;
  final peerClaim = true;

  @override
  Future<void> startNotify() async {
    starts++;
    if (failConfirmation && starts == 2) {
      throw StateError('confirmation failed after initial acquisition');
    }
    if (holdSetup && !setupEntered.isCompleted) {
      setupEntered.complete();
      await reply.future;
      if (failSetup) throw StateError('replacement setup failed');
    }
    clientClaim = true;
    notifying = true;
  }

  @override
  Future<void> stopNotify() async {
    stops++;
    if (removed) throw StateError('obsolete native characteristic');
    clientClaim = false;
    notifying = peerClaim;
  }
}

class Device extends notify.NotificationDevice {
  Device(super.adapter, super.characteristic);
  bool resolved = true;
  @override
  bool get servicesResolved => resolved;
}
