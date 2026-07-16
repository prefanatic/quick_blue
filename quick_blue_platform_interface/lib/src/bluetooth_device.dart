import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import '../models.dart';
import 'bluetooth_characteristic.dart';
import 'bluetooth_gatt.dart';
import 'quick_blue_platform.dart';
import 'quick_blue_exception.dart';

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
  /// Throws [QuickBlueException] when another connection operation for this
  /// device is already pending. A later [disconnect] supersedes this operation
  /// and completes it with [QuickBlueErrorCode.cancelled]. A temporarily busy
  /// shared native connection is retried automatically.
  /// Structured security failures trigger one coordinated recovery attempt and
  /// retry before a terminal exception is reported.
  ///
  /// Timeouts are left to callers with normal `Future.timeout` composition.
  Future<void> connect() {
    return _platform.runWithSecurityRecovery(
      deviceId,
      () => _platform.connectDevice(deviceId),
    );
  }

  /// Disconnects this client and waits for a disconnected state event.
  ///
  /// A platform may retain a process-wide physical connection while another
  /// Flutter engine remains attached to the same device.
  ///
  /// If a connect is pending, this call cancels it before disconnecting. Other
  /// overlapping connection operations still throw [QuickBlueException].
  ///
  /// Timeouts are left to callers with normal `Future.timeout` composition.
  Future<void> disconnect() => _platform.disconnectDevice(deviceId);

  /// Returns the current pairing/bonding state for this device.
  Future<BluetoothBondState> bondState() {
    return _platform.bondState(deviceId);
  }

  /// Pairing/bonding state transitions for this device.
  Stream<BluetoothBondStateChange> get bondStateStream {
    return _platform.bondStateStream.where(
      (event) => event.deviceId == deviceId,
    );
  }

  /// Waits until this device reaches [targetState].
  ///
  /// The event subscription is established before the current state is read,
  /// so a transition racing with the snapshot is not missed. Timeouts are left
  /// to callers with normal `Future.timeout` composition.
  Future<BluetoothBondState> waitForBondState(
    BluetoothBondState targetState,
  ) async {
    final stateEvents = StreamQueue(
      bondStateStream.where((event) => event.state == targetState),
    );

    try {
      final currentState = await bondState();
      if (currentState == targetState) {
        return currentState;
      }
      return (await stateEvents.next).state;
    } finally {
      await stateEvents.cancel();
    }
  }

  /// Starts pairing/bonding with this device.
  Future<void> pair() {
    return _platform.pair(deviceId);
  }

  /// Explicitly attempts the platform's best recovery for [error].
  ///
  /// Normal connection and characteristic operations invoke this recovery
  /// automatically before surfacing a terminal security exception.
  Future<QuickBlueSecurityRecoveryResult> recoverSecurity(
    QuickBlueSecurityException error,
  ) {
    return _platform.recoverSecurity(deviceId, error);
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
    return _platform.runWithSecurityRecovery(
      deviceId,
      () => _platform.setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty,
      ),
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
