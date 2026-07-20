import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BluetoothDevice.discoverGatt exposes discovered services', () async {
    final discoveredServices = <BluetoothService>[
      BluetoothService(
        deviceId: 'device-a',
        uuid: 'service-a',
        characteristics: const <String>['characteristic-a'],
      ),
    ];
    final platform = FakeQuickBluePlatform(
      discoveredServices: discoveredServices,
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(gatt.deviceId, 'device-a');
    expect(gatt.services, discoveredServices);
    expect(platform.calls, <String>['discoverServices device-a']);
  });

  test(
    'BluetoothGatt.characteristic resolves a discovered characteristic',
    () async {
      final platform = FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[1, 2, 3]),
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();
      final value = await gatt.characteristic('characteristic-a').read();

      expect(value, Uint8List.fromList(<int>[1, 2, 3]));
      expect(platform.calls, <String>[
        'discoverServices device-a',
        'readValue device-a service-a characteristic-a',
      ]);
    },
  );

  test('BluetoothGatt.characteristic matches short and full UUIDs', () async {
    final platform = FakeQuickBluePlatform(
      readValueResult: Uint8List.fromList(<int>[4, 5, 6]),
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: '0000180d-0000-1000-8000-00805f9b34fb',
          characteristics: const <String>[
            '00002a37-0000-1000-8000-00805f9b34fb',
          ],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();
    final value = await gatt.characteristic('2a37', service: '180d').read();

    expect(value, Uint8List.fromList(<int>[4, 5, 6]));
    expect(platform.calls, <String>[
      'discoverServices device-a',
      'readValue device-a '
          '0000180d-0000-1000-8000-00805f9b34fb '
          '00002a37-0000-1000-8000-00805f9b34fb',
    ]);
  });

  test('BluetoothGatt.characteristic exposes characteristic info', () async {
    final platform = FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
          characteristicDetails: <BluetoothCharacteristicInfo>[
            BluetoothCharacteristicInfo(
              uuid: 'characteristic-a',
              canRead: true,
            ),
          ],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(gatt.characteristicInfo('characteristic-a').canRead, isTrue);
  });

  test(
    'BluetoothGatt.hasCharacteristic returns true when discovered',
    () async {
      final platform = FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(gatt.hasCharacteristic('characteristic-a'), isTrue);
    },
  );

  test(
    'BluetoothGatt.hasCharacteristic returns false when not found',
    () async {
      final platform = FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(gatt.hasCharacteristic('missing-characteristic'), isFalse);
    },
  );

  test('BluetoothGatt.hasCharacteristic applies service filters', () async {
    final platform = FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-b',
          characteristics: const <String>['characteristic-b'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(
      gatt.hasCharacteristic('characteristic-a', service: 'service-a'),
      isTrue,
    );
    expect(
      gatt.hasCharacteristic('characteristic-a', service: 'service-b'),
      isFalse,
    );
  });

  test(
    'BluetoothGatt.hasCharacteristic matches short and full UUIDs',
    () async {
      final platform = FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            characteristics: const <String>[
              '00002a37-0000-1000-8000-00805f9b34fb',
            ],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(gatt.hasCharacteristic('2a37', service: '180d'), isTrue);
    },
  );

  test('BluetoothGatt.hasCharacteristic returns true when ambiguous', () async {
    final platform = FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-b',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(gatt.hasCharacteristic('characteristic-a'), isTrue);
  });

  test('BluetoothGatt.characteristic throws with service filter and missing '
      'characteristic context', () async {
    final platform = FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-b',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();
    expect(
      () => gatt.characteristic('characteristic-a', service: 'service-a'),
      throwsA(
        isA<QuickBlueException>()
            .having((error) => error.code, 'code', QuickBlueErrorCode.notFound)
            .having(
              (error) => error.message,
              'message',
              contains('under service service-a'),
            ),
      ),
    );
  });

  test('BluetoothGatt.characteristic throws when not found', () async {
    final platform = FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
    );
    addTearDown(platform.dispose);

    final gatt = await platform.device('device-a').discoverGatt();

    expect(
      () => gatt.characteristic('missing-characteristic'),
      throwsA(
        isA<QuickBlueException>()
            .having((error) => error.code, 'code', QuickBlueErrorCode.notFound)
            .having(
              (error) => error.message,
              'message',
              contains('Characteristic missing-characteristic not found'),
            ),
      ),
    );
  });

  test(
    'BluetoothGatt.characteristic throws when characteristic is ambiguous',
    () async {
      final platform = FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-b',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();

      expect(
        () => gatt.characteristic('characteristic-a'),
        throwsA(
          isA<QuickBlueException>()
              .having(
                (error) => error.code,
                'code',
                QuickBlueErrorCode.ambiguous,
              )
              .having(
                (error) => error.message,
                'message',
                allOf(contains('multiple services'), contains('service-a')),
              ),
        ),
      );
    },
  );

  test(
    'BluetoothGatt.characteristic resolves ambiguous characteristic by service',
    () async {
      final platform = FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[7, 8, 9]),
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-b',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final gatt = await platform.device('device-a').discoverGatt();
      final value = await gatt
          .characteristic('characteristic-a', service: 'service-b')
          .read();

      expect(value, Uint8List.fromList(<int>[7, 8, 9]));
      expect(platform.calls, <String>[
        'discoverServices device-a',
        'readValue device-a service-b characteristic-a',
      ]);
    },
  );

  test('BluetoothDevice.discoverServices propagates platform errors', () async {
    final error = StateError('discover failed');
    final platform = FakeQuickBluePlatform(discoverServicesError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform.device('device-a').discoverServices(),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>['discoverServices device-a']);
  });

  test(
    'BluetoothDevice.discoverServices coalesces concurrent device requests',
    () async {
      final discovery = Completer<void>();
      final platform = FakeQuickBluePlatform(
        discoveredServices: <BluetoothService>[
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-a',
            characteristics: const <String>['characteristic-a'],
          ),
        ],
        discoverServicesCompletion: discovery,
      );
      addTearDown(platform.dispose);

      final device = platform.device('device-a');
      final firstDiscovery = device.discoverServices();
      final secondDiscovery = device.discoverServices();
      await pumpEventQueue();

      expect(platform.calls, <String>['discoverServices device-a']);

      discovery.complete();
      final results = await Future.wait(<Future<List<BluetoothService>>>[
        firstDiscovery,
        secondDiscovery,
      ]);

      expect(results[0].map((service) => service.uuid), <String>['service-a']);
      expect(results[1].map((service) => service.uuid), <String>['service-a']);
      expect(results[0], same(results[1]));
    },
  );

  test('BluetoothDevice.discoverServices can retry after failure', () async {
    final error = StateError('discover failed');
    final platform = FakeQuickBluePlatform(
      discoveredServices: <BluetoothService>[
        BluetoothService(
          deviceId: 'device-a',
          uuid: 'service-a',
          characteristics: const <String>['characteristic-a'],
        ),
      ],
      discoverServicesError: error,
    );
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    await expectLater(device.discoverServices(), throwsA(same(error)));

    platform.discoverServicesError = null;
    final services = await device.discoverServices();

    expect(services.map((service) => service.uuid), <String>['service-a']);
    expect(platform.calls, <String>[
      'discoverServices device-a',
      'discoverServices device-a',
    ]);
  });

  test('BluetoothDevice.setNotifiable propagates platform errors', () async {
    final error = StateError('notify failed');
    final platform = FakeQuickBluePlatform(setNotifiableError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform
          .device('device-a')
          .setNotifiable(
            'service-a',
            'characteristic-a',
            BleInputProperty.notification,
          ),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>[
      'setNotifiable device-a service-a characteristic-a notification',
    ]);
  });

  test(
    'BluetoothDevice.readValue completes with the matching value event',
    () async {
      final platform = FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[4, 5, 6]),
      );
      addTearDown(platform.dispose);

      final device = platform.device('device-a');

      await expectLater(
        device.readValue('service-a', 'characteristic-a'),
        completion(Uint8List.fromList(<int>[4, 5, 6])),
      );
    },
  );

  test(
    'BluetoothCharacteristic.valueStream matches short and full UUIDs',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('180d', '2a37');

      final value = expectLater(
        characteristic.valueStream,
        emits(Uint8List.fromList(<int>[1, 2, 3])),
      );

      platform.handleCharacteristicValueChanged(
        'device-a',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '00002a37-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[1, 2, 3]),
      );

      await value;
    },
  );

  test(
    'BluetoothCharacteristic.valueStream receives direct and legacy values',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);

      final device = platform.device('device-a');
      final characteristic = device.characteristic('180d', '2a37');
      final otherCharacteristic = device.characteristic('180d', '2a38');
      final values = <Uint8List>[];
      final otherValues = <Uint8List>[];
      final subscription = characteristic.valueStream.listen(values.add);
      final otherSubscription = otherCharacteristic.valueStream.listen(
        otherValues.add,
      );

      platform.handleCharacteristicValueChanged(
        'device-a',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '00002a37-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      platform.onValueChanged?.call(
        'device-a',
        '00002a37-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[4, 5, 6]),
      );
      platform.handleCharacteristicValueChanged(
        'device-a',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '00002a38-0000-1000-8000-00805f9b34fb',
        Uint8List.fromList(<int>[7, 8, 9]),
      );
      await pumpEventQueue();

      expect(values.map((value) => value.toList()), [
        <int>[1, 2, 3],
        <int>[4, 5, 6],
      ]);
      expect(otherValues.map((value) => value.toList()), [
        <int>[7, 8, 9],
      ]);

      await subscription.cancel();
      await otherSubscription.cancel();
    },
  );

  test('BluetoothCharacteristic.setNotifiable delegates to platform', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final characteristic = platform
        .device('device-a')
        .characteristic('service-a', 'characteristic-a');

    await characteristic.setNotifiable(BleInputProperty.notification);
    await characteristic.setNotifiable(BleInputProperty.disabled);

    expect(platform.calls, <String>[
      'setNotifiable device-a service-a characteristic-a notification',
      'setNotifiable device-a service-a characteristic-a disabled',
    ]);
  });

  test(
    'BluetoothCharacteristic.setNotifiable propagates platform errors',
    () async {
      final error = StateError('notify failed');
      final platform = FakeQuickBluePlatform(setNotifiableError: error);
      addTearDown(platform.dispose);

      final characteristic = platform
          .device('device-a')
          .characteristic('service-a', 'characteristic-a');

      await expectLater(
        characteristic.setNotifiable(BleInputProperty.notification),
        throwsA(same(error)),
      );
      expect(platform.calls, <String>[
        'setNotifiable device-a service-a characteristic-a notification',
      ]);
    },
  );

  test('BluetoothDevice.readValue propagates platform errors', () async {
    final error = StateError('read failed');
    final platform = FakeQuickBluePlatform(readValueError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform.device('device-a').readValue('service-a', 'characteristic-a'),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>[
      'readValue device-a service-a characteristic-a',
    ]);
  });

  test(
    'BluetoothDevice.readValue pairs and retries a security failure',
    () async {
      const securityError = QuickBlueSecurityException(
        reason: QuickBlueSecurityErrorReason.insufficientAuthentication,
        nativeDomain: 'test.security',
        nativeCode: 5,
        operation: 'readValue',
        deviceId: 'device-a',
        serviceId: 'service-a',
        characteristicId: 'characteristic-a',
        message: 'Authentication required',
      );
      final platform = FakeQuickBluePlatform(
        readValueResult: Uint8List.fromList(<int>[7, 8]),
        readValueError: securityError,
        clearSecurityErrorsOnPair: true,
      );
      addTearDown(platform.dispose);

      final value = await platform
          .device('device-a')
          .readValue('service-a', 'characteristic-a');

      expect(value, Uint8List.fromList(<int>[7, 8]));
      expect(platform.calls, <String>[
        'readValue device-a service-a characteristic-a',
        'bondState device-a',
        'pair device-a',
        'readValue device-a service-a characteristic-a',
      ]);
    },
  );

  test('security recovery stops after one failed retry', () async {
    const securityError = QuickBlueSecurityException(
      reason: QuickBlueSecurityErrorReason.insufficientAuthentication,
      nativeDomain: 'test.security',
      nativeCode: 5,
      operation: 'readValue',
      deviceId: 'device-a',
      message: 'Authentication required',
    );
    final platform = FakeQuickBluePlatform(readValueError: securityError);
    addTearDown(platform.dispose);

    await expectLater(
      platform.device('device-a').readValue('service-a', 'characteristic-a'),
      throwsA(
        isA<QuickBlueSecurityException>().having(
          (error) => error.recoveryResult,
          'recoveryResult',
          QuickBlueSecurityRecoveryResult.userActionRequired,
        ),
      ),
    );

    expect(platform.calls, <String>[
      'readValue device-a service-a characteristic-a',
      'bondState device-a',
      'pair device-a',
      'readValue device-a service-a characteristic-a',
    ]);
  });

  test(
    'bonded security failures require user action without retrying',
    () async {
      const securityError = QuickBlueSecurityException(
        reason: QuickBlueSecurityErrorReason.peerRemovedPairingInformation,
        nativeDomain: 'test.security',
        nativeCode: 14,
        operation: 'readValue',
        deviceId: 'device-a',
        message: 'Peer removed pairing information',
      );
      final platform = FakeQuickBluePlatform(
        readValueError: securityError,
        currentBondState: BluetoothBondState.bonded,
      );
      addTearDown(platform.dispose);

      await expectLater(
        platform.device('device-a').readValue('service-a', 'characteristic-a'),
        throwsA(
          isA<QuickBlueSecurityException>().having(
            (error) => error.recoveryResult,
            'recoveryResult',
            QuickBlueSecurityRecoveryResult.userActionRequired,
          ),
        ),
      );

      expect(platform.calls, <String>[
        'readValue device-a service-a characteristic-a',
        'bondState device-a',
      ]);
    },
  );

  test('BluetoothDevice.writeValue propagates platform errors', () async {
    final error = StateError('write failed');
    final platform = FakeQuickBluePlatform(writeValueError: error);
    addTearDown(platform.dispose);

    await expectLater(
      platform
          .device('device-a')
          .writeValue(
            'service-a',
            'characteristic-a',
            Uint8List.fromList(<int>[1, 2, 3]),
            BleOutputProperty.withResponse,
          ),
      throwsA(same(error)),
    );

    expect(platform.calls, <String>[
      'writeValue device-a service-a characteristic-a withResponse [1, 2, 3]',
    ]);
  });
}
