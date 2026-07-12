/// Coordinates clients of a process-wide Linux Bluetooth connection.
abstract interface class QuickBlueLinuxConnectionLease {
  Future<void> attach(String deviceId);

  /// Detaches this client and runs [onLastClient] while new clients are blocked
  /// when no other Flutter engine remains attached.
  Future<void> detach(String deviceId, Future<void> Function() onLastClient);
}

/// Tracks the device leases held by one Linux Flutter-engine instance.
class ConnectionOwnership {
  ConnectionOwnership(this._lease);

  final QuickBlueLinuxConnectionLease _lease;
  final Set<String> _deviceIds = <String>{};

  bool owns(String deviceId) => _deviceIds.contains(deviceId);

  Future<void> attach(String deviceId) async {
    if (_deviceIds.contains(deviceId)) {
      return;
    }
    await _lease.attach(deviceId);
    _deviceIds.add(deviceId);
  }

  Future<void> detach(
    String deviceId, {
    required Future<void> Function() onLastClient,
  }) async {
    if (!_deviceIds.remove(deviceId)) {
      return;
    }
    try {
      await _lease.detach(deviceId, onLastClient);
    } catch (_) {
      _deviceIds.add(deviceId);
      rethrow;
    }
  }
}
