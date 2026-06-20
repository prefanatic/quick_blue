import 'dart:typed_data';

import '../models.dart';

/// Legacy callback for device connection changes.
typedef OnConnectionChanged =
    void Function(String deviceId, BlueConnectionState state, BleStatus status);

/// Legacy callback for discovered GATT services.
typedef OnServiceDiscovered =
    void Function(
      String deviceId,
      String serviceId,
      List<String> characteristicIds,
    );

/// Legacy callback for characteristic value changes.
typedef OnValueChanged =
    void Function(String deviceId, String characteristicId, Uint8List value);

/// Callback for service discovery completion.
typedef OnServiceDiscoveryComplete = void Function(String deviceId);
