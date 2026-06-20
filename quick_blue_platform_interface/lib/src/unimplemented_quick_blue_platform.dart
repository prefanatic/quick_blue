import 'dart:typed_data';

import '../models.dart';
import 'bluetooth_device.dart';
import 'quick_blue_platform.dart';
import 'quick_blue_exception.dart';

class UnimplementedQuickBluePlatform extends QuickBluePlatform {
  static QuickBlueException _unsupported(String operation) {
    return QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: operation,
      message: 'No QuickBlue platform implementation has been registered.',
    );
  }

  @override
  Future<bool> isBluetoothAvailable() {
    return Future<bool>.error(_unsupported('isBluetoothAvailable'));
  }

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    return Future<void>.error(_unsupported('startScan'));
  }

  @override
  Future<void> stopScan() {
    return Future<void>.error(_unsupported('stopScan'));
  }

  @override
  Stream<BlueScanResult> get scanResultStream {
    return Stream<BlueScanResult>.error(_unsupported('scanResultStream'));
  }

  @override
  Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) {
    return Future<List<BluetoothDevice>>.error(
      _unsupported('connectedDevices'),
    );
  }

  @override
  Future<void> connect(String deviceId) {
    return Future<void>.error(_unsupported('connect'));
  }

  @override
  Future<void> disconnect(String deviceId) {
    return Future<void>.error(_unsupported('disconnect'));
  }

  @override
  Future<bool> isCompanionAssociationSupported() {
    return Future<bool>.error(_unsupported('isCompanionAssociationSupported'));
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) {
    return Future<CompanionAssociation?>.error(
      _unsupported('companionAssociate'),
    );
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    return Future<void>.error(_unsupported('companionDisassociate'));
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() {
    return Future<List<CompanionAssociation>>.error(
      _unsupported('getCompanionAssociations'),
    );
  }

  @override
  Future<void> discoverServices(String deviceId) {
    return Future<void>.error(_unsupported('discoverServices'));
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return Future<void>.error(_unsupported('setNotifiable'));
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return Future<void>.error(_unsupported('readValue'));
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return Future<void>.error(_unsupported('writeValue'));
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    return Future<int>.error(_unsupported('requestMtu'));
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) {
    return Future<BleL2capSocket>.error(_unsupported('openL2cap'));
  }
}
