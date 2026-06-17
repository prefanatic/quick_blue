import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    input: 'pigeons/messages.dart',
    kotlinOut: 'android/src/main/kotlin/com/example/quick_blue/Messages.g.kt',
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

class PlatformBleCompanionFilter {
  PlatformBleCompanionFilter({
    this.deviceId,
    this.namePattern,
    required this.serviceUuids,
    this.manufacturerData,
  });

  final String? deviceId;
  final String? namePattern;
  final List<String> serviceUuids;
  final Map<int, Uint8List>? manufacturerData;
}

class PlatformCompanionAssociationRequest {
  PlatformCompanionAssociationRequest({
    required this.filters,
    required this.singleDevice,
  });

  final List<PlatformBleCompanionFilter> filters;
  final bool singleDevice;
}

class PlatformCompanionAssociation {
  PlatformCompanionAssociation({
    required this.id,
    this.deviceId,
    this.displayName,
    this.deviceProfile,
  });

  final int id;
  final String? deviceId;
  final String? displayName;
  final String? deviceProfile;
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
  bool isCompanionAssociationSupported();
  @async
  PlatformCompanionAssociation? companionAssociate(
    PlatformCompanionAssociationRequest request,
  );
  void companionDisassociate(int associationId);
  List<PlatformCompanionAssociation> getCompanionAssociations();
  void discoverServices(String deviceId);
  // Async so the reply can be deferred until the CCCD descriptor write
  // completes (onDescriptorWrite) rather than when the write is merely queued.
  @async
  void setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    PlatformBleInputProperty bleInputProperty,
  );
  void readValue(String deviceId, String service, String characteristic);

  // Async so the reply can be deferred until the GATT write completes
  // (onCharacteristicWrite) rather than when the write is merely queued.
  @async
  void writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    PlatformBleOutputProperty bleOutputProperty,
  );
  int requestMtu(String deviceId, int expectedMtu);

  @async
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

class PlatformMtuChange {
  PlatformMtuChange({required this.deviceId, required this.mtu});

  final String deviceId;
  final int mtu;
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
  PlatformMtuChange mtuChanged();
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
