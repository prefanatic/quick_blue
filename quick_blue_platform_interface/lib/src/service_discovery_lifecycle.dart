import 'dart:async';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import '../models.dart';
import 'quick_blue_exception.dart';
import 'service_discovery_event.dart';

@internal
class ServiceDiscoveryLifecycleCoordinator {
  ServiceDiscoveryLifecycleCoordinator({required this.startDiscovery});

  final Future<void> Function(String deviceId) startDiscovery;

  final _serviceController = StreamController<BluetoothService>.broadcast();
  final _completeController = StreamController<String>.broadcast();
  final _eventController = StreamController<ServiceDiscoveryEvent>.broadcast();
  final _pendingDiscoveries = <String, _ServiceDiscoveryOperation>{};

  Stream<BluetoothService> get serviceStream => _serviceController.stream;

  Stream<String> get completeStream => _completeController.stream;

  void handleDiscovered(
    String deviceId,
    String serviceId,
    List<String> characteristicIds,
    List<BluetoothCharacteristicInfo>? characteristicDetails,
  ) {
    final details =
        characteristicDetails ??
        characteristicIds
            .map((uuid) => BluetoothCharacteristicInfo(uuid: uuid))
            .toList(growable: false);
    final service = BluetoothService(
      deviceId: deviceId,
      uuid: serviceId,
      characteristics: characteristicIds,
      characteristicDetails: details,
    );

    _eventController.add(ServiceDiscoveredEvent(deviceId, service));
    _serviceController.add(service);
  }

  void handleComplete(String deviceId) {
    _eventController.add(ServiceDiscoveryCompleteEvent(deviceId));
    _completeController.add(deviceId);
  }

  void handleDisconnected(String deviceId) {
    _cancelPending(
      deviceId,
      message:
          'Service discovery for Bluetooth device $deviceId was cancelled '
          'because the device disconnected.',
    );
  }

  void handleGattServicesChanged(String deviceId) {
    _cancelPending(
      deviceId,
      message:
          'Service discovery for Bluetooth device $deviceId was cancelled '
          'because its GATT service database changed.',
    );
  }

  void _cancelPending(String deviceId, {required String message}) {
    final operation = _pendingDiscoveries.remove(deviceId);
    if (operation == null) {
      return;
    }
    final error = QuickBlueException(
      code: QuickBlueErrorCode.cancelled,
      operation: 'discoverServices',
      deviceId: deviceId,
      message: message,
    );
    operation.cancel(error);
    _eventController.add(
      _ServiceDiscoveryCancelledEvent(deviceId, operation, error),
    );
  }

  Future<List<BluetoothService>> discover(String deviceId) {
    final pending = _pendingDiscoveries[deviceId];
    if (pending != null) {
      return pending.completed;
    }

    final operation = _ServiceDiscoveryOperation(deviceId);
    _pendingDiscoveries[deviceId] = operation;
    operation.completed = () async {
      try {
        return await _run(deviceId, operation);
      } finally {
        if (identical(_pendingDiscoveries[deviceId], operation)) {
          _pendingDiscoveries.remove(deviceId);
        }
      }
    }();
    return operation.completed;
  }

  Future<List<BluetoothService>> _run(
    String deviceId,
    _ServiceDiscoveryOperation operation,
  ) async {
    final services = <BluetoothService>[];
    final events = StreamQueue(_events(deviceId));

    try {
      await operation.untilCancelled(startDiscovery(deviceId));

      while (await events.hasNext) {
        switch (await events.next) {
          case ServiceDiscoveredEvent(:final service):
            services.add(service);
          case ServiceDiscoveryCompleteEvent():
            return List<BluetoothService>.unmodifiable(services);
          case _ServiceDiscoveryCancelledEvent(
            :final cancelledOperation,
            :final error,
          ):
            if (identical(cancelledOperation, operation)) {
              throw error;
            }
        }
      }

      throw QuickBlueException(
        code: QuickBlueErrorCode.operationFailed,
        operation: 'discoverServices',
        deviceId: deviceId,
        message:
            'Service discovery ended before completion for Bluetooth device '
            '$deviceId.',
      );
    } finally {
      await events.cancel();
    }
  }

  Stream<ServiceDiscoveryEvent> _events(String deviceId) {
    return _eventController.stream.where((event) => event.deviceId == deviceId);
  }
}

class _ServiceDiscoveryOperation {
  _ServiceDiscoveryOperation(this.deviceId);

  final String deviceId;
  final _cancelled = Completer<QuickBlueException>();
  late final Future<List<BluetoothService>> completed;

  void cancel(QuickBlueException error) {
    if (!_cancelled.isCompleted) {
      _cancelled.complete(error);
    }
  }

  Future<T> untilCancelled<T>(Future<T> operation) {
    return Future.any<T>(<Future<T>>[
      operation,
      _cancelled.future.then<T>((error) => throw error),
    ]);
  }
}

class _ServiceDiscoveryCancelledEvent extends ServiceDiscoveryEvent {
  const _ServiceDiscoveryCancelledEvent(
    super.deviceId,
    this.cancelledOperation,
    this.error,
  );

  final _ServiceDiscoveryOperation cancelledOperation;
  final QuickBlueException error;
}
