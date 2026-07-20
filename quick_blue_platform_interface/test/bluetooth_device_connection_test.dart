import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BluetoothDevice delegates commands to platform', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final value = Uint8List.fromList(<int>[1, 2, 3]);

    await device.connect();
    await device.bondState();
    await device.pair();
    await device.discoverServices();
    await device.setNotifiable(
      'service-a',
      'characteristic-a',
      BleInputProperty.notification,
    );
    await device.writeValue(
      'service-a',
      'characteristic-a',
      value,
      BleOutputProperty.withResponse,
    );
    await device.requestMtu(128);
    await device.openL2cap(25);
    await device.disconnect();

    expect(platform.calls, <String>[
      'connect device-a',
      'bondState device-a',
      'pair device-a',
      'discoverServices device-a',
      'setNotifiable device-a service-a characteristic-a notification',
      'writeValue device-a service-a characteristic-a withResponse [1, 2, 3]',
      'requestMtu device-a 128',
      'openL2cap device-a 25',
      'disconnect device-a',
    ]);
  });

  test('BluetoothDevice.bondStateStream filters device transitions', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final events = <BluetoothBondStateChange>[];
    final subscription = platform
        .device('device-a')
        .bondStateStream
        .listen(events.add);

    platform
      ..addBondStateChange(
        'device-b',
        BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      )
      ..addBondStateChange(
        'device-a',
        BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      );
    await pumpEventQueue();

    expect(events, const <BluetoothBondStateChange>[
      BluetoothBondStateChange(
        deviceId: 'device-a',
        state: BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      ),
    ]);
    await subscription.cancel();
  });

  test('BluetoothDevice.waitForBondState returns an existing state', () async {
    final platform = FakeQuickBluePlatform(
      currentBondState: BluetoothBondState.bonded,
    );
    addTearDown(platform.dispose);

    final state = await platform
        .device('device-a')
        .waitForBondState(BluetoothBondState.bonded);

    expect(state, BluetoothBondState.bonded);
    expect(platform.calls, <String>['bondState device-a']);
  });

  test('BluetoothDevice.waitForBondState awaits a matching event', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final waiting = platform
        .device('device-a')
        .waitForBondState(BluetoothBondState.bonded);

    await pumpEventQueue();
    expect(platform.calls, <String>['bondState device-a']);

    platform
      ..addBondStateChange(
        'device-b',
        BluetoothBondState.bonded,
        previousState: BluetoothBondState.bonding,
      )
      ..addBondStateChange(
        'device-a',
        BluetoothBondState.bonding,
        previousState: BluetoothBondState.notBonded,
      );
    await pumpEventQueue();

    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonded,
      previousState: BluetoothBondState.bonding,
    );
    expect(await waiting, BluetoothBondState.bonded);
  });

  test('BluetoothDevice.connect waits for connected state', () async {
    final platform = FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);

    final connect = platform.device('device-a').connect();
    var connectCompleted = false;
    final connectCompletedFuture = connect.then((_) => connectCompleted = true);

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);
    expect(connectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await pumpEventQueue();
    expect(connectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await connectCompletedFuture;

    expect(connectCompleted, isTrue);
  });

  test('BluetoothDevice.connect completes with an error on failure', () async {
    final platform = FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);

    final connect = platform.device('device-a').connect();
    final connectExpectation = expectLater(
      connect,
      throwsA(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.operationFailed,
            )
            .having((error) => error.operation, 'operation', 'connect')
            .having(
              (error) => error.message,
              'message',
              'Failed to connect to Bluetooth device device-a.',
            ),
      ),
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.failure,
    );

    await connectExpectation;
  });

  test('BluetoothDevice.connect retries a busy shared connection', () async {
    final platform = FakeQuickBluePlatform(
      connectErrors: <Object>[
        const QuickBlueException(
          code: QuickBlueErrorCode.deviceBusy,
          message: 'busy',
        ),
      ],
    );
    addTearDown(platform.dispose);

    await platform.device('device-a').connect();

    expect(platform.calls, <String>['connect device-a', 'connect device-a']);
  });

  test(
    'BluetoothDevice.connect pairs and retries a security failure',
    () async {
      const securityError = QuickBlueSecurityException(
        reason: QuickBlueSecurityErrorReason.insufficientEncryption,
        nativeDomain: 'test.security',
        nativeCode: 15,
        operation: 'connect',
        deviceId: 'device-a',
        message: 'Encryption required',
      );
      final platform = FakeQuickBluePlatform(
        connectErrors: <Object>[securityError],
      );
      addTearDown(platform.dispose);

      await platform.device('device-a').connect();

      expect(platform.calls, <String>[
        'connect device-a',
        'bondState device-a',
        'pair device-a',
        'connect device-a',
      ]);
    },
  );

  test('concurrent security failures share one device recovery', () async {
    const securityError = QuickBlueSecurityException(
      reason: QuickBlueSecurityErrorReason.insufficientAuthentication,
      nativeDomain: 'test.security',
      nativeCode: 5,
      operation: 'readValue',
      deviceId: 'device-a',
      message: 'Authentication required',
    );
    final recoveryCompleter = Completer<void>();
    final platform = FakeQuickBluePlatform(
      securityRecoveryResult: QuickBlueSecurityRecoveryResult.recovered,
      securityRecoveryCompleter: recoveryCompleter,
    );
    addTearDown(platform.dispose);

    final firstRecovery = platform.recoverSecurity('device-a', securityError);
    final secondRecovery = platform.recoverSecurity('device-a', securityError);
    await pumpEventQueue();

    expect(platform.calls, <String>[
      'performSecurityRecovery device-a insufficientAuthentication',
    ]);

    recoveryCompleter.complete();
    expect(
      await Future.wait(<Future<QuickBlueSecurityRecoveryResult>>[
        firstRecovery,
        secondRecovery,
      ]),
      <QuickBlueSecurityRecoveryResult>[
        QuickBlueSecurityRecoveryResult.recovered,
        QuickBlueSecurityRecoveryResult.recovered,
      ],
    );
  });

  test('BluetoothDevice.connect ignores other-device failure events', () async {
    final platform = FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);

    final connect = platform.device('device-a').connect();
    var connectCompleted = false;
    Object? connectError;
    final connectCompletedFuture = connect.then<void>(
      (_) => connectCompleted = true,
      onError: (Object error) => connectError = error,
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['connect device-a']);

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.disconnected,
      BleStatus.failure,
    );
    await pumpEventQueue();

    expect(connectCompleted, isFalse);
    expect(connectError, isNull);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.connected,
      BleStatus.success,
    );
    await connectCompletedFuture;

    expect(connectCompleted, isTrue);
    expect(connectError, isNull);
  });

  test('BluetoothDevice.disconnect waits for disconnected state', () async {
    final platform = FakeQuickBluePlatform(disconnectsImmediately: false);
    addTearDown(platform.dispose);

    final disconnect = platform.device('device-a').disconnect();
    var disconnectCompleted = false;
    final disconnectCompletedFuture = disconnect.then(
      (_) => disconnectCompleted = true,
    );

    await pumpEventQueue();
    expect(platform.calls, <String>['disconnect device-a']);
    expect(disconnectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-b',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await pumpEventQueue();
    expect(disconnectCompleted, isFalse);

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await disconnectCompletedFuture;

    expect(disconnectCompleted, isTrue);
  });

  test(
    'BluetoothDevice.disconnect completes with an error on failure',
    () async {
      final platform = FakeQuickBluePlatform(disconnectsImmediately: false);
      addTearDown(platform.dispose);

      final disconnect = platform.device('device-a').disconnect();
      final disconnectExpectation = expectLater(
        disconnect,
        throwsA(
          isA<QuickBlueException>()
              .having(
                (error) => error.code,
                'code',
                QuickBlueErrorCode.operationFailed,
              )
              .having((error) => error.operation, 'operation', 'disconnect')
              .having(
                (error) => error.message,
                'message',
                'Failed to disconnect Bluetooth device device-a.',
              ),
        ),
      );

      await pumpEventQueue();
      expect(platform.calls, <String>['disconnect device-a']);

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.failure,
      );

      await disconnectExpectation;
    },
  );

  test(
    'BluetoothDevice.disconnect ignores other-device failure events',
    () async {
      final platform = FakeQuickBluePlatform(disconnectsImmediately: false);
      addTearDown(platform.dispose);

      final disconnect = platform.device('device-a').disconnect();
      var disconnectCompleted = false;
      Object? disconnectError;
      final disconnectCompletedFuture = disconnect.then<void>(
        (_) => disconnectCompleted = true,
        onError: (Object error) => disconnectError = error,
      );

      await pumpEventQueue();
      expect(platform.calls, <String>['disconnect device-a']);

      platform.onConnectionChanged!(
        'device-b',
        BlueConnectionState.connected,
        BleStatus.failure,
      );
      await pumpEventQueue();

      expect(disconnectCompleted, isFalse);
      expect(disconnectError, isNull);

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      await disconnectCompletedFuture;

      expect(disconnectCompleted, isTrue);
      expect(disconnectError, isNull);
    },
  );

  test(
    'BluetoothDevice.disconnect supersedes a timed-out connect and permits retry',
    () async {
      final platform = FakeQuickBluePlatform(connectsImmediately: false);
      addTearDown(platform.dispose);

      final device = platform.device('device-a');
      final connect = device.connect();
      await expectLater(
        connect.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );

      await device.disconnect();
      await expectLater(
        connect,
        throwsA(
          isA<QuickBlueException>()
              .having(
                (error) => error.code,
                'code',
                QuickBlueErrorCode.cancelled,
              )
              .having((error) => error.operation, 'operation', 'connect'),
        ),
      );
      expect(platform.calls, <String>[
        'connect device-a',
        'disconnect device-a',
      ]);

      final retry = device.connect();
      await pumpEventQueue();
      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      await retry;

      expect(platform.calls, <String>[
        'connect device-a',
        'disconnect device-a',
        'connect device-a',
      ]);
    },
  );

  test('BluetoothDevice.disconnect stops an automatic busy retry', () async {
    final platform = FakeQuickBluePlatform(
      connectErrors: <Object>[
        const QuickBlueException(
          code: QuickBlueErrorCode.deviceBusy,
          message: 'busy',
        ),
      ],
    );
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final connect = device.connect();
    final connectExpectation = expectLater(
      connect,
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.cancelled,
        ),
      ),
    );
    await pumpEventQueue();

    await device.disconnect();
    await connectExpectation;
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(platform.calls, <String>['connect device-a', 'disconnect device-a']);
  });

  test('BluetoothDevice rejects overlapping disconnect operations', () async {
    final platform = FakeQuickBluePlatform(disconnectsImmediately: false);
    addTearDown(platform.dispose);

    final device = platform.device('device-a');
    final firstDisconnect = device.disconnect();
    await pumpEventQueue();

    await expectLater(
      device.disconnect(),
      throwsA(
        isA<QuickBlueException>()
            .having(
              (error) => error.code,
              'code',
              QuickBlueErrorCode.invalidState,
            )
            .having((error) => error.operation, 'operation', 'disconnect')
            .having((error) => error.details, 'details', 'disconnect'),
      ),
    );

    platform.onConnectionChanged!(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.success,
    );
    await firstDisconnect;
  });

  test(
    'BluetoothDevice allows concurrent operations for different devices',
    () async {
      final platform = FakeQuickBluePlatform(connectsImmediately: false);
      addTearDown(platform.dispose);

      final firstConnect = platform.device('device-a').connect();
      final secondConnect = platform.device('device-b').connect();
      await pumpEventQueue();

      expect(platform.calls, <String>['connect device-a', 'connect device-b']);

      platform.onConnectionChanged!(
        'device-a',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      platform.onConnectionChanged!(
        'device-b',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      await Future.wait(<Future<void>>[firstConnect, secondConnect]);
    },
  );

  test(
    'BluetoothDevice.discoverServices completes with discovered services',
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
            characteristics: const <String>['characteristic-b'],
          ),
          BluetoothService(
            deviceId: 'device-a',
            uuid: 'service-c',
            characteristics: const <String>['characteristic-c'],
          ),
        ],
      );
      addTearDown(platform.dispose);

      final services = await platform.device('device-a').discoverServices();

      expect(services.map((service) => service.uuid), <String>[
        'service-a',
        'service-b',
        'service-c',
      ]);
    },
  );
}
