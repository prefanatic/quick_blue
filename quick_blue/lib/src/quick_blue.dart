import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

export 'package:quick_blue_platform_interface/models.dart';
export 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart'
    show BluetoothCharacteristic, BluetoothDevice;

export 'quick_blue_android.dart';

QuickBluePlatform get _platform => QuickBluePlatform.instance;

class QuickBlue {
  static Future<bool> isBluetoothAvailable() =>
      _platform.isBluetoothAvailable();

  static Future<void> startScan({ScanFilter scanFilter = const ScanFilter()}) =>
      _platform.startScan(scanFilter: scanFilter);

  static Future<void> stopScan() => _platform.stopScan();

  static Stream<BlueScanResult> get scanResultStream {
    return _platform.scanResultStream;
  }

  static Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = const ScanFilter(),
  }) {
    return _platform.scanResults(scanFilter: scanFilter);
  }

  static Stream<BluetoothDevice> scan({
    ScanFilter scanFilter = const ScanFilter(),
  }) {
    return _platform.scan(scanFilter: scanFilter);
  }

  @Deprecated('Use QuickBlue.scan() instead.')
  static Stream<BluetoothDevice> get bluetoothDeviceStream {
    return _platform.bluetoothDeviceStream;
  }

  static BluetoothDevice device(String deviceId) => _platform.device(deviceId);

  static Future<void> connect(String deviceId) => device(deviceId).connect();

  static Future<void> disconnect(String deviceId) =>
      device(deviceId).disconnect();

  static Future<CompanionDevice?> companionAssociate({
    String? deviceId,
    ScanFilter? scanFilter,
  }) =>
      _platform.companionAssociate(deviceId: deviceId, scanFilter: scanFilter);

  static Future<void> companionDissassociate(int associationId) =>
      _platform.companionDisassociate(associationId);

  static Future<List<CompanionDevice>?> getCompanionAssociations() =>
      _platform.getCompanionAssociations();

  @Deprecated(
    'Listen to QuickBlue.device(deviceId).connectionStateStream instead.',
  )
  static void setConnectionHandler(OnConnectionChanged? onConnectionChanged) {
    _platform.onConnectionChanged = onConnectionChanged;
  }

  static Future<List<BluetoothService>> discoverServices(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) => device(deviceId).discoverServices(timeout: timeout);

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
    String characteristic, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return device(
      deviceId,
    ).readValue(service, characteristic, timeout: timeout);
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
