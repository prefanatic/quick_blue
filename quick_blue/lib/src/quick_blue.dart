import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

export 'package:quick_blue_platform_interface/models.dart';
export 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart'
    show BluetoothCharacteristic, BluetoothDevice, BluetoothGatt;

export 'quick_blue_android.dart';

QuickBluePlatform get _platform => QuickBluePlatform.instance;

class QuickBlue {
  static final QuickBlueCompanion companion = QuickBlueCompanion._();

  static Future<bool> isBluetoothAvailable() =>
      _platform.isBluetoothAvailable();

  static Stream<BlueBluetoothState> get bluetoothStateStream =>
      _platform.bluetoothStateStream;

  @Deprecated('Use QuickBlue.scanResults() instead.')
  static Future<void> startScan({ScanFilter scanFilter = ScanFilter.empty}) =>
      _platform.startScan(scanFilter: scanFilter);

  @Deprecated('Use QuickBlue.scanResults() instead.')
  static Future<void> stopScan() => _platform.stopScan();

  @Deprecated('Use QuickBlue.scanResults() instead.')
  static Stream<BlueScanResult> get scanResultStream {
    return _platform.scanResultStream;
  }

  static Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = ScanFilter.empty,
  }) {
    return _platform.scanResults(scanFilter: scanFilter);
  }

  static Stream<BluetoothDevice> scan({
    ScanFilter scanFilter = ScanFilter.empty,
  }) {
    return _platform.scan(scanFilter: scanFilter);
  }

  @Deprecated('Use QuickBlue.scan() instead.')
  static Stream<BluetoothDevice> get bluetoothDeviceStream {
    return _platform.bluetoothDeviceStream;
  }

  static BluetoothDevice device(String deviceId) => _platform.device(deviceId);

  static Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) {
    return _platform.connectedDevices(serviceUuids: serviceUuids);
  }

  static Future<void> connect(String deviceId) => device(deviceId).connect();

  static Future<void> disconnect(String deviceId) =>
      device(deviceId).disconnect();

  @Deprecated('Use QuickBlue.companion.associate() instead.')
  static Future<CompanionDevice?> companionAssociate({
    String? deviceId,
    ScanFilter? scanFilter,
  }) async {
    final association = await companion.associate(
      CompanionAssociationRequest.ble(
        filters: _legacyCompanionFilters(
          deviceId: deviceId,
          scanFilter: scanFilter,
        ),
      ),
    );
    return association == null ? null : _toLegacyCompanionDevice(association);
  }

  @Deprecated('Use QuickBlue.companion.disassociate() instead.')
  static Future<void> companionDisassociate(int associationId) =>
      companion.disassociate(associationId);

  @Deprecated('Use QuickBlue.companion.disassociate() instead.')
  static Future<void> companionDissassociate(int associationId) =>
      companionDisassociate(associationId);

  @Deprecated('Use QuickBlue.companion.associations() instead.')
  static Future<List<CompanionDevice>?> getCompanionAssociations() async {
    final associations = await companion.associations();
    return associations.map(_toLegacyCompanionDevice).toList(growable: false);
  }

  @Deprecated(
    'Listen to QuickBlue.device(deviceId).connectionStateStream instead.',
  )
  static void setConnectionHandler(OnConnectionChanged? onConnectionChanged) {
    _platform.onConnectionChanged = onConnectionChanged;
  }

  static Future<List<BluetoothService>> discoverServices(String deviceId) =>
      device(deviceId).discoverServices();

  static Future<BluetoothGatt> discoverGatt(String deviceId) =>
      device(deviceId).discoverGatt();

  @Deprecated('Use QuickBlue.device(deviceId).discoverServices() instead.')
  static void setServiceHandler(OnServiceDiscovered? onServiceDiscovered) {
    _platform.onServiceDiscovered = onServiceDiscovered;
  }

  static Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return device(
      deviceId,
    ).setNotifiable(service, characteristic, bleInputProperty);
  }

  @Deprecated(
    'Use QuickBlue.device(deviceId).readValue or listen to '
    'QuickBlue.device(deviceId).characteristicValueStream instead.',
  )
  static void setValueHandler(OnValueChanged? onValueChanged) {
    _platform.onValueChanged = onValueChanged;
  }

  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return device(deviceId).readValue(service, characteristic);
  }

  static Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return device(
      deviceId,
    ).writeValue(service, characteristic, value, bleOutputProperty);
  }

  static Future<int> requestMtu(String deviceId, int expectedMtu) =>
      device(deviceId).requestMtu(expectedMtu);

  static Future<BleL2capSocket> openL2cap(String deviceId, int psm) =>
      device(deviceId).openL2cap(psm);
}

class QuickBlueCompanion {
  QuickBlueCompanion._();

  Future<bool> isSupported() => _platform.isCompanionAssociationSupported();

  Future<CompanionAssociation?> associate(CompanionAssociationRequest request) {
    return _platform.companionAssociate(request);
  }

  Future<void> disassociate(int associationId) {
    return _platform.companionDisassociate(associationId);
  }

  Future<List<CompanionAssociation>> associations() {
    return _platform.getCompanionAssociations();
  }
}

List<BleCompanionFilter> _legacyCompanionFilters({
  String? deviceId,
  ScanFilter? scanFilter,
}) {
  final hasScanFilter =
      scanFilter != null &&
      (scanFilter.serviceUuids.isNotEmpty ||
          scanFilter.manufacturerData != null);
  if (deviceId == null && !hasScanFilter) {
    return const <BleCompanionFilter>[];
  }
  return <BleCompanionFilter>[
    BleCompanionFilter(
      deviceId: deviceId,
      serviceUuids: scanFilter?.serviceUuids ?? const <String>[],
      manufacturerData: scanFilter?.manufacturerData,
    ),
  ];
}

// ignore: deprecated_member_use
CompanionDevice _toLegacyCompanionDevice(CompanionAssociation association) {
  // ignore: deprecated_member_use
  return CompanionDevice(
    id: association.deviceId ?? '',
    name: association.displayName ?? '',
    associationId: association.id,
  );
}
