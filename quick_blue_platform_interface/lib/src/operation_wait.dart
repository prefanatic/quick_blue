import 'dart:async';

import 'package:meta/meta.dart';

import 'quick_blue_exception.dart';

/// One-shot cancellation of a caller's interest in Bluetooth operations.
///
/// Cancellation does not abort native work or disconnect the device. Use a new
/// token for a retry. A token may intentionally cancel several caller waits.
class QuickBlueCancellationToken {
  bool _isCancelled = false;
  final _listeners = <void Function()>{};

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// Registers a caller-local observation wait; already cancelled tokens fire
  /// immediately. Remove the listener when the wait completes.
  @internal
  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  /// Releases a completed observation wait's cancellation listener.
  @internal
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Releases all waits using this token. Repeated calls have no effect.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

/// Caller-local waits over a platform-owned in-flight operation.
///
/// Keep the operation, not expired waiters, until native completion. Reusing it
/// is essential: native callbacks do not carry portable request identifiers, so
/// starting a replacement would let an old callback complete the new request.
@internal
class OperationWaitCoordinator {
  final _pending = <(String, String), _SharedOperation<dynamic>>{};

  @visibleForTesting
  int get pendingOperationCount => _pending.length;

  @visibleForTesting
  int get activeWaiterCount => _pending.values.fold(
    0,
    (count, operation) => count + operation.waiters.length,
  );

  /// Forgets work already invalidated by the underlying lifecycle.
  void forget(String deviceId, String operation) {
    _pending.remove((deviceId, operation));
  }

  Future<T> run<T>({
    required String deviceId,
    required String operation,
    required Future<T> Function() action,
    int? argument,
    Duration? timeout,
    QuickBlueCancellationToken? cancellationToken,
  }) {
    if (timeout != null && timeout.isNegative) {
      return Future<T>.error(ArgumentError.value(timeout, 'timeout'));
    }
    if (cancellationToken?.isCancelled ?? false) {
      return Future<T>.error(_cancelled(deviceId, operation));
    }
    final key = (deviceId, operation);
    if (operation == 'connect' || operation == 'disconnect') {
      final opposite = operation == 'connect' ? 'disconnect' : 'connect';
      final superseded = _pending.remove((deviceId, opposite));
      superseded?.completeError(
        _cancelled(deviceId, opposite),
        StackTrace.current,
      );
    }
    var shared = _pending[key] as _SharedOperation<T>?;
    if (shared != null && shared.argument != argument) {
      return Future<T>.error(
        QuickBlueException(
          code: QuickBlueErrorCode.invalidState,
          operation: operation,
          deviceId: deviceId,
          message: 'A request with a different argument is still pending.',
        ),
      );
    }
    if (shared == null) {
      shared = _SharedOperation<T>(argument);
      _pending[key] = shared;
      final current = shared;
      Future<T>.sync(action).then<void>(
        (value) {
          if (identical(_pending[key], current)) _pending.remove(key);
          current.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_pending[key], current)) _pending.remove(key);
          current.completeError(error, stack);
        },
      );
    }
    // The action can synchronously cancel a token while starting native work.
    if (cancellationToken?.isCancelled ?? false) {
      return Future<T>.error(_cancelled(deviceId, operation));
    }
    final waiter = _OperationWaiter<T>(shared, cancellationToken);
    shared.waiters.add(waiter);
    void cancel() => waiter.fail(_cancelled(deviceId, operation));
    waiter.onCancel = cancel;
    cancellationToken?._listeners.add(cancel);
    if (timeout != null) {
      waiter.timer = Timer(timeout, () {
        waiter.fail(
          TimeoutException(
            '$operation for Bluetooth device $deviceId',
            timeout,
          ),
        );
      });
    }
    return waiter.completer.future;
  }

  QuickBlueException _cancelled(String deviceId, String operation) =>
      QuickBlueException(
        code: QuickBlueErrorCode.cancelled,
        failureReason: QuickBlueFailureReason.callerCancelled,
        operation: operation,
        deviceId: deviceId,
        message: 'The caller stopped waiting for $operation on $deviceId.',
      );
}

class _SharedOperation<T> {
  _SharedOperation(this.argument);

  final int? argument;
  final waiters = <_OperationWaiter<T>>{};

  void complete(T value) {
    for (final waiter in List<_OperationWaiter<T>>.of(waiters)) {
      waiter.detach();
      waiter.completer.complete(value);
    }
  }

  void completeError(Object error, StackTrace stack) {
    for (final waiter in List<_OperationWaiter<T>>.of(waiters)) {
      waiter.fail(error, stack);
    }
  }
}

class _OperationWaiter<T> {
  _OperationWaiter(this.shared, this.token);

  final _SharedOperation<T> shared;
  final QuickBlueCancellationToken? token;
  final completer = Completer<T>();
  Timer? timer;
  late final void Function() onCancel;

  void detach() {
    shared.waiters.remove(this);
    timer?.cancel();
    token?._listeners.remove(onCancel);
  }

  void fail(Object error, [StackTrace? stack]) {
    if (completer.isCompleted) return;
    detach();
    completer.completeError(error, stack);
  }
}
