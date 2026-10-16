import 'dart:async';

import 'package:test/test.dart';
import 'package:quick_blue_platform_interface/src/cancellation_signal.dart';

/// The shared cancellation primitive every coordinator now races against. Its
/// precedence rules are load-bearing: a genuine platform failure must win over a
/// later cancellation, and a cancellation is one-shot.
void main() {
  test('an operation that completes first wins', () async {
    final signal = CancellationSignal();
    final completer = Completer<int>();

    final result = signal.race<int>(
      completer.future,
      cancellationError: () => StateError('cancelled'),
    );
    completer.complete(7);

    expect(await result, 7);
    expect(signal.isCancelled, isFalse);
  });

  test('a cancellation wins over a still-pending operation', () async {
    final signal = CancellationSignal();
    final completer = Completer<int>();

    final result = signal.race<int>(
      completer.future,
      cancellationError: () => StateError('cancelled'),
    );
    signal.cancel();

    await expectLater(result, throwsA(isA<StateError>()));
    expect(signal.isCancelled, isTrue);
  });

  test(
    'a platform failure propagating first is not masked by a cancellation',
    () async {
      final signal = CancellationSignal();
      final completer = Completer<int>();

      final result = signal.race<int>(
        completer.future,
        cancellationError: () => StateError('cancelled'),
      );
      completer.completeError(ArgumentError('platform failure'));
      signal.cancel();

      await expectLater(result, throwsA(isA<ArgumentError>()));
    },
  );

  test('cancellation is one-shot and idempotent', () {
    final signal = CancellationSignal();
    signal.cancel();
    signal.cancel();

    expect(signal.isCancelled, isTrue);
  });

  test(
    'racing after cancellation still settles with the cancellation error',
    () async {
      final signal = CancellationSignal()..cancel();
      final never = Completer<void>().future;

      await expectLater(
        signal.race<void>(
          never,
          cancellationError: () => StateError('cancelled'),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'the cancellation error is built when the signal fires, not when racing',
    () async {
      final signal = CancellationSignal();
      final never = Completer<void>().future;
      // A race is armed before anything knows why the operation was cancelled:
      // the caller records the reason only when it actually cancels.
      StateError? reason;

      final result = signal.race<void>(
        never,
        cancellationError: () => reason ?? StateError('fallback'),
      );
      reason = StateError('because the device disconnected');
      signal.cancel();

      await expectLater(
        result,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'because the device disconnected',
          ),
        ),
      );
    },
  );

  test(
    'the cancellation error factory is not called without a cancellation',
    () async {
      final signal = CancellationSignal();
      var calls = 0;

      expect(
        await signal.race<int>(
          Future<int>.value(3),
          cancellationError: () {
            calls += 1;
            return StateError('cancelled');
          },
        ),
        3,
      );
      expect(calls, 0);
    },
  );
}
