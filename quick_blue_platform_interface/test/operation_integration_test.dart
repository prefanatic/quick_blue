import 'dart:async';

import 'package:test/test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

Matcher get callerCancelled => throwsA(
  isA<QuickBlueException>()
      .having((e) => e.code, 'code', QuickBlueErrorCode.cancelled)
      .having(
        (e) => e.failureReason,
        'reason',
        QuickBlueFailureReason.callerCancelled,
      ),
);

void main() {
  for (final connectFirst in [true, false]) {
    test(
      'same-turn opposite operations: latest ${connectFirst ? 'connect' : 'disconnect'} wins',
      () async {
        final platform = FakeQuickBluePlatform();
        addTearDown(platform.dispose);
        final device = platform.device('a');
        final first = connectFirst ? device.connect() : device.disconnect();
        final firstFailure = expectLater(first, callerCancelled);
        final opposite = connectFirst ? device.disconnect() : device.connect();
        final oppositeFailure = expectLater(opposite, callerCancelled);
        final latest = connectFirst ? device.connect() : device.disconnect();
        await Future.wait([firstFailure, oppositeFailure, latest]);
        expect(
          platform.calls,
          connectFirst
              ? ['connect a', 'connect a']
              : ['disconnect a', 'disconnect a'],
        );
      },
    );
  }

  for (final managed in [false, true]) {
    test(
      '${managed ? 'managed cancellation' : 'explicit disconnect'} prevents late recovery reconnect',
      () async {
        final recovery = Completer<void>();
        final platform = FakeQuickBluePlatform(
          connectErrors: [
            const QuickBlueSecurityException(
              reason: QuickBlueSecurityErrorReason.insufficientAuthentication,
              nativeDomain: 'test.security',
              nativeCode: 5,
              operation: 'connect',
              message: 'Security rejection',
            ),
          ],
          securityRecoveryResult: QuickBlueSecurityRecoveryResult.recovered,
          securityRecoveryCompleter: recovery,
        );
        addTearDown(platform.dispose);
        final device = platform.device('a');
        StreamSubscription<BluetoothConnectionStateChange>? subscription;
        Future<void>? failed;
        if (managed) {
          subscription = device.maintainConnection().listen((_) {});
        } else {
          failed = expectLater(device.connect(), callerCancelled);
        }
        await pumpEventQueue();
        expect(platform.calls, [
          'connect a',
          'performSecurityRecovery a insufficientAuthentication',
        ]);
        if (managed) {
          await subscription!.cancel();
        } else {
          await device.disconnect();
          await failed;
        }
        recovery.complete();
        await pumpEventQueue();
        expect(platform.calls, [
          'connect a',
          'performSecurityRecovery a insufficientAuthentication',
          'disconnect a',
        ]);
      },
    );
  }

  for (final preCancelled in [true, false]) {
    test(
      'token cancellation has a typed reason (pre-cancelled: $preCancelled)',
      () async {
        final platform = FakeQuickBluePlatform(connectsImmediately: false);
        addTearDown(platform.dispose);
        final token = QuickBlueCancellationToken();
        if (preCancelled) token.cancel();
        final result = expectLater(
          platform.device('a').connect(cancellationToken: token),
          callerCancelled,
        );
        token.cancel();
        await result;
        if (!preCancelled) await platform.device('a').disconnect();
      },
    );
  }
}
