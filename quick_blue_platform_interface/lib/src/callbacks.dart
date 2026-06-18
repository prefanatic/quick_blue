import 'dart:typed_data';

import '../models.dart';

typedef OnConnectionChanged =
    void Function(String deviceId, BlueConnectionState state, BleStatus status);

typedef OnServiceDiscovered =
    void Function(
      String deviceId,
      String serviceId,
      List<String> characteristicIds,
    );

typedef OnValueChanged =
    void Function(String deviceId, String characteristicId, Uint8List value);

typedef OnServiceDiscoveryComplete = void Function(String deviceId);
