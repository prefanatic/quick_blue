import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_characteristic.dart';
import 'bluetooth_gatt.dart';
import 'quick_blue_platform.dart';

class BluetoothDevice {
  @internal
  BluetoothDevice.internal({
    required this.deviceId,
    required QuickBluePlatform platform,
    required Future<List<BluetoothService>> Function(String deviceId)
    discoverServices,
  }) : _platform = platform,
       _discoverServices = discoverServices;

  final String deviceId;
  final QuickBluePlatform _platform;
  final Future<List<BluetoothService>> Function(String deviceId)
  _discoverServices;

  String get id => deviceId;

  Stream<BluetoothConnectionStateChange> get connectionStateStream {
    return _platform.connectionStateStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  Stream<BluetoothService> get serviceDiscoveryStream {
    return _platform.serviceDiscoveryStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  Stream<BluetoothCharacteristicValue> get characteristicValueStream {
    return _platform.characteristicValueStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  Future<void> connect() async {
    await _runConnectionOperation(
      targetState: BlueConnectionState.connected,
      failureMessage: 'Failed to connect to Bluetooth device $deviceId.',
      operation: () => _platform.connect(deviceId),
    );
  }

  Future<void> disconnect() async {
    await _runConnectionOperation(
      targetState: BlueConnectionState.disconnected,
      failureMessage: 'Failed to disconnect Bluetooth device $deviceId.',
      operation: () => _platform.disconnect(deviceId),
    );
  }

  Future<void> _runConnectionOperation({
    required BlueConnectionState targetState,
    required String failureMessage,
    required Future<void> Function() operation,
  }) async {
    final stateEvents = StreamQueue(
      connectionStateStream.where(
        (event) =>
            event.status == BleStatus.failure || event.state == targetState,
      ),
    );

    try {
      await operation();
      final state = await stateEvents.next;
      if (state.status == BleStatus.failure) {
        throw StateError(failureMessage);
      }
    } finally {
      await stateEvents.cancel();
    }
  }

  Future<List<BluetoothService>> discoverServices() {
    return _discoverServices(deviceId);
  }

  Future<BluetoothGatt> discoverGatt() async {
    return BluetoothGatt.internal(
      device: this,
      services: await discoverServices(),
    );
  }

  BluetoothCharacteristic characteristic(
    String service,
    String characteristic,
  ) {
    return BluetoothCharacteristic.internal(
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      platform: _platform,
    );
  }

  Future<void> setNotifiable(
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) {
    return _platform.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
    );
  }

  Future<Uint8List> readValue(String service, String characteristic) async {
    return this.characteristic(service, characteristic).read();
  }

  Future<void> writeValue(
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) {
    return this
        .characteristic(service, characteristic)
        .write(value, bleOutputProperty);
  }

  Future<int> requestMtu(int expectedMtu) {
    return _platform.requestMtu(deviceId, expectedMtu);
  }

  Future<BleL2capSocket> openL2cap(int psm) {
    return _platform.openL2cap(deviceId, psm);
  }
}
