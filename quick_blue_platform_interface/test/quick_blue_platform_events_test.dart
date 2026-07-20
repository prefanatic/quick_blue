import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('device streams only emit events for that device', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final device = platform.device('device-a');

    final connection = expectLater(
      device.connectionStateStream.map((event) => event.state),
      emits(BlueConnectionState.connected),
    );
    final service = expectLater(
      device.serviceDiscoveryStream.map((event) => event.uuid),
      emits('service-a'),
    );
    final value = expectLater(
      device.characteristicValueStream.map((event) => event.value),
      emits(Uint8List.fromList(<int>[1, 2, 3])),
    );

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    platform.handleServiceDiscovered('device-b', 'service-b', const []);
    platform.handleCharacteristicValueChanged(
      'device-b',
      'service-b',
      'characteristic-b',
      Uint8List.fromList(<int>[9]),
    );

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    platform.handleServiceDiscovered('device-a', 'service-a', [
      BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
    ]);
    platform.handleCharacteristicValueChanged(
      'device-a',
      'service-a',
      'characteristic-a',
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    await Future.wait(<Future<void>>[connection, service, value]);
  });

  test(
    'legacy callbacks are still called while streams receive events',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final legacyConnectionEvents = <BluetoothConnectionStateChange>[];
      final streamEvent = platform.connectionStateStream.first;

      platform.onConnectionChanged = (deviceId, state, status) {
        legacyConnectionEvents.add(
          BluetoothConnectionStateChange(
            deviceId: deviceId,
            state: state,
            status: status,
          ),
        );
      };

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.success,
      );

      expect((await streamEvent).deviceId, 'device-a');
      expect(legacyConnectionEvents, hasLength(1));
      expect(legacyConnectionEvents.single.deviceId, 'device-a');
      expect(
        legacyConnectionEvents.single.state,
        BlueConnectionState.connected,
      );
      expect(legacyConnectionEvents.single.status, BleStatus.success);
    },
  );

  test(
    'default service discovery callback maps raw ids to characteristics',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final services = <BluetoothService>[];
      final sub = platform.serviceDiscoveryStream.listen(services.add);

      platform.onServiceDiscovered?.call(
        'device-a',
        'service-a',
        const <String>['characteristic-a'],
      );
      await pumpEventQueue();

      expect(services, <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      ]);

      await sub.cancel();
    },
  );

  test('service discovery stream delivery remains asynchronous', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final services = <BluetoothService>[];
    final sub = platform.serviceDiscoveryStream.listen(services.add);

    platform.handleServiceDiscovered(
      'device-a',
      'service-a',
      <BluetoothCharacteristicInfo>[
        BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
      ],
    );

    expect(services, isEmpty);

    await pumpEventQueue();
    expect(services.map((service) => service.uuid), <String>['service-a']);

    await sub.cancel();
  });

  test('custom onServiceDiscovered callback receives callbacks', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final services = <BluetoothService>[];
    final customServices = <BluetoothService>[];
    final sub = platform.serviceDiscoveryStream.listen(services.add);

    platform.onServiceDiscovered = (deviceId, serviceId, characteristicIds) {
      customServices.add(
        BluetoothService(
          deviceId: deviceId,
          uuid: serviceId,
          characteristics: characteristicIds,
        ),
      );
    };

    platform.handleServiceDiscovered(
      'device-a',
      'service-a',
      <BluetoothCharacteristicInfo>[
        BluetoothCharacteristicInfo(uuid: 'characteristic-a'),
      ],
    );
    await pumpEventQueue();

    expect(services, hasLength(1));
    expect(customServices, hasLength(1));
    expect(customServices.single.deviceId, 'device-a');
    expect(customServices.single.uuid, 'service-a');
    expect(customServices.single.characteristics, ['characteristic-a']);

    await sub.cancel();
  });

  test('default onValueChanged emits stream events', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final characteristicValues = <BluetoothCharacteristicValue>[];
    final sub = platform.characteristicValueStream.listen(
      characteristicValues.add,
    );

    final defaultCallback = platform.onValueChanged;
    defaultCallback?.call(
      'device-a',
      'characteristic-a',
      Uint8List.fromList(<int>[1]),
    );
    await pumpEventQueue();

    expect(characteristicValues.single.serviceId, isEmpty);
    expect(characteristicValues.single.characteristicId, 'characteristic-a');
    expect(characteristicValues.single.value, Uint8List.fromList(<int>[1]));

    await sub.cancel();
  });

  test(
    'custom onValueChanged receives callbacks in addition to stream events',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final events = <BluetoothCharacteristicValue>[];
      final characteristicValues = <BluetoothCharacteristicValue>[];
      final sub = platform.characteristicValueStream.listen(
        characteristicValues.add,
      );

      platform.onValueChanged = (deviceId, characteristicId, value) {
        events.add(
          BluetoothCharacteristicValue(
            deviceId: deviceId,
            serviceId: 'custom-service',
            characteristicId: characteristicId,
            value: value,
          ),
        );
      };

      platform.handleCharacteristicValueChanged(
        'device-a',
        'service-a',
        'characteristic-a',
        Uint8List.fromList(<int>[2]),
      );
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.deviceId, 'device-a');
      expect(events.single.serviceId, 'custom-service');
      expect(events.single.characteristicId, 'characteristic-a');
      expect(events.single.value, Uint8List.fromList(<int>[2]));
      expect(characteristicValues, hasLength(1));
      expect(characteristicValues.single.serviceId, 'service-a');
      expect(characteristicValues.single.characteristicId, 'characteristic-a');
      expect(characteristicValues.single.value, Uint8List.fromList(<int>[2]));

      await sub.cancel();
    },
  );
}
