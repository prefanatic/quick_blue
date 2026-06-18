import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

class QuickBlueAndroid extends QuickBluePlatform {
  QuickBlueAndroid();

  final messages.QuickBlueApi _api = messages.QuickBlueApi();
  messages.QuickBlueFlutterApi? _flutterApi;
  late final Stream<BlueBluetoothState> _bluetoothStateStream = messages
      .bluetoothState()
      .map((state) => state.toBlueBluetoothState())
      .distinct();

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueAndroid();
  }

  void _ensureInitialized() {
    if (_flutterApi != null) return;
    _flutterApi = _FlutterApi(this);
    messages.QuickBlueFlutterApi.setUp(_flutterApi);
  }

  @override
  Future<bool> isCompanionAssociationSupported() {
    _ensureInitialized();

    return _api.isCompanionAssociationSupported();
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    _ensureInitialized();

    final association = await _api.companionAssociate(
      messages.PlatformCompanionAssociationRequest(
        filters: request.filters.map(_toPlatformBleCompanionFilter).toList(),
        singleDevice: request.singleDevice,
      ),
    );
    return association == null ? null : _toCompanionAssociation(association);
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    _ensureInitialized();

    return _api.companionDisassociate(associationId);
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) async {
    _ensureInitialized();

    final deviceIds = await _api.connectedDeviceIds(serviceUuids);
    return deviceIds.map(device).toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) {
    _ensureInitialized();

    return _api.connect(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) {
    _ensureInitialized();

    return _api.disconnect(deviceId);
  }

  @override
  Future<void> discoverServices(String deviceId) {
    _ensureInitialized();

    return _api.discoverServices(deviceId);
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    _ensureInitialized();

    final associations = await _api.getCompanionAssociations();
    return associations.map(_toCompanionAssociation).toList(growable: false);
  }

  @override
  Future<bool> isBluetoothAvailable() {
    _ensureInitialized();

    return _api.isBluetoothAvailable();
  }

  @override
  Stream<BlueBluetoothState> get bluetoothStateStream {
    _ensureInitialized();

    return _bluetoothStateStream;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    _ensureInitialized();

    await _api.openL2cap(deviceId, psm);

    return BleL2capSocket(
      sink: _L2capSink(api: _api, deviceId: deviceId),
      stream: messages
          .l2CapSocketEvents()
          .where((event) => event.deviceId == deviceId)
          .map((e) {
            if (e.data != null) {
              return BleL2CapSocketEventData(
                deviceId: e.deviceId,
                data: e.data!,
              );
            } else if (e.error != null) {
              return BleL2CapSocketEventError(
                deviceId: e.deviceId,
                error: e.error,
              );
            } else if (e.opened == true) {
              return BleL2CapSocketEventOpened(deviceId: e.deviceId);
            } else if (e.closed == true) {
              return BleL2CapSocketEventClosed(deviceId: e.deviceId);
            }

            throw Exception('Unknown L2CAP event: $e');
          }),
    );
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    _ensureInitialized();

    return _api.readValue(deviceId, service, characteristic);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    _ensureInitialized();

    return _api.requestMtu(deviceId, expectedMtu);
  }

  @override
  Stream<BlueScanResult> get scanResultStream => messages.scanResults().map(
    (item) => BlueScanResult(
      deviceId: item.deviceId,
      name: item.name,
      rssi: item.rssi,
      serviceUuids: item.serviceUuids,
      manufacturerDataHead: item.manufacturerDataHead,
      manufacturerData: item.manufacturerData,
      serviceData: item.serviceData,
    ),
  );

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    _ensureInitialized();

    return _api.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty.toPlatformBleInputProperty(),
    );
  }

  @override
  Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) {
    _ensureInitialized();

    return _api.startScan(
      serviceUuids: scanFilter.serviceUuids,
      manufacturerData: scanFilter.manufacturerData,
    );
  }

  @override
  Future<void> stopScan() {
    _ensureInitialized();

    return _api.stopScan();
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    _ensureInitialized();

    return _api.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty.toPlatformBleOutputProperty(),
    );
  }
}

messages.PlatformBleCompanionFilter _toPlatformBleCompanionFilter(
  BleCompanionFilter filter,
) {
  return messages.PlatformBleCompanionFilter(
    deviceId: filter.deviceId,
    namePattern: filter.namePattern,
    serviceUuids: filter.serviceUuids,
    manufacturerData: filter.manufacturerData,
  );
}

