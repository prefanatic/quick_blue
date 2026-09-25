// Copyright (c) 2026, the quick_blue authors.
// Use of this source code is governed by the BSD-3-Clause license.

import 'dart:typed_data';

enum PlatformBleInputProperty { disabled, notification, indication }

enum PlatformBleOutputProperty { withResponse, withoutResponse }

enum PlatformBluetoothState {
  unknown,
  unavailable,
  unauthorized,
  poweredOff,
  poweredOn,
}

class PlatformDarwinScanOptions {
  PlatformDarwinScanOptions({
    required this.allowDuplicates,
    required this.solicitedServiceUuids,
  });

  final bool allowDuplicates;
  final List<String> solicitedServiceUuids;
}

class PlatformDarwinConfiguration {
  PlatformDarwinConfiguration({required this.maintainState});

  final bool maintainState;
}

class PlatformDarwinRestorationEvent {
  PlatformDarwinRestorationEvent({
    required this.restoredPeripheralCount,
    required this.disconnectedPeripheralCount,
    required this.connectingPeripheralCount,
    required this.connectedPeripheralCount,
    required this.disconnectingPeripheralCount,
    required this.unknownPeripheralCount,
    required this.scanningRestored,
    required this.restoredScanServiceCount,
  });

  final int restoredPeripheralCount;
  final int disconnectedPeripheralCount;
  final int connectingPeripheralCount;
  final int connectedPeripheralCount;
  final int disconnectingPeripheralCount;
  final int unknownPeripheralCount;
  final bool scanningRestored;
  final int restoredScanServiceCount;
}

class PlatformAppleAccessoryDiscovery {
  PlatformAppleAccessoryDiscovery({
    required this.serviceUuid,
    this.nameSubstring,
    this.serviceData,
    this.serviceDataMask,
    required this.immediate,
  });

  final String serviceUuid;
  final String? nameSubstring;
  final Uint8List? serviceData;
  final Uint8List? serviceDataMask;
  final bool immediate;
}

class PlatformAppleAccessoryPickerItem {
  PlatformAppleAccessoryPickerItem({
    required this.displayName,
    required this.productImage,
    required this.discovery,
    this.migrationDeviceId,
  });

  final String displayName;
  final Uint8List productImage;
  final PlatformAppleAccessoryDiscovery discovery;
  final String? migrationDeviceId;
}

class PlatformAppleAccessory {
  PlatformAppleAccessory({required this.deviceId, required this.displayName});

  final String deviceId;
  final String displayName;
}

class Peripheral {
  Peripheral({required this.id, required this.name});

  final String id;
  final String name;
}

class PlatformScanResult {
  PlatformScanResult({
    required this.name,
    required this.deviceId,
    required this.manufacturerDataHead,
    required this.manufacturerData,
    required this.rssi,
    required this.serviceUuids,
    required this.serviceData,
  });

  final String name;
  final String deviceId;
  final Uint8List manufacturerDataHead;
  final Uint8List manufacturerData;
  final int rssi;
  final List<String> serviceUuids;
  final Map<String, Uint8List> serviceData;
}

enum PlatformConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  unknown,
}

enum PlatformGattStatus { success, failure }

class PlatformConnectionStateChange {
  PlatformConnectionStateChange({
    required this.deviceId,
    required this.state,
    required this.gattStatus,
    this.errorDomain,
    this.errorCode,
    this.errorMessage,
  });

  final String deviceId;
  final PlatformConnectionState state;
  final PlatformGattStatus gattStatus;
  final String? errorDomain;
  final int? errorCode;
  final String? errorMessage;
}

class PlatformServiceDiscovered {
  PlatformServiceDiscovered({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristics,
  });

  final String deviceId;
  final String serviceUuid;
  final List<PlatformCharacteristic> characteristics;
}

class PlatformCharacteristic {
  PlatformCharacteristic({
    required this.uuid,
    required this.canRead,
    required this.canWriteWithResponse,
    required this.canWriteWithoutResponse,
    required this.canNotify,
    required this.canIndicate,
  });

  final String uuid;
  final bool canRead;
  final bool canWriteWithResponse;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;
}

class PlatformCharacteristicValueChanged {
  PlatformCharacteristicValueChanged({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicId,
    required this.value,
  });

  final String deviceId;
  final String serviceUuid;
  final String characteristicId;
  final Uint8List value;
}

class PlatformL2CapSocketEvent {
  PlatformL2CapSocketEvent({
    required this.deviceId,
    this.data,
    this.error,
    this.opened,
    this.closed,
  });

  final String deviceId;
  final Uint8List? data;
  final String? error;
  final bool? opened;
  final bool? closed;
}
