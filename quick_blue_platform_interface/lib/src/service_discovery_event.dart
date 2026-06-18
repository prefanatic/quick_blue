import '../models.dart';

abstract class ServiceDiscoveryEvent {
  const ServiceDiscoveryEvent(this.deviceId);

  final String deviceId;
}

class ServiceDiscoveredEvent extends ServiceDiscoveryEvent {
  const ServiceDiscoveredEvent(super.deviceId, this.service);

  final BluetoothService service;
}

class ServiceDiscoveryCompleteEvent extends ServiceDiscoveryEvent {
  const ServiceDiscoveryCompleteEvent(super.deviceId);
}
