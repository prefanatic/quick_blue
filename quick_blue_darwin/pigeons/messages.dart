import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'quick_blue_darwin',
    input: 'pigeons/messages.dart',
    swiftOut:
        'darwin/quick_blue_darwin/Sources/quick_blue_darwin/Messages.g.swift',
    dartOut: 'lib/src/messages.g.dart',
  ),
)
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

class Peripheral {
  Peripheral({required this.id, required this.name});

  final String id;
  final String name;
}

@HostApi()
abstract class QuickBlueApi {
  List<Peripheral> getConnectedPeripherals(List<String> serviceUuids);
  bool isBluetoothAvailable();
  void startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
    int? rssi,
    PlatformDarwinScanOptions? options,
  });
  void stopScan();
  void connect(String deviceId);
  void disconnect(String deviceId);

  void discoverServices(String deviceId);
  void setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    PlatformBleInputProperty bleInputProperty,
  );
  void readValue(String deviceId, String service, String characteristic);

  // Async so the reply can be deferred until the peripheral acknowledges a
  // write-with-response (via didWriteValueFor). Writes-without-response have no
  // acknowledgement and complete as soon as they are handed to CoreBluetooth.
  @async
  void writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    PlatformBleOutputProperty bleOutputProperty,
  );

  // CoreBluetooth negotiates the ATT MTU automatically at connection time and
  // exposes no API to request a specific value, so [expectedMtu] is advisory.
  // Returns the negotiated ATT MTU currently in effect for the peripheral.
  int requestMtu(String deviceId, int expectedMtu);

  void openL2cap(String deviceId, int psm);
  void closeL2cap(String deviceId);
  void writeL2cap(String deviceId, Uint8List value);
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
  });

  final String deviceId;
  final PlatformConnectionState state;
  final PlatformGattStatus gattStatus;
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

@EventChannelApi()
abstract class QuickBlueEventApi {
  PlatformBluetoothState bluetoothState();
  PlatformScanResult scanResults();
  PlatformL2CapSocketEvent l2CapSocketEvents();
}

@FlutterApi()
abstract class QuickBlueFlutterApi {
  void onConnectionStateChange(PlatformConnectionStateChange stateChange);
  void onServiceDiscovered(PlatformServiceDiscovered serviceDiscovered);
  void onServiceDiscoveryComplete(String deviceId);
  void onCharacteristicValueChanged(
    PlatformCharacteristicValueChanged valueChanged,
  );
}
