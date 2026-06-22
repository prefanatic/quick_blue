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
  late final Stream<BlueScanResult> _scanResultStream = _scanResults
      .receiveBroadcastStream({'name': 'scanResult'})
      .map(_scanResultFromEvent);

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueWindows();
  }

  void _ensureInitialized() {
    if (_flutterApi != null) return;
    _flutterApi = _FlutterApi(this);
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
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'companionAssociate',
      message: _companionUnsupported,
    );
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'companionDisassociate',
      message: _companionUnsupported,
    );
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'getCompanionAssociations',
      message: _companionUnsupported,
    );
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
  Future<bool> isBluetoothAvailable() {
    _ensureInitialized();
    return _api.isBluetoothAvailable();
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'openL2cap',
      message: 'L2CAP sockets are not supported on Windows.',
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
  Stream<BlueScanResult> get scanResultStream => _scanResultStream;

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
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    _ensureInitialized();
    return _api.startScan(
      serviceUuids: scanFilter.serviceUuids,
      manufacturerData: scanFilter.manufacturerData,
      rssi: scanFilter.rssi,
      options: scanOptions.toPlatformWindowsScanOptions(scanFilter: scanFilter),
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

extension on ScanOptions {
  messages.PlatformWindowsScanOptions toPlatformWindowsScanOptions({
    required ScanFilter scanFilter,
  }) {
    return messages.PlatformWindowsScanOptions(
      scanningMode: (windows.scanningMode ?? scanMode?.toWindowsScanMode())
          ?.toPlatformWindowsScanMode(),
      signalStrengthFilter:
          windows.signalStrengthFilter
              ?.toPlatformWindowsSignalStrengthFilter() ??
          scanFilter.rssi?.toPlatformWindowsSignalStrengthFilter(),
    );
  }
}

extension on ScanMode {
  WindowsScanMode toWindowsScanMode() {
    return switch (this) {
      ScanMode.lowPower => WindowsScanMode.passive,
      ScanMode.balanced => WindowsScanMode.passive,
      ScanMode.lowLatency => WindowsScanMode.active,
    };
  }
}

extension on WindowsScanMode {
  messages.PlatformWindowsScanMode toPlatformWindowsScanMode() {
    return switch (this) {
      WindowsScanMode.passive => messages.PlatformWindowsScanMode.passive,
      WindowsScanMode.active => messages.PlatformWindowsScanMode.active,
      WindowsScanMode.none => messages.PlatformWindowsScanMode.none,
    };
  }
}

extension on WindowsSignalStrengthFilter {
  messages.PlatformWindowsSignalStrengthFilter
  toPlatformWindowsSignalStrengthFilter() {
    return messages.PlatformWindowsSignalStrengthFilter(
      inRangeThresholdInDBm: inRangeThresholdInDBm,
      outOfRangeThresholdInDBm: outOfRangeThresholdInDBm,
      outOfRangeTimeoutMillis: outOfRangeTimeout?.inMilliseconds,
      samplingIntervalMillis: samplingInterval?.inMilliseconds,
    );
  }
}

extension on int {
  messages.PlatformWindowsSignalStrengthFilter
  toPlatformWindowsSignalStrengthFilter() {
    return messages.PlatformWindowsSignalStrengthFilter(
      inRangeThresholdInDBm: this,
    );
  }
}

BlueScanResult _scanResultFromEvent(Object? item) {
  final map = Map<String, dynamic>.from(item as Map);
  final serviceData = map['serviceData'];
  if (serviceData is Map) {
    map['serviceData'] = serviceData.map(
      (key, value) => MapEntry(key as String, value as Uint8List),
    );
  }
  return BlueScanResult.fromMap(map);
}

class _FlutterApi extends messages.QuickBlueFlutterApi {
  _FlutterApi(this.platform);

  final QuickBlueWindows platform;

  @override
  void onCharacteristicValueChanged(
    messages.PlatformCharacteristicValueChanged valueChanged,
  ) {
    _handleCharacteristicValueChanged(platform, valueChanged);
  }

  @override
  void onConnectionStateChange(
    messages.PlatformConnectionStateChange stateChange,
  ) {
    _handleConnectionStateChange(platform, stateChange);
  }

  @override
  void onServiceDiscovered(
    messages.PlatformServiceDiscovered serviceDiscovered,
  ) {
    _handleServiceDiscovered(platform, serviceDiscovered);
  }

  @override
  void onServiceDiscoveryComplete(String deviceId) {
    platform.onServiceDiscoveryComplete(deviceId);
  }
}

void _handleCharacteristicValueChanged(
  QuickBluePlatform platform,
  messages.PlatformCharacteristicValueChanged valueChanged,
) {
  platform.handleCharacteristicValueChanged(
    valueChanged.deviceId,
    valueChanged.serviceUuid,
    valueChanged.characteristicId,
    valueChanged.value,
  );
}

void _handleConnectionStateChange(
  QuickBluePlatform platform,
  messages.PlatformConnectionStateChange stateChange,
) {
  final state = stateChange.state.toBlueConnectionState();
  if (state == null) return;

  platform.onConnectionChanged?.call(
    stateChange.deviceId,
    state,
    stateChange.gattStatus.toBleStatus(),
  );
}

void _handleServiceDiscovered(
  QuickBluePlatform platform,
  messages.PlatformServiceDiscovered serviceDiscovered,
) {
  platform.handleServiceDiscovered(
    serviceDiscovered.deviceId,
    serviceDiscovered.serviceUuid,
    serviceDiscovered.characteristics
        .map((characteristic) => characteristic.toBluetoothCharacteristicInfo())
        .toList(growable: false),
  );
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

extension _PlatformConnectionStateExtension
    on messages.PlatformConnectionState {
  BlueConnectionState? toBlueConnectionState() {
    return switch (this) {
      messages.PlatformConnectionState.disconnected =>
        BlueConnectionState.disconnected,
      messages.PlatformConnectionState.connected =>
        BlueConnectionState.connected,
      _ => null,
    };
  }
}
