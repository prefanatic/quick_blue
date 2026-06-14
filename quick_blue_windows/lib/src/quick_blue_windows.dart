import 'package:flutter/services.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

class QuickBlueWindows extends QuickBluePlatform {
  QuickBlueWindows();

  static const EventChannel _scanResults = EventChannel(
    'quick_blue/event.scanResult',
  );

  final messages.QuickBlueApi _api = messages.QuickBlueApi();
  messages.QuickBlueFlutterApi? _flutterApi;

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueWindows();
  }

  void _ensureInitialized() {
    if (_flutterApi != null) return;
    _flutterApi = _FlutterApi(
      onConnectionChangedCallback: (deviceId, state, status) {
        onConnectionChanged?.call(deviceId, state, status);
      },
      onServiceDiscoveredCallback: (deviceId, serviceId, characteristics) {
        handleServiceDiscovered(deviceId, serviceId, characteristics);
      },
      onServiceDiscoveryCompleteCallback: (deviceId) {
        onServiceDiscoveryComplete(deviceId);
      },
      onValueChangedCallback: (deviceId, serviceId, characteristicId, value) {
        handleCharacteristicValueChanged(
          deviceId,
          serviceId,
          characteristicId,
          value,
        );
      },
    );
    messages.QuickBlueFlutterApi.setUp(_flutterApi);
  }

  static const _companionUnsupported =
      'Companion device association is not supported on Windows.';

  @override
  Future<bool> isCompanionAssociationSupported() async => false;

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    throw UnsupportedError(_companionUnsupported);
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    throw UnsupportedError(_companionUnsupported);
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    throw UnsupportedError(_companionUnsupported);
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
  Future<bool> isBluetoothAvailable() {
    _ensureInitialized();
    return _api.isBluetoothAvailable();
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) {
    throw UnsupportedError('L2CAP sockets are not supported on Windows.');
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
  Stream<BlueScanResult> get scanResultStream => _scanResults
      .receiveBroadcastStream({'name': 'scanResult'})
      .map((item) => BlueScanResult.fromMap(item));

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

class _FlutterApi extends messages.QuickBlueFlutterApi {
  _FlutterApi({
    required this.onConnectionChangedCallback,
    required this.onServiceDiscoveredCallback,
    required this.onServiceDiscoveryCompleteCallback,
    required this.onValueChangedCallback,
  });

  final OnConnectionChanged onConnectionChangedCallback;
  final void Function(
    String deviceId,
    String serviceId,
    List<BluetoothCharacteristicInfo> characteristics,
  )
  onServiceDiscoveredCallback;
  final OnServiceDiscoveryComplete onServiceDiscoveryCompleteCallback;
  final void Function(
    String deviceId,
    String serviceId,
    String characteristicId,
    Uint8List value,
  )
  onValueChangedCallback;

  @override
  void onCharacteristicValueChanged(
    messages.PlatformCharacteristicValueChanged valueChanged,
  ) {
    onValueChangedCallback.call(
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

    onConnectionChangedCallback.call(
      stateChange.deviceId,
      state,
      stateChange.gattStatus.toBleStatus(),
    );
  }

  @override
  void onServiceDiscovered(
    messages.PlatformServiceDiscovered serviceDiscovered,
  ) {
    onServiceDiscoveredCallback.call(
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
    onServiceDiscoveryCompleteCallback.call(deviceId);
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
    return switch (this) {
      BleInputProperty.disabled => messages.PlatformBleInputProperty.disabled,
      BleInputProperty.notification =>
        messages.PlatformBleInputProperty.notification,
      BleInputProperty.indication =>
        messages.PlatformBleInputProperty.indication,
      _ => throw ArgumentError('Unknown BleInputProperty: $this'),
    };
  }
}

extension _BleOutputPropertyExtension on BleOutputProperty {
  messages.PlatformBleOutputProperty toPlatformBleOutputProperty() {
    return switch (this) {
      BleOutputProperty.withResponse =>
        messages.PlatformBleOutputProperty.withResponse,
      BleOutputProperty.withoutResponse =>
        messages.PlatformBleOutputProperty.withoutResponse,
      _ => throw ArgumentError('Unknown BleOutputProperty: $this'),
    };
  }
}

extension _BleStatusExtension on messages.PlatformGattStatus {
  BleStatus toBleStatus() {
    return switch (this) {
      messages.PlatformGattStatus.success => BleStatus.success,
      messages.PlatformGattStatus.failure => BleStatus.failure,
    };
  }
}
