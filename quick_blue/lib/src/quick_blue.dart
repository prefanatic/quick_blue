import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

export 'package:quick_blue_platform_interface/models.dart';
export 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart'
    show
        BluetoothCharacteristic,
        BluetoothDevice,
        BluetoothGatt,
        QuickBlueErrorCode,
        QuickBlueException,
        QuickBlueGattException,
        QuickBlueSecurityErrorReason,
        QuickBlueSecurityException,
        QuickBlueSecurityRecoveryResult;

export 'quick_blue_android.dart';

QuickBluePlatform get _platform => QuickBluePlatform.instance;

/// Entry point for Bluetooth LE operations.
class QuickBlue {
  /// Android companion-device association APIs.
  ///
  /// Check [QuickBlueCompanion.isSupported] before showing association UI.
  static final QuickBlueCompanion companion = QuickBlueCompanion._();

  /// Configures platform behavior before starting Bluetooth work.
  ///
  /// When [maintainState] is true, iOS and macOS opt into CoreBluetooth state
  /// preservation and restoration. Call this before any other `QuickBlue` API.
  static Future<void> configure({bool maintainState = false}) {
    return _platform.configure(maintainState: maintainState);
  }

  /// Returns whether Bluetooth is powered on and usable.
  static Future<bool> isBluetoothAvailable() =>
      _platform.isBluetoothAvailable();

  /// Emits the current Bluetooth state, then later state changes when possible.
  ///
  /// Platforms without live state monitoring may emit only the initial state.
  static Stream<BlueBluetoothState> get bluetoothStateStream =>
      _platform.bluetoothStateStream;

