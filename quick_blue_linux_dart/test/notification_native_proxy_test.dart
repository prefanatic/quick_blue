// Real BlueZ wrappers with a controlled D-Bus method boundary.
import 'dart:async';

import 'package:bluez/bluez.dart';
import 'package:bluez/src/bluez_object.dart';
import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';
import 'package:quick_blue_linux_dart/quick_blue_linux_dart.dart';
import 'package:quick_blue_linux_dart/src/gatt_session.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:test/test.dart';

import 'adapter_lease_test.dart' as lease;
import 'adapter_selection_test.dart' as fake;
import 'notification_disconnect_test.dart' as notify;

const iface = 'org.bluez.GattCharacteristic1';
const nativePath = '/org/bluez/hci0/dev_02_00_00_00_00_03/service0001/char0002';

class NativeBus implements DBusClient {
  String control = 'settled';
  final confirmationEntered = Completer<void>();
  final confirmationReply = Completer<void>();
  var starts = 0;
  var stops = 0;
  final calls = <String>[];
  bool clientClaim = false;
  final bool peerClaim = true;
  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) async {
    expect(destination, 'org.bluez');
    expect(path.value, nativePath);
    expect(interface, iface);
    calls.add('$name ${path.value}');
    if (name == 'StartNotify') {
      starts++;
      if (starts == 3 && control != 'settled') {
        confirmationEntered.complete();
        await confirmationReply.future;
        if (control == 'confirmation-error') {
          throw DBusMethodResponseException(
            DBusMethodErrorResponse('org.bluez.Error.Failed'),
          );
        }
      }
      if (clientClaim) {
        throw DBusMethodResponseException(
          DBusMethodErrorResponse('org.bluez.Error.AlreadyExists'),
        );
      }
      clientClaim = true;
    } else if (name == 'StopNotify') {
      stops++;
      clientClaim = false;
      if (stops == 1 && control == 'stop-error') {
        throw DBusMethodResponseException(
          DBusMethodErrorResponse('org.bluez.Error.Failed'),
        );
      }
    } else {
      throw StateError('Unexpected method $name');
    }
    return DBusMethodSuccessResponse([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BlueZObject nativeObject(NativeBus bus) =>
    BlueZObject(bus, DBusObjectPath(nativePath), {
      iface: {
        'UUID': DBusString('00002a19-0000-1000-8000-00805f9b34fb'),
        'Flags': DBusArray.string(['notify']),
        'Notifying': DBusBoolean(true),
        'Value': DBusArray.byte([0]),
      },
    });

class Device extends notify.NotificationDevice {
  Device(super.adapter, super.characteristic);
  bool resolved = true;
  @override
  bool get servicesResolved => resolved;
}

void main() {
  for (final fail in [false, true]) {
    test(
      'clear during native confirmation releases late claim: error=$fail',
      () async {
        final bus = NativeBus()
          ..control = fail ? 'confirmation-error' : 'pending';
        final adapter = fake.Adapter('02:00:00:00:00:01');
        final client = fake.Client([adapter]);
        final object = nativeObject(bus);
        final old = BlueZGattCharacteristic(client, object);
        final current = BlueZGattCharacteristic(client, object);
        final placeholder = notify.HeldCharacteristic();
        final device = Device(adapter, placeholder);
        device.gattServices
          ..clear()
          ..add(notify.NotificationService([old]));
        final session = LinuxGattSession(
          getDevice: (_) => device,
          ensureConnected: (_) async {},
          handleServiceDiscovered: (_, _, _) {},
          onServiceDiscoveryComplete: (_) {},
          handleCharacteristicValueChanged: (_, _, _, _) {},
          handleGattServicesChanged: (_) {},
          logger: Logger('native-proxy-test'),
        );
        addTearDown(() async {
          if (!bus.confirmationReply.isCompleted) {
            bus.confirmationReply.complete();
          }
          await session.stopNotificationsForClient(device.address);
          await session.clearDevice(device.address);
          await client.removed.close();
          await device.events.close();
          await placeholder.events.close();
        });
        Future<void> enable() => session.setNotifiable(
          device.address,
          '180f',
          '2a19',
          BleInputProperty.notification,
        );
        await enable();
        session.clearResolvedCharacteristics(device.address);
        device.gattServices
          ..clear()
          ..add(notify.NotificationService([current]));
        final setup = enable().then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
        await bus.confirmationEntered.future;
        await session.clearDevice(device.address);
        bus.confirmationReply.complete();
        expect(
          await setup,
          fail ? isA<BlueZFailedException>() : isA<QuickBlueException>(),
        );
        expect(bus.clientClaim, isFalse);
        expect(bus.stops, 2);
        expect(bus.peerClaim, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  }
  for (final mode in ['same-wrapper', 'fresh-wrapper', 'recreated-object']) {
    for (final control in [
      'settled',
      'pending',
      'confirmation-error',
      'stop-error',
    ]) {
      if (mode == 'same-wrapper' && control != 'settled') continue;
      test('rediscovery retains native claim: $mode $control', () async {
        final bus = NativeBus()..control = control;
        final adapter = fake.Adapter('02:00:00:00:00:01');
        final client = fake.Client([adapter]);
        final object = nativeObject(bus);
        final old = BlueZGattCharacteristic(client, object);
        final current = mode == 'same-wrapper'
            ? old
            : BlueZGattCharacteristic(
                client,
                mode == 'recreated-object' ? nativeObject(bus) : object,
              );
        final placeholder = notify.HeldCharacteristic();
        final device = Device(adapter, placeholder)..connected = false;
        device.gattServices
          ..clear()
          ..add(notify.NotificationService([old]));
        client.deviceList = [device];
        final owners = <String, String>{};
        final a = QuickBlueLinux.withClient(
          client,
          connectionLease: DbusConnectionLease.withBus(
            lease.UnlockBus(owners, ':1.1'),
          ),
        );
        final b = lease.platform([adapter], [device], null, owners, ':1.2');
        addTearDown(() async {
          if (!bus.confirmationReply.isCompleted) {
            bus.confirmationReply.complete();
          }
          await a.close();
          await b.close();
          await client.removed.close();
          await device.events.close();
          await placeholder.events.close();
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
        expect(bus.clientClaim, isTrue);
        device.resolved = false;
        device.events.add(['ServicesResolved']);
        await pumpEventQueue();
        // Real bluez getGattCharacteristics constructs fresh wrappers even when
        // the underlying BlueZObject is unchanged. Removal/re-add can also reuse
        // the D-Bus path. Both must preserve successful native setup.
        device.gattServices
          ..clear()
          ..add(notify.NotificationService([current]));
        if (mode == 'recreated-object') bus.clientClaim = false;
        device.resolved = true;
        device.events.add(['ServicesResolved']);
        await pumpEventQueue();
        await a.discoverServices(device.address);
        bool? successfulSetupClaim;
        final setup = enable().then<Object?>((_) {
          successfulSetupClaim = bus.clientClaim;
          return null;
        }, onError: (Object error) => error);
        final held = control != 'settled';
        if (held) await bus.confirmationEntered.future;
        if (!held) expect(await setup, isNull);
        final claimAfterEnable = bus.clientClaim;
        final stopsBeforeDisconnect = bus.calls
            .where((c) => c.startsWith('StopNotify '))
            .length;
        var disconnectDone = false;
        final disconnect = a.device(device.address).disconnect().then((_) {
          disconnectDone = true;
        });
        if (held) {
          await pumpEventQueue();
          expect(disconnectDone, isFalse);
          bus.confirmationReply.complete();
          expect(
            await setup,
            control == 'confirmation-error'
                ? isA<BlueZFailedException>()
                : isNull,
          );
        }
        await disconnect;
        print(
          'PROXY mode=$mode liveAfterSetup=$claimAfterEnable '
          'stopsBeforeDisconnect=$stopsBeforeDisconnect '
          'claimAfterDisconnect=${bus.clientClaim} peerClaim=${bus.peerClaim} '
          'connected=${device.connected} disconnects=${device.disconnects} '
          'calls=${bus.calls}',
        );
        expect(bus.peerClaim, isTrue);
        expect(device.connected, isTrue);
        expect(device.disconnects, 0);
        expect(bus.clientClaim, isFalse);
        expect(
          successfulSetupClaim,
          control == 'confirmation-error' ? isNull : isTrue,
          reason: 'successful setup must not retire its own native endpoint',
        );
        expect(stopsBeforeDisconnect, mode == 'same-wrapper' ? 0 : 1);
        if (mode != 'same-wrapper') {
          expect(
            bus.calls[3],
            'StartNotify $nativePath',
            reason: 'confirmation must follow retirement, before disconnect',
          );
        }
      }, timeout: const Timeout(Duration(seconds: 5)));
    }
  }
}
