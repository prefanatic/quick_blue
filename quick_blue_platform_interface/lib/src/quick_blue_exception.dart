/// Broad error categories used by [QuickBlueException].
enum QuickBlueErrorCode {
  /// The requested API is not supported by the active platform.
  unsupported,

  /// A required Bluetooth resource or capability is unavailable.
  unavailable,

  /// The requested operation cannot run in the current state.
  invalidState,

  /// The shared native connection is temporarily unavailable.
  ///
  /// This can occur while a previous connection is still disconnecting.
  deviceBusy,

  /// The operation failed after it was accepted by the platform.
  operationFailed,

  /// The requested Bluetooth resource was not found.
  notFound,

  /// The requested Bluetooth resource matched more than one candidate.
  ambiguous,

  /// The operation was superseded by a conflicting request from this client.
  cancelled,
}

/// Exception type for errors created by QuickBlue Dart code.
///
/// Platform implementations may translate native failures into this type when
/// a portable error category is available.
class QuickBlueException implements Exception {
  /// Creates a QuickBlue exception.
  const QuickBlueException({
    required this.code,
    required this.message,
    this.operation,
    this.deviceId,
    this.serviceId,
    this.characteristicId,
    this.details,
  });

  /// Machine-readable error category.
  final QuickBlueErrorCode code;

  /// Human-readable explanation of the failure.
  final String message;

  /// API or workflow that produced the error.
  final String? operation;

  /// Bluetooth device associated with the error, when known.
  final String? deviceId;

  /// GATT service associated with the error, when known.
  final String? serviceId;

  /// GATT characteristic associated with the error, when known.
  final String? characteristicId;

  /// Extra diagnostic context.
  final Object? details;

  @override
  String toString() {
    final context = <String>[
      if (operation != null) 'operation: $operation',
      if (deviceId != null) 'deviceId: $deviceId',
      if (serviceId != null) 'serviceId: $serviceId',
      if (characteristicId != null) 'characteristicId: $characteristicId',
      if (details != null) 'details: $details',
    ];
    final suffix = context.isEmpty ? '' : ' (${context.join(', ')})';
    return 'QuickBlueException(${code.name}: $message)$suffix';
  }
}

/// A GATT operation failure reported by the active native platform.
///
/// [status] is the unmodified numeric platform status. Callers should preserve
/// unknown values because Android devices may report vendor-specific statuses.
class QuickBlueGattException extends QuickBlueException {
  /// Creates a structured GATT operation failure.
  const QuickBlueGattException({
    required this.status,
    required super.message,
    required super.operation,
    super.deviceId,
    super.serviceId,
    super.characteristicId,
  }) : super(code: QuickBlueErrorCode.operationFailed, details: status);

  /// Raw numeric GATT status reported by the native platform.
  final int status;
}
