/// Coordinates clients of a process-wide Linux Bluetooth connection.
/// Lease identifiers are opaque; Linux combines local adapter and remote address.
abstract interface class QuickBlueLinuxConnectionLease {
  Future<void> attach(String deviceId);

  /// Detaches this client and runs [onLastClient] while new clients are blocked
  /// when no other Flutter engine remains attached.
  Future<void> detach(String deviceId, Future<void> Function() onLastClient);
}

/// Tracks the device leases held by one Linux Flutter-engine instance.
abstract interface class QuickBlueLinuxDisposableConnectionLease {
  Future<void> close();
}

class ConnectionOwnership {
  ConnectionOwnership(this._lease);

  final QuickBlueLinuxConnectionLease _lease;
  final Map<String, String> _leaseIds = <String, String>{};
  final Set<String> _membershipUncertain = <String>{};
  final Map<String, ({String identity, Future<void> completion})> _attaching =
      {};
  final Map<String, Future<void>> _detaching = <String, Future<void>>{};

  List<String> get deviceIds => List.unmodifiable(_leaseIds.keys);

  Future<void> close() async {
    if (_lease case final QuickBlueLinuxDisposableConnectionLease lease) {
      await lease.close();
    }
  }

  bool owns(String deviceId) => _leaseIds.containsKey(deviceId);

  Future<void> attach(
    String deviceId, {
    String? leaseId,
    bool Function()? isCurrent,
  }) {
    if (isCurrent != null && !isCurrent()) return Future<void>.value();
    final detaching = _detaching[deviceId];
    if (detaching != null) {
      return detaching.then(
        (_) => attach(deviceId, leaseId: leaseId, isCurrent: isCurrent),
      );
    }
    if (_leaseIds.containsKey(deviceId) &&
        !_membershipUncertain.contains(deviceId)) {
      return Future<void>.value();
    }
    // A failed detach can have released the real Client name before failing
    // its final unlock reply. Retained cleanup identity is not live membership.
    final pending = _attaching.putIfAbsent(deviceId, () {
      final identity = _leaseIds[deviceId] ?? leaseId ?? deviceId;
      return (
        identity: identity,
        completion: Future<void>.microtask(() => _attach(deviceId, identity)),
      );
    });
    return _settleAttach(deviceId, pending, isCurrent);
  }

  Future<void> _attach(String deviceId, String identity) async {
    try {
      await _lease.attach(identity);
      _leaseIds[deviceId] = identity;
      _membershipUncertain.remove(deviceId);
    } finally {
      _attaching.remove(deviceId);
    }
  }

  Future<void> _settleAttach(
    String deviceId,
    ({String identity, Future<void> completion}) pending,
    bool Function()? isCurrent,
  ) async {
    await pending.completion;
    // A native callback may request detach during registration. Detach waits
    // only for the raw lease operation, not this waiter (which would deadlock).
    // Its successful cleanup invalidates registration, so restore membership
    // before completing the original attach request. Errors remain observable.
    // Raw registration still records its identity for waiting detach cleanup.
    // Only a live requester may restore membership after that detach settles.
    await attach(deviceId, leaseId: pending.identity, isCurrent: isCurrent);
  }

  Future<void> detach(
    String deviceId, {
    required Future<void> Function() onLastClient,
    void Function()? onStart,
  }) {
    if (!_leaseIds.containsKey(deviceId) && !_attaching.containsKey(deviceId)) {
      return Future<void>.value();
    }
    final attaching = _attaching[deviceId]?.completion;
    return _detaching.putIfAbsent(deviceId, () {
      // Reentrant callbacks join cleanup; they must not retire a connect that
      // is already waiting for this same teardown to finish.
      onStart?.call();
      return Future<void>.microtask(
        () => _detach(deviceId, attaching, onLastClient),
      );
    });
  }

  Future<void> _detach(
    String deviceId,
    Future<void>? attaching,
    Future<void> Function() onLastClient,
  ) async {
    // Keep identity visible until teardown settles. Native disconnect events
    // can reenter detach while the final D-Bus unlock reply is still pending.
    try {
      // D-Bus alreadyOwner does not serialize operations on the same bus client.
      await attaching;
      final identity = _leaseIds[deviceId]!;
      _membershipUncertain.add(deviceId);
      await _lease.detach(identity, onLastClient);
      _leaseIds.remove(deviceId);
      _membershipUncertain.remove(deviceId);
    } finally {
      _detaching.remove(deviceId);
    }
  }
}
