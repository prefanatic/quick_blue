import 'package:test/test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  test('attaching a reason preserves all exception context', () {
    final diagnostics = <String, Object>{'domain': 'native', 'code': 999};
    final error = QuickBlueException(
      code: QuickBlueErrorCode.operationFailed,
      message: 'arbitrary localized text',
      operation: 'connect',
      deviceId: 'device-a',
      serviceId: 'service-a',
      characteristicId: 'characteristic-a',
      details: diagnostics,
    ).withFailureReason(QuickBlueFailureReason.connectionFailed);
    expect(error.failureReason, QuickBlueFailureReason.connectionFailed);
    expect(error.details, same(diagnostics));
    expect(error.message, 'arbitrary localized text');
    expect(error.operation, 'connect');
    expect(error.deviceId, 'device-a');
    expect(error.serviceId, 'service-a');
    expect(error.characteristicId, 'characteristic-a');
  });

  test('GATT and security subtypes survive reason attachment and recovery', () {
    const gatt = QuickBlueGattException(
      status: 999,
      message: 'vendor status',
      operation: 'connection',
    );
    final classified = gatt.withFailureReason(
      QuickBlueFailureReason.remoteDisconnected,
    );
    expect(classified.status, 999);
    expect(classified.details, 999);
    expect(classified.failureReason, QuickBlueFailureReason.remoteDisconnected);
    const security = QuickBlueSecurityException(
      reason: QuickBlueSecurityErrorReason.insufficientEncryption,
      nativeDomain: 'CBATTErrorDomain',
      nativeCode: 15,
      message: 'native text',
      operation: 'connect',
    );
    final recovered = security
        .withFailureReason(QuickBlueFailureReason.connectionFailed)
        .withRecoveryResult(QuickBlueSecurityRecoveryResult.userActionRequired);
    expect(recovered.reason, security.reason);
    expect(recovered.nativeDomain, security.nativeDomain);
    expect(recovered.nativeCode, security.nativeCode);
    expect(recovered.message, security.message);
    expect(recovered.failureReason, QuickBlueFailureReason.connectionFailed);
  });

  test(
    'programming errors and invalid-state errors are not connection failures',
    () async {
      final bug = StateError('connection failed');
      const invalid = QuickBlueException(
        code: QuickBlueErrorCode.invalidState,
        message: 'remote disconnect caller cancelled connection failed',
      );
      final platform = FakeQuickBluePlatform(connectErrors: [bug, invalid]);
      addTearDown(platform.dispose);
      await expectLater(
        platform.device('device-a').connect(),
        throwsA(same(bug)),
      );
      await expectLater(
        platform.device('device-a').connect(),
        throwsA(same(invalid)),
      );
      expect(invalid.failureReason, isNull);
    },
  );

  test('connection failure event preserves native diagnostics', () async {
    final platform = FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);
    const native = QuickBlueGattException(
      status: 133,
      operation: 'connection',
      message: 'anything',
    );
    final connecting = platform.device('device-a').connect();
    final expectation = expectLater(
      connecting,
      throwsA(
        isA<QuickBlueGattException>()
            .having(
              (e) => e.failureReason,
              'reason',
              QuickBlueFailureReason.connectionFailed,
            )
            .having((e) => e.status, 'status', 133)
            .having((e) => e.message, 'message', 'anything'),
      ),
    );
    platform.handleConnectionStateChanged(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.failure,
      error: native,
    );
    await expectation;
  });

  test('disconnect superseding connect is caller cancellation', () async {
    final platform = FakeQuickBluePlatform(connectsImmediately: false);
    addTearDown(platform.dispose);
    final connecting = platform.device('device-a').connect();
    final expectation = expectLater(
      connecting,
      throwsA(
        isA<QuickBlueException>()
            .having((e) => e.code, 'code', QuickBlueErrorCode.cancelled)
            .having(
              (e) => e.failureReason,
              'reason',
              QuickBlueFailureReason.callerCancelled,
            ),
      ),
    );
    await platform.device('device-a').disconnect();
    await expectation;
  });

  test(
    'unexpected established disconnect has a reason even on native success',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      await platform.device('device-a').connect();
      final event = platform.connectionStateStream.first;
      platform.handleConnectionStateChanged(
        'device-a',
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      final disconnected = await event;
      expect(disconnected.status, BleStatus.success);
      expect(
        disconnected.error?.failureReason,
        QuickBlueFailureReason.remoteDisconnected,
      );
    },
  );

  test('remote disconnect keeps security native identity', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    await platform.device('device-a').connect();
    const native = QuickBlueSecurityException(
      reason: QuickBlueSecurityErrorReason.peerRemovedPairingInformation,
      nativeDomain: 'CBErrorDomain',
      nativeCode: 14,
      operation: 'connection',
      message: 'localized diagnostic',
    );
    final event = platform.connectionStateStream.first;
    platform.handleConnectionStateChanged(
      'device-a',
      BlueConnectionState.disconnected,
      BleStatus.failure,
      error: native,
    );
    final error = (await event).error as QuickBlueSecurityException;
    expect(error.failureReason, QuickBlueFailureReason.remoteDisconnected);
    expect(error.nativeDomain, native.nativeDomain);
    expect(error.nativeCode, native.nativeCode);
    expect(error.reason, native.reason);
    expect(error.message, native.message);
  });

  test(
    'local disconnect is not a remote failure and reconnect resets context',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      await platform.device('device-a').connect();
      final local = platform.connectionStateStream.first;
      await platform.device('device-a').disconnect();
      expect((await local).error, isNull);
      await platform.device('device-a').connect();
      final remote = platform.connectionStateStream.first;
      platform.handleConnectionStateChanged(
        'device-a',
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      expect(
        (await remote).error?.failureReason,
        QuickBlueFailureReason.remoteDisconnected,
      );
    },
  );

  test(
    'unobserved and other-device disconnects are not guessed as remote',
    () async {
      final platform = FakeQuickBluePlatform();
      addTearDown(platform.dispose);
      await platform.device('device-a').connect();
      final event = platform.connectionStateStream.first;
      platform.handleConnectionStateChanged(
        'device-b',
        BlueConnectionState.disconnected,
        BleStatus.failure,
      );
      expect((await event).error, isNull);
    },
  );

  test(
    'remote loss cancels discovery with reason and original diagnostics',
    () async {
      final platform = FakeQuickBluePlatform(completesServiceDiscovery: false);
      addTearDown(platform.dispose);
      await platform.device('device-a').connect();
      final discovery = platform.device('device-a').discoverServices();
      final expectation = expectLater(
        discovery,
        throwsA(
          isA<QuickBlueException>()
              .having(
                (e) => e.failureReason,
                'reason',
                QuickBlueFailureReason.remoteDisconnected,
              )
              .having(
                (e) => e.details,
                'cause',
                isA<QuickBlueGattException>().having(
                  (e) => e.status,
                  'native status',
                  999,
                ),
              ),
        ),
      );
      await pumpEventQueue();
      platform.handleConnectionStateChanged(
        'device-a',
        BlueConnectionState.disconnected,
        BleStatus.failure,
        error: const QuickBlueGattException(
          status: 999,
          message: 'native diagnostic',
          operation: 'connection',
        ),
      );
      await expectation;
    },
  );

  test(
    'explicit local disconnect cancels pending discovery as caller cancellation',
    () async {
      final platform = FakeQuickBluePlatform(completesServiceDiscovery: false);
      addTearDown(platform.dispose);
      await platform.device('device-a').connect();
      final discovery = platform.device('device-a').discoverServices();
      final expectation = expectLater(
        discovery,
        throwsA(
          isA<QuickBlueException>()
              .having((e) => e.code, 'code', QuickBlueErrorCode.cancelled)
              .having(
                (e) => e.failureReason,
                'reason',
                QuickBlueFailureReason.callerCancelled,
              ),
        ),
      );
      await pumpEventQueue();
      await platform.device('device-a').disconnect();
      await expectation;
    },
  );

  test(
    'database invalidation is not mistaken for caller cancellation',
    () async {
      final platform = FakeQuickBluePlatform(completesServiceDiscovery: false);
      addTearDown(platform.dispose);
      final discovery = platform.device('device-a').discoverServices();
      final expectation = expectLater(
        discovery,
        throwsA(
          isA<QuickBlueException>()
              .having((e) => e.code, 'code', QuickBlueErrorCode.cancelled)
              .having((e) => e.failureReason, 'reason', isNull),
        ),
      );
      await pumpEventQueue();
      platform.handleGattServicesChanged('device-a');
      await expectation;
    },
  );
}
