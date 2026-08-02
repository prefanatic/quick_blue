import 'dart:async';

import 'package:meta/meta.dart';

import '../models.dart';
import 'quick_blue_exception.dart';

@internal
class ManagedConnectionLifecycleCoordinator {
  ManagedConnectionLifecycleCoordinator({
    required this.connect,
    required this.disconnect,
    required this.connectionStateStream,
  });

  final Future<void> Function(String deviceId) connect;
  final Future<void> Function(String deviceId) disconnect;
  final Stream<BluetoothConnectionStateChange> Function() connectionStateStream;

  final _activeConnections = <String, _ManagedConnection>{};

  bool isActive(String deviceId) => _activeConnections.containsKey(deviceId);

  Stream<BluetoothConnectionStateChange> maintainConnection(
    String deviceId,
    BluetoothReconnectionPolicy policy,
  ) {
    return Stream<BluetoothConnectionStateChange>.multi((controller) {
      if (_activeConnections.containsKey(deviceId)) {
        controller
          ..addErrorSync(
            QuickBlueException(
              code: QuickBlueErrorCode.invalidState,
              operation: 'maintainConnection',
              deviceId: deviceId,
              message:
                  'A managed connection for Bluetooth device $deviceId is '
                  'already active.',
            ),
          )
          ..closeSync();
        return;
      }

      late final _ManagedConnection connection;
      connection = _ManagedConnection(
        deviceId: deviceId,
        policy: policy,
        connect: connect,
        disconnect: disconnect,
        connectionStateStream: connectionStateStream,
        controller: controller,
        onFinished: () {
          if (identical(_activeConnections[deviceId], connection)) {
            _activeConnections.remove(deviceId);
          }
        },
      );
      _activeConnections[deviceId] = connection;
      controller.onCancel = connection.cancel;
      connection.start();
    });
  }

  Future<void> stopForExplicitDisconnect(String deviceId) async {
    await _activeConnections[deviceId]?.stop(disconnect: false);
  }
}

class _ManagedConnection {
  _ManagedConnection({
    required this.deviceId,
    required this.policy,
    required this.connect,
    required this.disconnect,
    required this.connectionStateStream,
    required this.controller,
    required this.onFinished,
  });

  final String deviceId;
  final BluetoothReconnectionPolicy policy;
  final Future<void> Function(String deviceId) connect;
  final Future<void> Function(String deviceId) disconnect;
  final Stream<BluetoothConnectionStateChange> Function() connectionStateStream;
  final MultiStreamController<BluetoothConnectionStateChange> controller;
  final void Function() onFinished;

  final _stopSignal = Completer<void>();
  StreamSubscription<BluetoothConnectionStateChange>? _eventSubscription;
  Completer<void>? _nextDisconnection;
  late final Future<void> _reporting;
  bool _connected = false;
  bool _connectionInFlight = false;
  bool _disconnectWhenStopped = true;
  bool _stopRequested = false;
  bool _runFinished = false;
  Object? _stopError;
  StackTrace? _stopStackTrace;

  void start() {
    _eventSubscription = connectionStateStream()
        .where((event) => event.deviceId == deviceId)
        .listen(
          _handleConnectionState,
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addErrorSync(error, stackTrace);
            }
          },
        );

    _reporting = _run().then<void>(
      (_) {
        _runFinished = true;
        if (!controller.isClosed) {
          controller.closeSync();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _runFinished = true;
        if (_stopRequested) {
          _stopError = error;
          _stopStackTrace = stackTrace;
        } else if (!controller.isClosed) {
          controller
            ..addErrorSync(error, stackTrace)
            ..closeSync();
        }
      },
    );
  }

  void _handleConnectionState(BluetoothConnectionStateChange event) {
    if (event.state == BlueConnectionState.connected &&
        event.status == BleStatus.success) {
      _connected = true;
    } else if (event.state == BlueConnectionState.disconnected) {
      final wasConnected = _connected;
      _connected = false;
      if (wasConnected && !(_nextDisconnection?.isCompleted ?? true)) {
        _nextDisconnection!.complete();
      }
    }

    if (!controller.isClosed) {
      controller.addSync(event);
    }
  }

  Future<void> _run() async {
    try {
      await _connectOnce();

      while (true) {
        final nextDisconnection = _nextDisconnection;
        if (nextDisconnection == null) {
          throw StateError('Managed connection has no disconnect signal.');
        }
        await _untilStopped(nextDisconnection.future);
        _nextDisconnection = null;

        var attempt = 1;
        while (true) {
          await _untilStopped(
            Future<void>.delayed(policy.delayForAttempt(attempt)),
          );
          try {
            await _connectOnce();
            break;
          } on _ManagedConnectionStopped {
            rethrow;
          } catch (error, stackTrace) {
            if (policy.maxAttempts == attempt) {
              Error.throwWithStackTrace(error, stackTrace);
            }
            attempt += 1;
          }
        }
      }
    } on _ManagedConnectionStopped {
      // Subscription cancellation and explicit disconnect are normal stops.
    } finally {
      try {
        if (_disconnectWhenStopped && (_connected || _connectionInFlight)) {
          await disconnect(deviceId);
        }
      } finally {
        await _eventSubscription?.cancel();
        onFinished();
      }
    }
  }

  Future<void> _connectOnce() async {
    _nextDisconnection = Completer<void>();
    _connectionInFlight = true;
    try {
      await _untilStopped(connect(deviceId));
      _connectionInFlight = false;
      if (!_nextDisconnection!.isCompleted) {
        _connected = true;
      }
    } catch (_) {
      if (!_stopSignal.isCompleted) {
        _connectionInFlight = false;
        _nextDisconnection = null;
      }
      rethrow;
    }
  }

  Future<T> _untilStopped<T>(Future<T> operation) {
    return Future.any<T>(<Future<T>>[
      operation,
      _stopSignal.future.then<T>(
        (_) => throw const _ManagedConnectionStopped(),
      ),
    ]);
  }

  Future<void> cancel() => stop(disconnect: true);

  Future<void> stop({required bool disconnect}) async {
    if (_runFinished) {
      return;
    }
    _stopRequested = true;
    _disconnectWhenStopped = disconnect;
    if (!_stopSignal.isCompleted) {
      _stopSignal.complete();
    }
    await _reporting;

    final error = _stopError;
    if (error != null) {
      Error.throwWithStackTrace(error, _stopStackTrace ?? StackTrace.current);
    }
  }
}

class _ManagedConnectionStopped implements Exception {
  const _ManagedConnectionStopped();
}
