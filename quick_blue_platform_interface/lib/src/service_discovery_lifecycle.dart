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
  final _pendingDiscoveries = <String, Future<List<BluetoothService>>>{};

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

  Future<List<BluetoothService>> discover(String deviceId) {
    final pending = _pendingDiscoveries[deviceId];
    if (pending != null) {
      return pending;
    }

    late Future<List<BluetoothService>> discovery;
    discovery = () async {
      try {
        return await _run(deviceId);
      } finally {
        if (identical(_pendingDiscoveries[deviceId], discovery)) {
          _pendingDiscoveries.remove(deviceId);
        }
      }
    }();
    _pendingDiscoveries[deviceId] = discovery;
    return discovery;
  }

  Future<List<BluetoothService>> _run(String deviceId) async {
    final services = <BluetoothService>[];
    final events = StreamQueue(_events(deviceId));

    try {
      await startDiscovery(deviceId);

      while (await events.hasNext) {
        switch (await events.next) {
          case ServiceDiscoveredEvent(:final service):
            services.add(service);
          case ServiceDiscoveryCompleteEvent():
            return List<BluetoothService>.unmodifiable(services);
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
