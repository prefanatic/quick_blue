/// Acquires process-wide ownership of a Linux Bluetooth connection.
abstract interface class QuickBlueLinuxConnectionLease {
  Future<bool> claim(String deviceId);
  Future<void> release(String deviceId);
}

/// Tracks the device leases held by one Linux Flutter-engine instance.
class ConnectionOwnership {
  ConnectionOwnership(this._lease);

  final QuickBlueLinuxConnectionLease _lease;
  final Set<String> _deviceIds = <String>{};

  bool owns(String deviceId) => _deviceIds.contains(deviceId);

  Future<bool> claim(String deviceId) async {
    if (_deviceIds.contains(deviceId)) {
      return true;
    }
    if (!await _lease.claim(deviceId)) {
      return false;
    }
    _deviceIds.add(deviceId);
    return true;
  }

  Future<void> release(String deviceId) async {
    if (!_deviceIds.remove(deviceId)) {
      return;
    }
    try {
      await _lease.release(deviceId);
    } catch (_) {
      _deviceIds.add(deviceId);
      rethrow;
    }
  }
}
