import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

/// Runs an async contract against a fake clock and checks timer cleanup.
void testWithClock(String description, Future<void> Function(TestClock) body) {
  test(description, () async {
    var completed = false;
    Object? failure;
    StackTrace? trace;
    late FakeAsync clock;
    fakeAsync((fake) {
      clock = fake;
      body(TestClock(clock)).then(
        (_) {
          completed = true;
        },
        onError: (Object error, StackTrace stack) {
          completed = true;
          failure = error;
          trace = stack;
        },
      );
      clock.flushMicrotasks();
    });
    // package:test expectation futures can settle in its enclosing test zone.
    // Drain those turns too, without advancing fake deadlines automatically.
    for (var turn = 0; !completed && turn < 100; turn++) {
      await Future<void>.delayed(Duration.zero);
      clock.flushMicrotasks();
    }
    expect(completed, isTrue, reason: 'Test must settle within the watchdog');
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    expect(
      clock.pendingTimers,
      isEmpty,
      reason: 'Deadline timers must be released',
    );
  });
}

class TestClock {
  TestClock(this.clock);
  final FakeAsync clock;
  Future<void> pump([Duration duration = Duration.zero]) async {
    clock.elapse(duration);
  }

  Future<T> runAsync<T>(Future<T> Function() action) => action();
}
