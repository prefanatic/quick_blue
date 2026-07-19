import 'dart:async';

import 'package:meta/meta.dart';

import '../models.dart';
import 'observability.dart';
import 'quick_blue_exception.dart';

@internal
class ConnectionLifecycleCoordinator {
  ConnectionLifecycleCoordinator({
    required this.connect,
    required this.disconnect,
    required this.connectionStateStream,
  });

  final Future<void> Function(String deviceId) connect;
  final Future<void> Function(String deviceId) disconnect;
  final Stream<BluetoothConnectionStateChange> Function() connectionStateStream;

  final _activeOperations = <String, _ConnectionOperation>{};

  Future<void> connectDevice(String deviceId) {
    return _runOperation(
      deviceId: deviceId,
      operationName: 'connect',
      targetState: BlueConnectionState.connected,
      failureMessage: 'Failed to connect to Bluetooth device $deviceId.',
      operation: (cancellation) =>
          _connectWhenAvailable(deviceId, cancellation),
    );
  }

  Future<void> _connectWhenAvailable(
    String deviceId,
    _ConnectionOperationCancellation cancellation,
  ) async {
    const busyTimeout = Duration(seconds: 30);
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        await cancellation.untilCancelled(
          connect(deviceId),
          error: _cancelledException(deviceId, 'connect'),
        );
        return;
      } on QuickBlueException catch (error) {
        if (error.code != QuickBlueErrorCode.deviceBusy) {
          rethrow;
        }
        if (stopwatch.elapsed >= busyTimeout) {
          throw QuickBlueException(
            code: QuickBlueErrorCode.deviceBusy,
            operation: 'connect',
            deviceId: deviceId,
            details: busyTimeout,
            message:
                'Timed out waiting for the shared connection to $deviceId '
                'to finish disconnecting.',
          );
        }
        await cancellation.untilCancelled(
          Future<void>.delayed(const Duration(milliseconds: 100)),
          error: _cancelledException(deviceId, 'connect'),
        );
      }
    }
  }

  Future<void> disconnectDevice(String deviceId) async {
    final activeOperation = _activeOperations[deviceId];
    if (activeOperation?.name == 'connect') {
      activeOperation!.cancellation.cancel();
      try {
        await activeOperation.completed;
      } on Object {
        // The disconnect is authoritative even if the superseded connect fails.
      }
    }

    return _runOperation(
      deviceId: deviceId,
      operationName: 'disconnect',
      targetState: BlueConnectionState.disconnected,
      failureMessage: 'Failed to disconnect Bluetooth device $deviceId.',
      operation: (_) => disconnect(deviceId),
    );
  }

  Future<void> _runOperation({
    required String deviceId,
    required String operationName,
    required BlueConnectionState targetState,
    required String failureMessage,
    required Future<void> Function(
      _ConnectionOperationCancellation cancellation,
    )
    operation,
  }) {
    final observation = QuickBlueInstrumentation.startOperation(
      operationName == 'connect'
          ? QuickBlueOperationKind.connect
          : QuickBlueOperationKind.disconnect,
      deviceId: deviceId,
    );
    final activeOperation = _activeOperations[deviceId];
    if (activeOperation != null) {
      return QuickBlueInstrumentation.observeCompletion<void>(
        Future<void>.error(
          QuickBlueException(
            code: QuickBlueErrorCode.invalidState,
            operation: operationName,
            deviceId: deviceId,
            details: activeOperation.name,
            message:
                'Cannot $operationName Bluetooth device $deviceId while '
                '${activeOperation.name} is pending.',
          ),
        ),
        observation,
      );
    }
    final connectionOperation = _ConnectionOperation(operationName);
    _activeOperations[deviceId] = connectionOperation;
    connectionOperation.completed = _executeOperation(
      deviceId: deviceId,
      connectionOperation: connectionOperation,
      targetState: targetState,
      failureMessage: failureMessage,
      operation: operation,
    );
    return QuickBlueInstrumentation.observeCompletion<void>(
      connectionOperation.completed,
      observation,
    );
  }

  Future<void> _executeOperation({
    required String deviceId,
    required _ConnectionOperation connectionOperation,
    required BlueConnectionState targetState,
    required String failureMessage,
    required Future<void> Function(
      _ConnectionOperationCancellation cancellation,
    )
    operation,
  }) async {
    final operationName = connectionOperation.name;
    final cancellation = connectionOperation.cancellation;

    final stateCompleter = Completer<BluetoothConnectionStateChange>();
    final stateSubscription = connectionStateStream()
        .where(
          (event) =>
              event.deviceId == deviceId &&
              (event.status == BleStatus.failure || event.state == targetState),
        )
        .listen((state) {
          if (!stateCompleter.isCompleted) {
            stateCompleter.complete(state);
          }
        });

    try {
      final cancellationError = _cancelledException(deviceId, operationName);
      await cancellation.untilCancelled(
        operation(cancellation),
        error: cancellationError,
      );
      final state = await cancellation.untilCancelled(
        stateCompleter.future,
        error: cancellationError,
      );
      if (state.status == BleStatus.failure) {
        if (state.error != null) {
          throw state.error!;
        }
        throw QuickBlueException(
          code: QuickBlueErrorCode.operationFailed,
          operation: operationName,
          deviceId: deviceId,
          details: state.status,
          message: failureMessage,
        );
      }
    } finally {
      await stateSubscription.cancel();
      if (_activeOperations[deviceId] == connectionOperation) {
        _activeOperations.remove(deviceId);
      }
    }
  }

  QuickBlueException _cancelledException(
    String deviceId,
    String operationName,
  ) {
    return QuickBlueException(
      code: QuickBlueErrorCode.cancelled,
      operation: operationName,
      deviceId: deviceId,
      message:
          '${operationName[0].toUpperCase()}${operationName.substring(1)} '
          'for Bluetooth device $deviceId was cancelled.',
    );
  }
}

class _ConnectionOperation {
  _ConnectionOperation(this.name);

  final String name;
  final cancellation = _ConnectionOperationCancellation();
  late final Future<void> completed;
}

class _ConnectionOperationCancellation {
  final _completer = Completer<void>();

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  Future<T> untilCancelled<T>(
    Future<T> operation, {
    required QuickBlueException error,
  }) {
    return Future.any<T>(<Future<T>>[
      operation,
      _completer.future.then<T>((_) => throw error),
    ]);
  }
}
