import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

FakeQuickBluePlatform fixture({List<Completer<void>> writes = const []}) {
  final platform = FakeQuickBluePlatform(
    readValueResult: Uint8List.fromList([7]),
    writeValueCompletions: writes,
    discoveredServices: [
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const ['characteristic-a'],
      ),
    ],
  );
  addTearDown(platform.dispose);
  return platform;
}

Matcher invalidState(String operation) => isA<QuickBlueException>()
    .having((e) => e.code, 'code', QuickBlueErrorCode.invalidState)
    .having((e) => e.operation, 'operation', operation)
    .having((e) => e.deviceId, 'device', 'device-a')
    .having((e) => e.serviceId, 'service', 'service-a')
    .having((e) => e.characteristicId, 'characteristic', 'characteristic-a');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final operations = <String, Future<void> Function(BluetoothCharacteristic)>{
    'read': (c) async {
      await c.read();
    },
    'write-response': (c) =>
        c.write(Uint8List.fromList([1]), BleOutputProperty.withResponse),
    'write-no-response': (c) =>
        c.write(Uint8List.fromList([1]), BleOutputProperty.withoutResponse),
    'notify': (c) => c.setNotifiable(BleInputProperty.notification),
    'indicate': (c) => c.setNotifiable(BleInputProperty.indication),
    'disable': (c) => c.setNotifiable(BleInputProperty.disabled),
  };
  for (final entry in operations.entries) {
    test(
      'invalidated bound handle rejects ${entry.key} before submission',
      () async {
        final platform = fixture();
        final gatt = await platform.device('device-a').discoverGatt();
        final handle = gatt.boundCharacteristic('characteristic-a');
        platform.handleGattServicesChanged('device-a');
        final before = List<String>.of(platform.calls);
        final operation = entry.key.startsWith('write')
            ? 'write'
            : entry.key == 'read'
            ? 'read'
            : 'setNotifiable';
        await expectLater(
          () => entry.value(handle),
          throwsA(invalidState(operation)),
        );
        expect(platform.calls, before);
      },
    );
  }

  test('notifications checks at listen, before native setup', () async {
    final platform = fixture();
    final gatt = await platform.device('device-a').discoverGatt();
    final handle = gatt.boundCharacteristic('characteristic-a');
    final retained = handle.notifications();
    platform.handleGattServicesChanged('device-a');
    final before = List<String>.of(platform.calls);
    await expectLater(retained, emitsError(invalidState('notifications')));
    expect(platform.calls, before);
  });

  test(
    'freshly rediscovered bound handles submit read write and notify',
    () async {
      final platform = fixture();
      final device = platform.device('device-a');
      final old = await device.discoverGatt();
      platform.handleGattServicesChanged('device-a');
      final fresh = await device.discoverGatt();
      expect(old.isValid, isFalse);
      expect(fresh.isValid, isTrue);
      final handle = fresh.boundCharacteristic(
        'characteristic-a',
        service: 'service-a',
      );
      platform.calls.clear();
      expect(await handle.read(), [7]);
      await handle.write(
        Uint8List.fromList([1]),
        BleOutputProperty.withResponse,
      );
      await handle.setNotifiable(BleInputProperty.indication);
      final subscription = handle.notifications().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(platform.calls.where((c) => c.startsWith('readValue')).length, 1);
      expect(platform.calls.where((c) => c.startsWith('writeValue')).length, 1);
      expect(
        platform.calls.where((c) => c.startsWith('setNotifiable')).length,
        3,
      );
    },
  );

  test('direct-ID and default resolved handles remain unbound', () async {
    final platform = fixture();
    final device = platform.device('device-a');
    final gatt = await device.discoverGatt();
    final defaultHandle = gatt.characteristic('characteristic-a');
    final direct = device.characteristic('service-a', 'characteristic-a');
    platform.handleGattServicesChanged('device-a');
    platform.calls.clear();
    await defaultHandle.read();
    await direct.read();
    await device.readValue('service-a', 'characteristic-a');
    await device.writeValue(
      'service-a',
      'characteristic-a',
      Uint8List(0),
      BleOutputProperty.withResponse,
    );
    await device.setNotifiable(
      'service-a',
      'characteristic-a',
      BleInputProperty.notification,
    );
    expect(platform.calls.length, 5);
  });

  test(
    'already-submitted write completes normally after invalidation',
    () async {
      final gate = Completer<void>();
      final platform = fixture(writes: [gate]);
      final gatt = await platform.device('device-a').discoverGatt();
      final handle = gatt.boundCharacteristic('characteristic-a');
      final pending = handle.write(
        Uint8List.fromList([1]),
        BleOutputProperty.withResponse,
      );
      expect(platform.calls.where((c) => c.startsWith('writeValue')).length, 1);
      platform.handleGattServicesChanged('device-a');
      gate.complete();
      await pending;
      expect(platform.calls.where((c) => c.startsWith('writeValue')).length, 1);
    },
  );

  test('chunked write stops before the next invalidated submission', () async {
    final gate = Completer<void>();
    final platform = fixture(writes: [gate]);
    final gatt = await platform.device('device-a').discoverGatt();
    final handle = gatt.boundCharacteristic('characteristic-a');
    final pending = handle.writeInChunks(
      Uint8List.fromList([1, 2]),
      BleOutputProperty.withResponse,
      chunkSize: 1,
    );
    final assertion = expectLater(pending, throwsA(invalidState('write')));
    expect(platform.calls.where((c) => c.startsWith('writeValue')).length, 1);
    platform.handleGattServicesChanged('device-a');
    gate.complete();
    await assertion;
    expect(platform.calls.where((c) => c.startsWith('writeValue')).length, 1);
  });

  test('disconnect reconnect preserves current snapshot policy', () async {
    final platform = fixture();
    final device = platform.device('device-a');
    final gatt = await device.discoverGatt();
    final handle = gatt.boundCharacteristic('characteristic-a');
    await device.disconnect();
    expect(gatt.isValid, isTrue);
    await device.connect();
    expect(gatt.isValid, isTrue);
    expect(await handle.read(), [7]);
    platform.handleGattServicesChanged('device-a');
    expect(gatt.isValid, isFalse);
    await expectLater(handle.read(), throwsA(invalidState('read')));
  });
}