  /// Starts scanning with the legacy manual scan lifecycle.
  @Deprecated('Use QuickBlue.scanResults() instead.')
  static Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) => _platform.startScan(scanFilter: scanFilter, scanOptions: scanOptions);

  /// Stops a scan started by [startScan].
  @Deprecated('Use QuickBlue.scanResults() instead.')
  static Future<void> stopScan() => _platform.stopScan();

  /// Raw scan results from the legacy manual scan lifecycle.
  @Deprecated('Use QuickBlue.scanResults() instead.')
  static Stream<BlueScanResult> get scanResultStream {
    return _platform.scanResultStream;
  }

  /// Starts scanning on listen and stops when the stream is canceled.
  ///
  /// While a scan is active, additional listeners must use the same
  /// [scanFilter] and [scanOptions]. A different configuration throws instead
  /// of silently changing the shared platform scan.
  static Stream<BlueScanResult> scanResults({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    return _platform.scanResults(
      scanFilter: scanFilter,
      scanOptions: scanOptions,
    );
  }

  /// Scans for device handles.
  ///
  /// Use [scanResults] when advertisement data such as RSSI, service data, or
  /// manufacturer data is needed.
  static Stream<BluetoothDevice> scan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    return _platform.scan(scanFilter: scanFilter, scanOptions: scanOptions);
  }

  /// Legacy stream of scanned device handles.
  @Deprecated('Use QuickBlue.scan() instead.')
  static Stream<BluetoothDevice> get bluetoothDeviceStream {
    return _platform.bluetoothDeviceStream;
  }

  /// Returns a lightweight handle for a platform Bluetooth device identifier.
  ///
  /// Creating a handle does not connect or validate that the device is nearby.
  static BluetoothDevice device(String deviceId) => _platform.device(deviceId);

  /// Returns handles for devices already connected at the system level.
  ///
  /// iOS and macOS require [serviceUuids] for CoreBluetooth lookup.
  static Future<List<BluetoothDevice>> connectedDevices({
    List<String> serviceUuids = const <String>[],
  }) {
    return _platform.connectedDevices(serviceUuids: serviceUuids);
  }

  /// Connects to [deviceId] and waits for the connected state event.
  @Deprecated('Use QuickBlue.device(deviceId).connect() instead.')
  static Future<void> connect(String deviceId) => device(deviceId).connect();

  /// Disconnects from [deviceId] and waits for the disconnected state event.
  @Deprecated('Use QuickBlue.device(deviceId).disconnect() instead.')
  static Future<void> disconnect(String deviceId) =>
      device(deviceId).disconnect();

  /// Returns the current pairing/bonding state for [deviceId].
  static Future<BluetoothBondState> bondState(String deviceId) {
    return device(deviceId).bondState();
  }

  /// Pairing/bonding state transitions for all devices.
  static Stream<BluetoothBondStateChange> get bondStateStream {
    return _platform.bondStateStream;
  }

  /// Waits until [deviceId] reaches [targetState].
  static Future<BluetoothBondState> waitForBondState(
    String deviceId,
    BluetoothBondState targetState,
  ) {
    return device(deviceId).waitForBondState(targetState);
  }

  /// Starts pairing/bonding with [deviceId].
  static Future<void> pair(String deviceId) => device(deviceId).pair();

  /// Starts a legacy Android companion-device association request.
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

  /// Removes a legacy Android companion-device association.
  @Deprecated('Use QuickBlue.companion.disassociate() instead.')
  static Future<void> companionDisassociate(int associationId) =>
      companion.disassociate(associationId);

  /// Removes a legacy Android companion-device association.
  @Deprecated('Use QuickBlue.companion.disassociate() instead.')
  static Future<void> companionDissassociate(int associationId) =>
      companionDisassociate(associationId);

  /// Returns legacy Android companion-device associations.
  @Deprecated('Use QuickBlue.companion.associations() instead.')
  static Future<List<CompanionDevice>?> getCompanionAssociations() async {
    final associations = await companion.associations();
    return associations.map(_toLegacyCompanionDevice).toList(growable: false);
  }

  /// Sets the legacy global connection callback.
  @Deprecated(
    'Listen to QuickBlue.device(deviceId).connectionStateStream instead.',
  )
  static void setConnectionHandler(OnConnectionChanged? onConnectionChanged) {
    _platform.onConnectionChanged = onConnectionChanged;
  }

  /// Discovers services for [deviceId].
  ///
  /// The returned future completes after the platform reports service discovery
  /// completion.
  @Deprecated('Use QuickBlue.device(deviceId).discoverServices() instead.')
  static Future<List<BluetoothService>> discoverServices(String deviceId) =>
      device(deviceId).discoverServices();

  /// Discovers a GATT view for [deviceId].
  ///
  /// Use the returned [BluetoothGatt] to resolve characteristics by UUID,
  /// including the service UUID when a characteristic is ambiguous.
  @Deprecated('Use QuickBlue.device(deviceId).discoverGatt() instead.')
  static Future<BluetoothGatt> discoverGatt(String deviceId) =>
      device(deviceId).discoverGatt();

  /// Sets the legacy global service discovery callback.
  @Deprecated('Use QuickBlue.device(deviceId).discoverServices() instead.')
  static void setServiceHandler(OnServiceDiscovered? onServiceDiscovered) {
    _platform.onServiceDiscovered = onServiceDiscovered;
  }

  /// Enables or disables notifications or indications for a characteristic.
  @Deprecated(
    'Use QuickBlue.device(deviceId).characteristic(service, characteristic).notifications() '
    'or QuickBlue.device(deviceId).discoverGatt() instead.',
  )
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

  /// Sets the legacy global characteristic value callback.
  @Deprecated(
    'Use QuickBlue.device(deviceId).readValue or listen to '
    'QuickBlue.device(deviceId).characteristicValueStream instead.',
  )
  static void setValueHandler(OnValueChanged? onValueChanged) {
    _platform.onValueChanged = onValueChanged;
  }

  /// Reads a characteristic value and completes with the matching value event.
  @Deprecated(
    'Use QuickBlue.device(deviceId).characteristic(service, characteristic).read() '
    'or QuickBlue.device(deviceId).discoverGatt() instead.',
  )
  static Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    return device(deviceId).readValue(service, characteristic);
  }

  /// Writes a characteristic value.
  @Deprecated(
    'Use QuickBlue.device(deviceId).characteristic(service, characteristic).write() '
    'or QuickBlue.device(deviceId).discoverGatt() instead.',
  )
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

  /// Requests or returns the negotiated MTU, depending on platform support.
  @Deprecated('Use QuickBlue.device(deviceId).requestMtu() instead.')
  static Future<int> requestMtu(String deviceId, int expectedMtu) =>
      device(deviceId).requestMtu(expectedMtu);

  /// Opens a BLE L2CAP socket for [deviceId] and protocol/service multiplexer.
  ///
  /// Not every platform supports L2CAP sockets.
  @Deprecated('Use QuickBlue.device(deviceId).openL2cap() instead.')
  static Future<BleL2capSocket> openL2cap(String deviceId, int psm) =>
      device(deviceId).openL2cap(psm);
}

/// Android companion-device association API.
///
/// Unsupported platforms report [isSupported] as false and throw
/// [QuickBlueException] with [QuickBlueErrorCode.unsupported] for association
/// operations.
class QuickBlueCompanion {
  QuickBlueCompanion._();

  /// Returns whether companion association is supported on this platform.
  Future<bool> isSupported() => _platform.isCompanionAssociationSupported();

  /// Starts a companion-device association request.
  Future<CompanionAssociation?> associate(CompanionAssociationRequest request) {
    return _platform.companionAssociate(request);
  }

  /// Removes the association with [associationId].
  Future<void> disassociate(int associationId) {
    return _platform.companionDisassociate(associationId);
  }

  /// Returns current companion-device associations.
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
