import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;
import 'notification_disconnect_test.dart' as notify;

void main() {
  for (final reply in ['already-exists', 'success', 'error']) {
    for (final order in ['pending', 'settled']) {
      test(
        'disconnect releases claim after $order reconfiguration $reply',
        () async {
          final adapter = fake.Adapter('02:00:00:00:00:01');
          final characteristic = ReconfiguredCharacteristic(reply)
            ..hold = false;
          final device = notify.NotificationDevice(adapter, characteristic)
            ..connected = false;
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
            if (!characteristic.reply.isCompleted) {
              characteristic.reply.complete();
            }
            await a.close();
            await b.close();
            await client.removed.close();
            await device.events.close();
            await characteristic.events.close();
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
          final reconfigure = enable().then<Object?>(
            (_) => null,
            onError: (Object e) => e,
          );
          await characteristic.secondEntered.future;
          if (order == 'settled') {
            characteristic.reply.complete();
            await reconfigure;
          }
          var disconnected = false;
          final disconnect = a.device(device.address).disconnect().then((_) {
            disconnected = true;
          });
          await pumpEventQueue();
          if (order == 'pending') {
            expect(disconnected, isFalse);
            characteristic.reply.complete();
          }
          final error = await reconfigure;
          await disconnect;
          expect(error, reply == 'error' ? isA<StateError>() : isNull);
          expect(characteristic.stops, 1);
          expect(characteristic.clientClaim, isFalse);
          expect(characteristic.peerClaim, isTrue);
          expect(characteristic.notifying, isTrue);
          expect(characteristic.events.hasListener, isFalse);
          expect(device.connected, isTrue);
          expect(device.disconnects, 0);
          expect(disconnected, isTrue);
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );
    }
  }
}

class ReconfiguredCharacteristic extends notify.HeldCharacteristic {
  ReconfiguredCharacteristic(this.outcome);
  final String outcome;
  final secondEntered = Completer<void>();
  final reply = Completer<void>();
  var starts = 0;
  var stops = 0;
  var clientClaim = false;
  // Models a second D-Bus client's independent native notification ownership.
  final peerClaim = true;
  @override
  Future<void> startNotify() async {
    starts++;
    if (starts == 2) {
      secondEntered.complete();
      await reply.future;
      if (outcome == 'already-exists') {
        throw BlueZAlreadyExistsException(
          DBusMethodErrorResponse('org.bluez.Error.AlreadyExists'),
        );
      }
      if (outcome == 'error') throw StateError('reconfiguration failed');
    }
    clientClaim = true;
    notifying = true;
  }

  @override
  Future<void> stopNotify() async {
    stops++;
    clientClaim = false;
    notifying = peerClaim;
  }
}
