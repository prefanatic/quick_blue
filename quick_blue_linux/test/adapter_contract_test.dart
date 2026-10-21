import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/adapter_contract_bluez.dart';

const deadline = Duration(seconds: 2);
Future<T> bounded<T>(Future<T> future) => future.timeout(deadline);

void main() {
  late AdapterFixture f;
  final subscriptions = <StreamSubscription<Uint8List>>[];
  setUp(() => f = AdapterFixture());
  tearDown(() async {
    for (final subscription in subscriptions) {
      await bounded(subscription.cancel());
    }
    subscriptions.clear();
    await bounded(f.close());
  });

  StreamSubscription<Uint8List> watch(
    String device,
    String service,
    List<List<int>> values, {
    String characteristic = '2A19',
  }) {
    final subscription = f.platform
        .characteristicValueStreamFor(device, service, characteristic)
        .listen((value) => values.add(value.toList()));
    subscriptions.add(subscription);
    return subscription;
  }

  Future<void> connect() => f.platform.connect(f.a.address);
  Future<void> notify([
    BleInputProperty mode = BleInputProperty.notification,
  ]) => f.platform.setNotifiable(f.a.address, '180F', '2A19', mode);
  Future<void> flush() async {
    // Yield through an awaited injected event, not a timer or hardware call.
    // Multi-event ordering assertions additionally await their matching event.
    final barrier = f.platform
        .characteristicValueStreamFor(f.a.address, '180f', '2a00')
        .first;
    f.platform.handleCharacteristicValueChanged(
      f.a.address,
      '180f',
      '2a00',
      Uint8List.fromList([255]),
    );
    await bounded(barrier);
  }

  test(
    'R1 notification before direct read never replaces direct result',
    () async {
      await connect();
      final values = <List<int>>[];
      watch(f.a.address, '180F', values);
      await notify();
      await flush();
      expect(values, [
        [0],
      ]); // BlueZ cached setup value is explicitly accounted for.
      f.battery.pendingRead = Completer<List<int>>();
      final read = f.platform.readCharacteristicValue(
        f.a.address,
        '180f',
        '2a19',
      );
      await bounded(f.battery.readEntered.future);
      final event = f.platform
          .characteristicValueStreamFor(f.a.address, '180f', '2a19')
          .first;
      f.battery.emit([9]);
      expect(await bounded(event), [9]);
      f.battery.pendingRead!.complete([1, 2]);
      expect(await bounded(read), [1, 2]);
      await flush();
      expect(values, [
        [0],
        [9],
        [1, 2],
      ]);
    },
  );

  test(
    'R2 duplicate characteristic UUIDs retain device/service identity and aliases',
    () async {
      await connect();
      await f.platform.connect(f.b.address);
      final a = <List<int>>[], info = <List<int>>[], b = <List<int>>[];
      watch(f.a.address, uuid('180f').toUpperCase(), a);
      watch(f.a.address, '180A', info);
      watch(f.b.address, '180f', b);
      await f.platform.readCharacteristicValue(f.a.address, '180F', '2A19');
      await f.platform.writeValue(
        f.a.address,
        '180A',
        uuid('2a19'),
        Uint8List.fromList([4]),
        BleOutputProperty.withoutResponse,
      );
      await f.platform.setNotifiable(
        f.a.address,
        '180A',
        '2A19',
        BleInputProperty.notification,
      );
      final event = f.platform.characteristicValueStream.first;
      f.info.emit([9]);
      final update = await bounded(event);
      expect(update.deviceId, f.a.address);
      expect(update.serviceId, uuid('180a'));
      expect(update.characteristicId, uuid('2a19'));
      f.platform.handleCharacteristicValueChanged(
        f.b.address,
        '180f',
        '2a19',
        Uint8List.fromList([7]),
      );
      f.platform.handleCharacteristicValueChanged(
        f.a.address,
        '180f',
        '2a18',
        Uint8List.fromList([8]),
      );
      await flush();
      expect(a, [
        [1, 2],
      ]);
      expect(info, [
        [0],
        [9],
      ]);
      expect(b, [
        [7],
      ]);
      expect(f.battery.reads, 1);
      expect(f.info.reads, 0);
      expect(f.info.writes.single.$1, [4]);
      expect(f.info.writes.single.$2, BlueZGattCharacteristicWriteType.command);
      expect(f.battery.writes, isEmpty);
      expect(f.info.starts, 1);
      expect(f.battery.starts, 0);
    },
  );

  for (final operation in ['readValue', 'writeValue', 'setNotifiable']) {
    Future<void> invoke() async {
      switch (operation) {
        case 'readValue':
          await f.platform.readCharacteristicValue(f.a.address, '180F', '2A19');
        case 'writeValue':
          await f.platform.writeValue(
            f.a.address,
            '180F',
            '2A19',
            Uint8List.fromList([4]),
            BleOutputProperty.withResponse,
          );
        case 'setNotifiable':
          await notify();
      }
    }

    test('R3 $operation preserves typed authorization context', () async {
      await connect();
      f.battery.error = BlueZNotAuthorizedException(
        DBusMethodErrorResponse('org.bluez.Error.NotAuthorized', [
          DBusString('denied'),
        ]),
      );
      await expectLater(
        invoke(),
        throwsA(
          isA<QuickBlueSecurityException>()
              .having(
                (e) => e.reason,
                'reason',
                QuickBlueSecurityErrorReason.insufficientAuthorization,
              )
              .having(
                (e) => e.nativeDomain,
                'domain',
                'org.bluez.Error.NotAuthorized',
              )
              .having((e) => e.nativeCode, 'code', isNull)
              .having((e) => e.operation, 'operation', operation)
              .having((e) => e.deviceId, 'device', f.a.address)
              .having((e) => e.serviceId, 'service', '180F')
              .having((e) => e.characteristicId, 'characteristic', '2A19'),
        ),
      );
      f.battery.error = null;
    });
    test(
      'R3 $operation leaves non-security and arbitrary failures unchanged',
      () async {
        await connect();
        for (final error in [
          BlueZFailedException(
            DBusMethodErrorResponse('org.bluez.Error.Failed'),
          ),
          StateError('malformed dependency failure'),
        ]) {
          f.battery.error = error;
          await expectLater(invoke(), throwsA(same(error)));
        }
        f.battery.error = null;
      },
    );
  }

  test(
    'R4 matching claims share setup; conflict rejected; final cancellation stops',
    () async {
      await connect();
      final firstValue = Completer<void>();
      final first = f.platform
          .characteristicNotifications(f.a.address, '180f', '2a19')
          .listen((_) {
            if (!firstValue.isCompleted) firstValue.complete();
          });
      subscriptions.add(first);
      await bounded(firstValue.future);
      final second = f.platform
          .characteristicNotifications(f.a.address, '180F', '2A19')
          .listen((_) {});
      subscriptions.add(second);
      final conflictError = Completer<Object>();
      final conflict = f.platform
          .characteristicNotifications(
            f.a.address,
            '180f',
            '2a19',
            bleInputProperty: BleInputProperty.indication,
          )
          .listen((_) {}, onError: conflictError.complete);
      subscriptions.add(conflict);
      expect(
        await bounded(conflictError.future),
        isA<QuickBlueException>().having(
          (e) => e.code,
          'code',
          QuickBlueErrorCode.invalidState,
        ),
      );
      expect(f.battery.starts, 1);
      await first.cancel();
      expect(f.battery.stops, 0);
      await second.cancel();
      expect(f.battery.stops, 1);
      expect(f.battery.properties.hasListener, isFalse);
    },
  );

  test('R4 failed setup installs no property watcher', () async {
    await connect();
    f.battery.error = BlueZNotAuthorizedException(
      DBusMethodErrorResponse('org.bluez.Error.NotAuthorized'),
    );
    await expectLater(notify(), throwsA(isA<QuickBlueSecurityException>()));
    expect(f.battery.properties.hasListener, isFalse);
    expect(f.battery.stops, 0);
    f.battery.error = null;
  });

  test('R4 disconnect cleans watches even when native stop fails', () async {
    await connect();
    await notify();
    f.battery.error = BlueZFailedException(
      DBusMethodErrorResponse('org.bluez.Error.Failed'),
    );
    await f.platform.disconnect(f.a.address);
    expect(f.battery.stops, 1);
    expect(f.battery.properties.hasListener, isFalse);
    expect(f.a.properties.hasListener, isFalse);
  });

  test(
    'R4 pending setup cancellation waits then releases exactly once',
    () async {
      await connect();
      f.battery.pendingStart = Completer<void>();
      final subscription = f.platform
          .characteristicNotifications(f.a.address, '180f', '2a19')
          .listen((_) {});
      subscriptions.add(subscription);
      await bounded(f.battery.startEntered.future);
      final cancellation = subscription.cancel();
      f.battery.pendingStart!.complete();
      await bounded(cancellation);
      expect(f.battery.starts, 1);
      expect(f.battery.stops, 1);
      expect(f.battery.properties.hasListener, isFalse);
    },
  );

  test(
    'R4 pending setup failure cancellation releases no unacquired claim',
    () async {
      await connect();
      f.battery.pendingStart = Completer<void>();
      final subscription = f.platform
          .characteristicNotifications(f.a.address, '180f', '2a19')
          .listen((_) {}, onError: (Object _) {});
      subscriptions.add(subscription);
      await bounded(f.battery.startEntered.future);
      final cancellation = subscription.cancel();
      f.battery.pendingStart!.completeError(
        BlueZFailedException(DBusMethodErrorResponse('org.bluez.Error.Failed')),
      );
      await bounded(cancellation);
      expect(f.battery.stops, 0);
      expect(f.battery.properties.hasListener, isFalse);
    },
  );

  test(
    'R4 explicit disable failure retains watcher until disconnect cleanup',
    () async {
      await connect();
      await notify();
      f.battery.error = BlueZNotAuthorizedException(
        DBusMethodErrorResponse('org.bluez.Error.NotAuthorized'),
      );
      await expectLater(
        notify(BleInputProperty.disabled),
        throwsA(isA<QuickBlueSecurityException>()),
      );
      expect(f.battery.properties.hasListener, isTrue);
      f.battery.error = null;
      await f.platform.disconnect(f.a.address);
      expect(f.battery.stops, 2);
      expect(f.battery.properties.hasListener, isFalse);
    },
  );

  test(
    'R5 complete capabilities, bonding/filter forwarding and typed unsupported MTU',
    () async {
      final c = await f.platform.capabilities();
      expect(c.bonding, BluetoothBondingCapability.queryAndPair);
      expect(c.mtu, BluetoothMtuCapability.unsupported);
      expect(
        c.gattServiceChanges,
        BluetoothGattServiceChangeCapability.databaseOnly,
      );
      expect(
        c.connectedDeviceLookup,
        BluetoothConnectedDeviceLookupCapability.unrestricted,
      );
      expect(c.supportsL2capSockets, isTrue);
      expect(c.supportsCompanionAssociation, isFalse);
      expect(c.supportsAppleAccessorySetup, isFalse);
      expect(
        await f.platform.bondState(f.a.address),
        BluetoothBondState.notBonded,
      );
      await f.platform.pair(f.a.address);
      await f.platform.pair(f.a.address);
      expect(f.a.pairs, 1);
      expect(
        await f.platform.bondState(f.a.address),
        BluetoothBondState.bonded,
      );
      final devices = await f.platform.connectedDevices(serviceUuids: ['180A']);
      expect(devices.map((d) => d.id), [f.a.address]);
      await expectLater(
        f.platform.requestMtu(f.a.address, 247),
        throwsA(
          isA<QuickBlueException>()
              .having((e) => e.code, 'code', QuickBlueErrorCode.unsupported)
              .having((e) => e.operation, 'operation', 'requestMtu')
              .having((e) => e.details, 'requested MTU', 247),
        ),
      );
      await expectLater(
        f.platform.getCompanionAssociations(),
        throwsA(
          isA<QuickBlueException>()
              .having((e) => e.code, 'code', QuickBlueErrorCode.unsupported)
              .having(
                (e) => e.operation,
                'operation',
                'getCompanionAssociations',
              ),
        ),
      );
    },
  );

  test(
    'R6 empty-service inherited routing is not service-less BlueZ lookup',
    () async {
      await connect();
      final battery = <List<int>>[],
          info = <List<int>>[],
          wrong = <List<int>>[];
      watch(f.a.address, '180f', battery);
      watch(f.a.address, '180a', info);
      watch(f.b.address, '180f', wrong);
      final legacy = <List<int>>[];
      f.platform.onValueChanged = (_, _, bytes) => legacy.add(bytes.toList());
      final secondValue = f.platform
          .characteristicValueStreamFor(f.a.address, '180f', '2a19')
          .firstWhere((bytes) => bytes.length == 2);
      f.platform.handleCharacteristicValueChanged(
        f.a.address,
        '',
        '2A19',
        Uint8List.fromList([9]),
      );
      f.platform.handleCharacteristicValueChanged(
        f.a.address,
        '180f',
        '2a19',
        Uint8List.fromList([1, 2]),
      );
      await bounded(secondValue);
      expect(battery, [
        [9],
        [1, 2],
      ]);
      expect(info, [
        [9],
      ]);
      expect(wrong, isEmpty);
      expect(legacy, [
        [9],
        [1, 2],
      ]);
      await expectLater(
        f.platform.readCharacteristicValue(f.a.address, '', '2a19'),
        throwsA(isA<ArgumentError>()),
      );
      expect(f.battery.reads, 0);
    },
  );

  test(
    'R7 lazy initialization is coalesced and disconnect releases lease/watchers',
    () async {
      expect(f.client.connects, 0);
      await Future.wait([
        f.platform.isBluetoothAvailable(),
        f.platform.isBluetoothAvailable(),
      ]);
      expect(f.client.connects, 1);
      await connect();
      await notify();
      expect(f.a.properties.hasListener, isTrue);
      expect(f.battery.properties.hasListener, isTrue);
      final values = <List<int>>[];
      watch(f.a.address, '180f', values);
      final event = f.platform
          .characteristicValueStreamFor(f.a.address, '180f', '2a19')
          .first;
      f.battery.emit([9]);
      expect(await bounded(event), [9]);
      await flush();
      expect(values, [
        [9],
      ]);
      await f.platform.disconnect(f.a.address);
      expect(f.client.connects, 1);
      expect(f.lease.attaches, [f.a.address]);
      expect(f.lease.detaches, [f.a.address]);
      expect(f.a.disconnects, 1);
      expect(f.a.properties.hasListener, isFalse);
      expect(f.battery.properties.hasListener, isFalse);
    },
  );
}