CompanionAssociation _toCompanionAssociation(
  messages.PlatformCompanionAssociation association,
) {
  return CompanionAssociation(
    id: association.id,
    deviceId: association.deviceId,
    displayName: association.displayName,
    deviceProfile: association.deviceProfile,
  );
}

class _L2capSink implements EventSink<Uint8List> {
  _L2capSink({required this.api, required this.deviceId});

  final messages.QuickBlueApi api;
  final String deviceId;

  @override
  void add(Uint8List event) {
    api.writeL2cap(deviceId, event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future close() async {}
}

class _FlutterApi extends messages.QuickBlueFlutterApi {
  _FlutterApi(this.platform);

  final QuickBlueAndroid platform;

  @override
  void onCharacteristicValueChanged(
    messages.PlatformCharacteristicValueChanged valueChanged,
  ) {
    platform.handleCharacteristicValueChanged(
      valueChanged.deviceId,
      valueChanged.serviceUuid,
      valueChanged.characteristicId,
      valueChanged.value,
    );
  }

  @override
  void onConnectionStateChange(
    messages.PlatformConnectionStateChange stateChange,
  ) {
    final state = switch (stateChange.state) {
      messages.PlatformConnectionState.disconnected =>
        BlueConnectionState.disconnected,
      messages.PlatformConnectionState.connected =>
        BlueConnectionState.connected,
      _ => null,
    };
    if (state == null) return;

    platform.onConnectionChanged?.call(
      stateChange.deviceId,
      state,
      stateChange.gattStatus.toBleStatus(),
    );
  }

  @override
  void onServiceDiscovered(
    messages.PlatformServiceDiscovered serviceDiscovered,
  ) {
    platform.handleServiceDiscovered(
      serviceDiscovered.deviceId,
      serviceDiscovered.serviceUuid,
      serviceDiscovered.characteristics
          .map(
            (characteristic) => characteristic.toBluetoothCharacteristicInfo(),
          )
          .toList(growable: false),
    );
  }

  @override
  void onServiceDiscoveryComplete(String deviceId) {
    platform.onServiceDiscoveryComplete(deviceId);
  }
}

extension _PlatformCharacteristicExtension on messages.PlatformCharacteristic {
  BluetoothCharacteristicInfo toBluetoothCharacteristicInfo() {
    return BluetoothCharacteristicInfo(
      uuid: uuid,
      canRead: canRead,
      canWriteWithResponse: canWriteWithResponse,
      canWriteWithoutResponse: canWriteWithoutResponse,
      canNotify: canNotify,
      canIndicate: canIndicate,
    );
  }
}

extension _BleInputPropertyExtension on BleInputProperty {
  messages.PlatformBleInputProperty toPlatformBleInputProperty() {
    if (this == BleInputProperty.disabled) {
      return messages.PlatformBleInputProperty.disabled;
    } else if (this == BleInputProperty.notification) {
      return messages.PlatformBleInputProperty.notification;
    } else if (this == BleInputProperty.indication) {
      return messages.PlatformBleInputProperty.indication;
    } else {
      throw ArgumentError('Unknown BleInputProperty: $this');
    }
  }
}

extension _BleOutputPropertyExtension on BleOutputProperty {
  messages.PlatformBleOutputProperty toPlatformBleOutputProperty() {
    if (this == BleOutputProperty.withResponse) {
      return messages.PlatformBleOutputProperty.withResponse;
    } else if (this == BleOutputProperty.withoutResponse) {
      return messages.PlatformBleOutputProperty.withoutResponse;
    } else {
      throw ArgumentError('Unknown BleOutputProperty: $this');
    }
  }
}

extension _BleStatusExtension on messages.PlatformGattStatus {
  BleStatus toBleStatus() {
    switch (this) {
      case messages.PlatformGattStatus.success:
        return BleStatus.success;
      case messages.PlatformGattStatus.failure:
        return BleStatus.failure;
    }
  }
}

extension _BluetoothStateExtension on messages.PlatformBluetoothState {
  BlueBluetoothState toBlueBluetoothState() {
    switch (this) {
      case messages.PlatformBluetoothState.unknown:
        return BlueBluetoothState.unknown;
      case messages.PlatformBluetoothState.unavailable:
        return BlueBluetoothState.unavailable;
      case messages.PlatformBluetoothState.unauthorized:
        return BlueBluetoothState.unauthorized;
      case messages.PlatformBluetoothState.poweredOff:
        return BlueBluetoothState.poweredOff;
      case messages.PlatformBluetoothState.poweredOn:
        return BlueBluetoothState.poweredOn;
    }
  }
}
