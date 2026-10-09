import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  testWidgets('timeout releases the bond listener without a target event', (
    tester,
  ) async {
    final platform = _CountingBondPlatform();
    addTearDown(platform.dispose);
    final waiting = platform
        .device('device-a')
        .waitForBondState(
          BluetoothBondState.bonded,
          timeout: const Duration(seconds: 5),
        );
    final expectation = expectLater(
      waiting,
      throwsA(
        isA<TimeoutException>()
            .having((e) => e.duration, 'duration', const Duration(seconds: 5))
            .having(
              (e) => e.message,
              'message',
              'waitForBondState for Bluetooth device device-a',
            ),
      ),
    );
    await tester.pump();
    expect(platform.listenerCount, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() async {
      await expectation;
    });
    expect(platform.listenerCount, 0);
    expect(platform.calls, ['bondState device-a']);
  });

  testWidgets('cancellation releases the listener without a target event', (
    tester,
  ) async {
    final platform = _CountingBondPlatform();
    addTearDown(platform.dispose);
    final token = QuickBlueCancellationToken();
    final waiting = platform
        .device('device-a')
        .waitForBondState(
          BluetoothBondState.bonded,
          cancellationToken: token,
          timeout: const Duration(seconds: 5),
        );
    final expectation = expectLater(waiting, throwsA(_cancelled));
    await tester.pump();
    expect(platform.listenerCount, 1);
    token.cancel();
    await tester.pump();
    await tester.runAsync(() async {
      await expectation;
    });
    expect(platform.listenerCount, 0);
    // testWidgets also checks that no deadline timer remains at test exit.
    expect(platform.calls, ['bondState device-a']);
  });

  for (final stopWithTimeout in [true, false]) {
    testWidgets(
      'stopping during snapshot cleans up; timeout=$stopWithTimeout',
      (tester) async {
        final platform = _CountingBondPlatform();
        addTearDown(platform.dispose);
        final snapshot = platform.snapshot = Completer<BluetoothBondState>();
        final token = QuickBlueCancellationToken();
        final waiting = platform
            .device('device-a')
            .waitForBondState(
              BluetoothBondState.bonded,
              timeout: stopWithTimeout ? const Duration(seconds: 2) : null,
              cancellationToken: token,
            );
        final expectation = expectLater(
          waiting,
          throwsA(stopWithTimeout ? isA<TimeoutException>() : _cancelled),
        );
        await tester.pump();
        expect(platform.listenerCount, 1);
        if (stopWithTimeout) {
          await tester.pump(const Duration(seconds: 2));
        } else {
          token.cancel();
          await tester.pump();
        }
        await tester.runAsync(() async {
          await expectation;
        });
        expect(platform.listenerCount, 0);
        // A late snapshot error is handled and cannot revive the observer.
        snapshot.completeError(StateError('late snapshot failure'));
        await tester.pump();
        expect(platform.listenerCount, 0);
      },
    );

    testWidgets(
      'concurrent waiters are independent; timeout=$stopWithTimeout',
      (tester) async {
        final platform = _CountingBondPlatform();
        addTearDown(platform.dispose);
        final token = QuickBlueCancellationToken();
        final device = platform.device('device-a');
        final first = device.waitForBondState(
          BluetoothBondState.bonded,
          timeout: stopWithTimeout ? const Duration(seconds: 2) : null,
          cancellationToken: token,
        );
        final expectation = expectLater(
          first,
          throwsA(stopWithTimeout ? isA<TimeoutException>() : _cancelled),
        );
        final second = device.waitForBondState(BluetoothBondState.bonding);
        await tester.pump();
        expect(platform.listenerCount, 2);
        if (stopWithTimeout) {
          await tester.pump(const Duration(seconds: 2));
        } else {
          token.cancel();
          await tester.pump();
        }
        await tester.runAsync(() async {
          await expectation;
        });
        expect(platform.listenerCount, 1);
        platform.addBondStateChange(
          'device-a',
          BluetoothBondState.bonding,
          previousState: BluetoothBondState.notBonded,
        );
        await tester.pump();
        expect(await tester.runAsync(() => second), BluetoothBondState.bonding);
        expect(platform.listenerCount, 0);
        expect(platform.calls, ['bondState device-a', 'bondState device-a']);
      },
    );
  }

  testWidgets('snapshot/event race retains a matching event', (tester) async {
    final platform = _CountingBondPlatform();
    addTearDown(platform.dispose);
    final snapshot = platform.snapshot = Completer<BluetoothBondState>();
    final waiting = platform
        .device('device-a')
        .waitForBondState(
          BluetoothBondState.bonded,
          timeout: const Duration(seconds: 5),
        );
    expect(platform.listenerCount, 1);
    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonded,
      previousState: BluetoothBondState.bonding,
    );
    await tester.pump();
    snapshot.complete(BluetoothBondState.notBonded);
    await tester.pump();
    expect(await tester.runAsync(() => waiting), BluetoothBondState.bonded);
    expect(platform.listenerCount, 0);
  });

  testWidgets('immediate snapshot releases listeners and timer', (
    tester,
  ) async {
    final platform = _CountingBondPlatform()
      ..currentBondState = BluetoothBondState.bonded;
    addTearDown(platform.dispose);
    final token = QuickBlueCancellationToken();
    final waiting = platform
        .device('device-a')
        .waitForBondState(
          BluetoothBondState.bonded,
          timeout: const Duration(seconds: 5),
          cancellationToken: token,
        );
    await tester.pump();
    expect(await tester.runAsync(() => waiting), BluetoothBondState.bonded);
    expect(platform.listenerCount, 0);
    token.cancel();
    await tester.pump();
  });

  testWidgets('snapshot failure is preserved and releases the listener', (
    tester,
  ) async {
    final platform = _CountingBondPlatform();
    addTearDown(platform.dispose);
    final snapshot = platform.snapshot = Completer<BluetoothBondState>();
    final error = StateError('snapshot failed');
    final waiting = platform
        .device('device-a')
        .waitForBondState(
          BluetoothBondState.bonded,
          timeout: const Duration(seconds: 5),
        );
    final expectation = expectLater(waiting, throwsA(same(error)));
    snapshot.completeError(error);
    await tester.pump();
    await tester.runAsync(() async {
      await expectation;
    });
    expect(platform.listenerCount, 0);
  });

  testWidgets('pre-cancelled and invalid timeout do no platform work', (
    tester,
  ) async {
    final platform = _CountingBondPlatform();
    addTearDown(platform.dispose);
    final token = QuickBlueCancellationToken()..cancel();
    final device = platform.device('device-a');
    final cancelled = expectLater(
      device.waitForBondState(
        BluetoothBondState.bonded,
        cancellationToken: token,
      ),
      throwsA(_cancelled),
    );
    final invalid = expectLater(
      device.waitForBondState(
        BluetoothBondState.bonded,
        timeout: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
    await tester.pump();
    await cancelled;
    await invalid;
    expect(platform.calls, isEmpty);
    expect(platform.listenerCount, 0);
  });

  testWidgets('no options stays pending and filters state and device', (
    tester,
  ) async {
    final platform = _CountingBondPlatform();
    addTearDown(platform.dispose);
    var completed = false;
    final waiting = platform
        .device('device-a')
        .waitForBondState(BluetoothBondState.bonded)
        .then((value) {
          completed = true;
          return value;
        });
    await tester.pump(const Duration(days: 1));
    platform.addBondStateChange(
      'device-b',
      BluetoothBondState.bonded,
      previousState: BluetoothBondState.bonding,
    );
    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonding,
      previousState: BluetoothBondState.notBonded,
    );
    await tester.pump();
    expect(completed, isFalse);
    expect(platform.listenerCount, 1);
    platform.addBondStateChange(
      'device-a',
      BluetoothBondState.bonded,
      previousState: BluetoothBondState.bonding,
    );
    await tester.pump();
    expect(await tester.runAsync(() => waiting), BluetoothBondState.bonded);
    expect(platform.listenerCount, 0);
  });
}

final _cancelled = isA<QuickBlueException>()
    .having((e) => e.code, 'code', QuickBlueErrorCode.cancelled)
    .having(
      (e) => e.failureReason,
      'reason',
      QuickBlueFailureReason.callerCancelled,
    )
    .having((e) => e.operation, 'operation', 'waitForBondState')
    .having((e) => e.deviceId, 'deviceId', 'device-a');

class _CountingBondPlatform extends FakeQuickBluePlatform {
  int listenerCount = 0;
  Completer<BluetoothBondState>? snapshot;

  @override
  Stream<BluetoothBondStateChange> get bondStateStream =>
      Stream<BluetoothBondStateChange>.multi((controller) {
        listenerCount++;
        final subscription = super.bondStateStream.listen(
          controller.addSync,
          onError: controller.addErrorSync,
          onDone: controller.closeSync,
        );
        controller.onPause = subscription.pause;
        controller.onResume = subscription.resume;
        controller.onCancel = () async {
          await subscription.cancel();
          listenerCount--;
        };
      }, isBroadcast: true);

  @override
  Future<BluetoothBondState> bondState(String deviceId) {
    calls.add('bondState $deviceId');
    return snapshot?.future ?? Future.value(currentBondState);
  }
}
