import 'dart:async';

import 'package:test/test.dart';
import 'test_support/test_clock.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';
import 'package:quick_blue_platform_interface/src/operation_wait.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  for (final operation in [
    'connect',
    'disconnect',
    'discoverServices',
    'requestMtu',
  ]) {
    test(
      '$operation releases expired callers and rejoins missing native work',
      () async {
        final coordinator = OperationWaitCoordinator();
        final native = Completer<int>();
        var starts = 0;
        Future<int> call({
          Duration? timeout,
          QuickBlueCancellationToken? token,
        }) => coordinator.run<int>(
          deviceId: 'device-a',
          operation: operation,
          action: () {
            starts++;
            return native.future;
          },
          timeout: timeout,
          cancellationToken: token,
        );

        final survivor = call();
        await expectLater(
          call(timeout: Duration.zero),
          throwsA(isA<TimeoutException>()),
        );
        final token = QuickBlueCancellationToken();
        final cancelled = call(token: token);
        final cancelledExpectation = expectLater(
          cancelled,
          throwsA(
            isA<QuickBlueException>()
                .having((e) => e.code, 'code', QuickBlueErrorCode.cancelled)
                .having((e) => e.operation, 'operation', operation)
                .having((e) => e.deviceId, 'deviceId', 'device-a'),
          ),
        );
        token.cancel();
        token.cancel();
        await cancelledExpectation;
        expect(coordinator.activeWaiterCount, 1);
        final retry = call();
        expect(starts, 1);
        native.complete(247);
        expect(await survivor, 247);
        expect(await retry, 247);
        expect(coordinator.activeWaiterCount, 0);
        expect(coordinator.pendingOperationCount, 0);
        expect(await call(), 247);
        expect(starts, 2);
      },
    );

    test('$operation consumes late errors after every caller leaves', () async {
      final coordinator = OperationWaitCoordinator();
      final native = Completer<int>();
      var starts = 0;
      Future<int> call(Duration timeout) => coordinator.run<int>(
        deviceId: 'device-a',
        operation: operation,
        timeout: timeout,
        action: () {
          starts++;
          return native.future;
        },
      );
      // Repeated waits must never issue replacement native requests.
      for (var i = 0; i < 20; i++) {
        await expectLater(
          call(Duration.zero),
          throwsA(isA<TimeoutException>()),
        );
      }
      expect(starts, 1);
      expect(coordinator.activeWaiterCount, 0);
      expect(coordinator.pendingOperationCount, 1);
      native.completeError(StateError('late failure'));
      await pumpEventQueue();
      expect(coordinator.pendingOperationCount, 0);
      await expectLater(call(const Duration(seconds: 1)), throwsStateError);
      expect(starts, 2);
    });
  }

  test(
    'pre-cancelled and negative-deadline requests do not start native work',
    () async {
      final coordinator = OperationWaitCoordinator();
      var starts = 0;
      Future<void> call({
        Duration? timeout,
        QuickBlueCancellationToken? token,
      }) => coordinator.run<void>(
        deviceId: 'a',
        operation: 'connect',
        action: () async {
          starts++;
        },
        timeout: timeout,
        cancellationToken: token,
      );
      await expectLater(
        call(token: QuickBlueCancellationToken()..cancel()),
        throwsA(isA<QuickBlueException>()),
      );
      await expectLater(
        call(timeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(starts, 0);
    },
  );

  testWithClock(
    'success removes long deadline timer before later cancellation',
    (tester) async {
      final coordinator = OperationWaitCoordinator();
      final token = QuickBlueCancellationToken();
      expect(
        await coordinator.run<int>(
          deviceId: 'a',
          operation: 'requestMtu',
          action: () async => 247,
          timeout: const Duration(hours: 1),
          cancellationToken: token,
        ),
        247,
      );
      token.cancel();
    },
  );

  test('synchronous cancellation during native start is not missed', () async {
    final coordinator = OperationWaitCoordinator();
    final token = QuickBlueCancellationToken();
    await expectLater(
      coordinator.run<int>(
        deviceId: 'a',
        operation: 'requestMtu',
        action: () {
          token.cancel();
          return Future.value(247);
        },
        cancellationToken: token,
      ),
      throwsA(isA<QuickBlueException>()),
    );
  });

  test(
    'conflicting MTU arguments cannot create replacement native work',
    () async {
      final coordinator = OperationWaitCoordinator();
      final native = Completer<int>();
      final first = coordinator.run<int>(
        deviceId: 'a',
        operation: 'requestMtu',
        argument: 247,
        action: () => native.future,
      );
      await expectLater(
        coordinator.run<int>(
          deviceId: 'a',
          operation: 'requestMtu',
          argument: 512,
          action: () async => fail('must not start'),
        ),
        throwsA(isA<QuickBlueException>()),
      );
      native.complete(247);
      expect(await first, 247);
    },
  );

  test(
    'connect timeout and cancellation leave other device handles interested',
    () async {
      final platform = FakeQuickBluePlatform(connectsImmediately: false);
      addTearDown(platform.dispose);
      final token = QuickBlueCancellationToken();
      final abandoned = platform.device('a').connect(cancellationToken: token);
      final expectation = expectLater(
        abandoned,
        throwsA(isA<QuickBlueException>()),
      );
      final survivor = platform.device('a').connect();
      token.cancel();
      await expectation;
      await expectLater(
        platform.device('a').connect(timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      final retry = platform.device('a').connect();
      expect(platform.calls, ['connect a']);
      platform.onConnectionChanged!(
        'a',
        BlueConnectionState.connected,
        BleStatus.success,
      );
      await Future.wait([survivor, retry]);
      await platform.device('a').disconnect();
    },
  );

  test(
    'disconnect deadline cannot undo native detach; retry shares callback',
    () async {
      final platform = FakeQuickBluePlatform(disconnectsImmediately: false);
      addTearDown(platform.dispose);
      await expectLater(
        platform.device('a').disconnect(timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      final retry = platform.device('a').disconnect();
      expect(platform.calls, ['disconnect a']);
      platform.onConnectionChanged!(
        'a',
        BlueConnectionState.disconnected,
        BleStatus.success,
      );
      await retry;
    },
  );

  test(
    'discovery timeout rejoins until invalidation, then starts fresh',
    () async {
      final platform = FakeQuickBluePlatform(completesServiceDiscovery: false);
      addTearDown(platform.dispose);
      await expectLater(
        platform.device('a').discoverGatt(timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      final survivor = platform.device('a').discoverServices();
      final invalidation = expectLater(
        survivor,
        throwsA(isA<QuickBlueException>()),
      );
      platform.handleGattServicesChanged('a');
      // Retry in the same synchronous turn, before the old future unwinds.
      final retry = platform.device('a').discoverServices();
      await invalidation;
      await pumpEventQueue();
      expect(platform.calls, ['discoverServices a', 'discoverServices a']);
      platform.onServiceDiscoveryComplete('a');
      expect(await retry, isEmpty);
    },
  );

  test(
    'MTU deadline and cancellation share negotiation and preserve another engine',
    () async {
      final native = Completer<int>();
      // Two Dart platform instances model independent engine-local wait tables.
      // Native ownership remains shared; caller cancellation never invokes detach.
      final firstEngine = _PendingMtuPlatform(native);
      final secondEngine = _PendingMtuPlatform(native);
      addTearDown(firstEngine.dispose);
      addTearDown(secondEngine.dispose);
      final survivor = secondEngine.device('a').requestMtu(247);
      await expectLater(
        firstEngine.device('a').requestMtu(247, timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      final token = QuickBlueCancellationToken();
      final cancelled = firstEngine
          .device('a')
          .requestMtu(247, cancellationToken: token);
      final expectation = expectLater(
        cancelled,
        throwsA(isA<QuickBlueException>()),
      );
      token.cancel();
      await expectation;
      final retry = firstEngine.device('a').requestMtu(247);
      expect(firstEngine.calls, ['requestMtu a 247']);
      expect(secondEngine.calls, ['requestMtu a 247']);
      native.complete(247);
      expect(await survivor, 247);
      expect(await retry, 247);
    },
  );
}

class _PendingMtuPlatform extends FakeQuickBluePlatform {
  _PendingMtuPlatform(this.native);
  final Completer<int> native;

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    calls.add('requestMtu $deviceId $expectedMtu');
    return native.future;
  }
}
