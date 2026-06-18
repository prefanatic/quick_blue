import 'dart:typed_data';

import '../models.dart';
import 'bluetooth_device.dart';
import 'quick_blue_platform.dart';

class UnimplementedQuickBluePlatform extends QuickBluePlatform {
  static UnsupportedError _unsupported() {
    return UnsupportedError(
      'No QuickBlue platform implementation has been registered.',
    );
  }

  @override
  Future<bool> isBluetoothAvailable() => Future<bool>.error(_unsupported());

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> stopScan() => Future<void>.error(_unsupported());

  @override
  Stream<BlueScanResult> get scanResultStream {
    return Stream<BlueScanResult>.error(_unsupported());
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) {
    return Future<List<BluetoothDevice>>.error(_unsupported());
  }

  @override
  Future<void> connect(String deviceId) => Future<void>.error(_unsupported());

  @override
  Future<void> disconnect(String deviceId) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<bool> isCompanionAssociationSupported() {
    return Future<bool>.error(_unsupported());
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) {
    return Future<CompanionAssociation?>.error(_unsupported());
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() {
    return Future<List<CompanionAssociation>>.error(_unsupported());
  }

  @override
  Future<void> discoverServices(String deviceId) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return Future<void>.error(_unsupported());
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    return Future<int>.error(_unsupported());
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) {
    return Future<BleL2capSocket>.error(_unsupported());
  }
}
