import 'dart:async';

import 'package:meta/meta.dart';

/// Availability of Bluetooth LE Channel Sounding on the current device.
enum BleRangingAvailability {
  /// Channel Sounding is available for foreground use.
  available,

  /// The operating system or Bluetooth controller does not support it.
  unsupported,

  /// The user disabled the underlying ranging capability.
  disabledByUser,

  /// Ranging is unavailable because of local regulatory restrictions.
  disabledByRegulation,

  /// Device policy or another system restriction disabled ranging.
  restricted,
}

/// Preferred interval between Channel Sounding measurements.
enum BleRangingUpdateRate {
  /// Favor lower power use over update frequency.
  infrequent,

  /// Use the platform's normal update frequency.
  normal,

  /// Favor responsiveness over power use.
  frequent,
}

/// Platform-reported confidence in an individual ranging value.
enum BleRangingConfidence {
  /// The platform did not provide confidence information.
  unknown,

  /// The platform reported low confidence.
  low,

  /// The platform reported medium confidence.
  medium,

  /// The platform reported high confidence.
  high,
}

/// Local Bluetooth LE Channel Sounding capabilities.
class BleRangingCapabilities {
  const BleRangingCapabilities({
    required this.availability,
    required this.supportsDirection,
  });

  /// Capabilities used by platforms without a public Channel Sounding API.
  static const unsupported = BleRangingCapabilities(
    availability: BleRangingAvailability.unsupported,
    supportsDirection: false,
  );

  /// Current Channel Sounding availability.
  final BleRangingAvailability availability;

  /// Whether sessions can request directional measurements.
  ///
  /// Direction support may depend on non-Bluetooth sensors. On iOS, for
  /// example, direction uses Nearby Interaction camera assistance.
  final bool supportsDirection;

  /// Whether Channel Sounding can currently be started.
  bool get isAvailable => availability == BleRangingAvailability.available;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleRangingCapabilities &&
            other.availability == availability &&
            other.supportsDirection == supportsDirection;
  }

  @override
  int get hashCode => Object.hash(availability, supportsDirection);

  @override
  String toString() {
    return 'BleRangingCapabilities('
        'availability: $availability, '
        'supportsDirection: $supportsDirection'
        ')';
  }
}

/// Options for a Bluetooth LE Channel Sounding session.
class BleRangingOptions {
  const BleRangingOptions({
    this.requestDirection = false,
    this.updateRate = BleRangingUpdateRate.normal,
  });

  /// Whether to request direction in addition to distance.
  ///
  /// Check [BleRangingCapabilities.supportsDirection] before enabling this.
  /// Unsupported direction requests fail instead of silently returning only
  /// distance.
  final bool requestDirection;

  /// Preferred measurement update rate.
  ///
  /// Platforms may reduce the effective rate because of power, radio
  /// contention, thermal state, or system policy.
  final BleRangingUpdateRate updateRate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleRangingOptions &&
            other.requestDirection == requestDirection &&
            other.updateRate == updateRate;
  }

  @override
  int get hashCode => Object.hash(requestDirection, updateRate);

  @override
  String toString() {
    return 'BleRangingOptions('
        'requestDirection: $requestDirection, '
        'updateRate: $updateRate'
        ')';
  }
}

/// One Bluetooth LE Channel Sounding measurement.
class BleRangingMeasurement {
  const BleRangingMeasurement({
    required this.deviceId,
    required this.timestamp,
    this.distanceMeters,
    this.azimuthDegrees,
    this.elevationDegrees,
    this.rssi,
    this.distanceConfidence = BleRangingConfidence.unknown,
    this.azimuthConfidence = BleRangingConfidence.unknown,
    this.elevationConfidence = BleRangingConfidence.unknown,
  });

  /// Platform-specific identifier of the ranged device.
  final String deviceId;

  /// Time the measurement reached Dart.
  final DateTime timestamp;

  /// Measured distance in meters, or `null` when the procedure had no result.
  final double? distanceMeters;

  /// Horizontal direction in degrees, or `null` when unavailable.
  final double? azimuthDegrees;

  /// Vertical direction in degrees, or `null` when unavailable.
  final double? elevationDegrees;

  /// Received signal strength in dBm when the platform includes it.
  final int? rssi;

  /// Confidence in [distanceMeters].
  final BleRangingConfidence distanceConfidence;

  /// Confidence in [azimuthDegrees].
  final BleRangingConfidence azimuthConfidence;

  /// Confidence in [elevationDegrees].
  final BleRangingConfidence elevationConfidence;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleRangingMeasurement &&
            other.deviceId == deviceId &&
            other.timestamp == timestamp &&
            other.distanceMeters == distanceMeters &&
            other.azimuthDegrees == azimuthDegrees &&
            other.elevationDegrees == elevationDegrees &&
            other.rssi == rssi &&
            other.distanceConfidence == distanceConfidence &&
            other.azimuthConfidence == azimuthConfidence &&
            other.elevationConfidence == elevationConfidence;
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    timestamp,
    distanceMeters,
    azimuthDegrees,
    elevationDegrees,
    rssi,
    distanceConfidence,
    azimuthConfidence,
    elevationConfidence,
  );

  @override
  String toString() {
    return 'BleRangingMeasurement('
        'deviceId: $deviceId, '
        'timestamp: $timestamp, '
        'distanceMeters: $distanceMeters, '
        'azimuthDegrees: $azimuthDegrees, '
        'elevationDegrees: $elevationDegrees, '
        'rssi: $rssi, '
        'distanceConfidence: $distanceConfidence, '
        'azimuthConfidence: $azimuthConfidence, '
        'elevationConfidence: $elevationConfidence'
        ')';
  }
}

/// An active, initiator-role Bluetooth LE Channel Sounding session.
class BleRangingSession {
  @internal
  BleRangingSession.internal({
    required this.deviceId,
    required this.measurements,
    required Future<void> Function() stop,
  }) : _stop = stop;

  /// Platform-specific identifier of the ranged device.
  final String deviceId;

  /// Measurements and asynchronous session failures.
  ///
  /// This is a single-subscription stream. Call [stop] when the session is no
  /// longer needed, including after handling a stream error.
  final Stream<BleRangingMeasurement> measurements;

  final Future<void> Function() _stop;
  Future<void>? _stopFuture;

  /// Stops the native session and closes [measurements].
  ///
  /// Repeated calls share the first stop operation.
  Future<void> stop() => _stopFuture ??= _stop();
}
