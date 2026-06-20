import '../models.dart';

/// Base class for service discovery events.
abstract class ServiceDiscoveryEvent {
  const ServiceDiscoveryEvent(this.deviceId);

  /// Platform-specific device identifier.
  final String deviceId;
}

/// Event emitted when a service is discovered.
class ServiceDiscoveredEvent extends ServiceDiscoveryEvent {
  const ServiceDiscoveredEvent(super.deviceId, this.service);

  /// The discovered service.
  final BluetoothService service;
}

/// Event emitted when service discovery completes.
class ServiceDiscoveryCompleteEvent extends ServiceDiscoveryEvent {
  const ServiceDiscoveryCompleteEvent(super.deviceId);
}
