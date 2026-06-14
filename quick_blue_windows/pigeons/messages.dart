import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'quick_blue_windows',
    input: 'pigeons/messages.dart',
    dartOut: 'lib/src/messages.g.dart',
    cppOptions: CppOptions(namespace: 'quick_blue_windows'),
    cppHeaderOut: 'windows/messages.g.h',
    cppSourceOut: 'windows/messages.g.cpp',
  ),
)
enum PlatformBleInputProperty { disabled, notification, indication }

enum PlatformBleOutputProperty { withResponse, withoutResponse }

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

@HostApi()
abstract class QuickBlueApi {
  bool isBluetoothAvailable();
  void startScan({
    List<String>? serviceUuids,
    Map<int, Uint8List>? manufacturerData,
  });
  void stopScan();
  List<String> connectedDeviceIds(List<String> serviceUuids);
  void connect(String deviceId);
  void disconnect(String deviceId);

  @async
  void discoverServices(String deviceId);

  @async
  void setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    PlatformBleInputProperty bleInputProperty,
  );

  @async
  void readValue(String deviceId, String service, String characteristic);

  @async
  void writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    PlatformBleOutputProperty bleOutputProperty,
  );

  @async
  int requestMtu(String deviceId, int expectedMtu);
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
