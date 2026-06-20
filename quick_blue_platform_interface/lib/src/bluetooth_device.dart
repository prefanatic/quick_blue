import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_characteristic.dart';
import 'bluetooth_gatt.dart';
import 'quick_blue_platform.dart';

/// A handle for a Bluetooth LE device.
///
/// The handle is cheap to create. It does not connect, scan, or validate that
/// the platform identifier currently resolves to a nearby device.
class BluetoothDevice {
  @internal
  BluetoothDevice.internal({
    required this.deviceId,
    required QuickBluePlatform platform,
    required Future<List<BluetoothService>> Function(String deviceId)
    discoverServices,
  }) : _platform = platform,
       _discoverServices = discoverServices;

  /// The platform-specific device identifier.
  final String deviceId;
  final QuickBluePlatform _platform;
  final Future<List<BluetoothService>> Function(String deviceId)
  _discoverServices;

  /// Alias for [deviceId].
  String get id => deviceId;

  /// Connection state changes for this device.
  ///
  /// The stream is filtered from the shared platform connection stream.
  Stream<BluetoothConnectionStateChange> get connectionStateStream {
    return _platform.connectionStateStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  /// Services discovered for this device.
  ///
  /// Listen directly for progressive discovery updates, or use
  /// [discoverServices] to wait for completion.
  Stream<BluetoothService> get serviceDiscoveryStream {
    return _platform.serviceDiscoveryStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  /// Characteristic value updates for this device.
  ///
  /// Use [characteristic] for a service-scoped stream.
  Stream<BluetoothCharacteristicValue> get characteristicValueStream {
    return _platform.characteristicValueStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  /// Connects and waits for a connected state event.
  ///
  /// Timeouts are left to callers with normal `Future.timeout` composition.
  Future<void> connect() async {
    await _runConnectionOperation(
      targetState: BlueConnectionState.connected,
      failureMessage: 'Failed to connect to Bluetooth device $deviceId.',
      operation: () => _platform.connect(deviceId),
    );
  }

  /// Disconnects and waits for a disconnected state event.
  ///
  /// Timeouts are left to callers with normal `Future.timeout` composition.
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

  /// Discovers services and characteristics for this device.
  ///
  /// Completes after the platform reports discovery completion.
  Future<List<BluetoothService>> discoverServices() {
    return _discoverServices(deviceId);
  }

  /// Discovers services and returns a GATT view for characteristic lookup.
  ///
  /// Prefer this when call sites know characteristic UUIDs but not service
  /// UUIDs yet.
  Future<BluetoothGatt> discoverGatt() async {
    return BluetoothGatt.internal(
      device: this,
      services: await discoverServices(),
    );
  }

  /// Returns a handle for a characteristic under [service].
  ///
  /// No platform work is started until the returned handle is used.
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

  /// Enables or disables notifications or indications for a characteristic.
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

  /// Reads a characteristic value.
  Future<Uint8List> readValue(String service, String characteristic) async {
    return this.characteristic(service, characteristic).read();
  }

  /// Writes a characteristic value.
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

  /// Requests or returns the negotiated MTU, depending on platform support.
  Future<int> requestMtu(int expectedMtu) {
    return _platform.requestMtu(deviceId, expectedMtu);
  }

  /// Opens a BLE L2CAP socket for this device.
  Future<BleL2capSocket> openL2cap(int psm) {
    return _platform.openL2cap(deviceId, psm);
  }
}
