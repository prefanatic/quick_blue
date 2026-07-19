import 'dart:async';

import 'package:flutter/services.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

class QuickBlueDarwin extends QuickBluePlatform {
  QuickBlueDarwin();

  final messages.QuickBlueApi _api = messages.QuickBlueApi();
  messages.QuickBlueFlutterApi? _flutterApi;
  late final Stream<BlueBluetoothState> _bluetoothStateEvents = messages
      .bluetoothState()
      .map((state) => state.toBlueBluetoothState());
  late final Stream<BlueScanResult> _scanResultStream = messages
      .scanResults()
      .map(_scanResultFromPlatformResult)
      .where(_matchesActiveServiceDataFilter);
  Map<String, Uint8List>? _activeScanServiceData;

  bool _matchesActiveServiceDataFilter(BlueScanResult result) {
    return matchesServiceDataFilter(_activeScanServiceData, result.serviceData);
  }

  final Stream<messages.PlatformL2CapSocketEvent> _l2CapEventStream = messages
      .l2CapSocketEvents();

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueDarwin();
  }

  void _ensureInitialized() {
    if (_flutterApi != null) return;
    _flutterApi = _FlutterApi(this);
    messages.QuickBlueFlutterApi.setUp(_flutterApi);
  }

  // This API remains Android-specific. Apple AccessorySetupKit is exposed
  // separately because its picker items and identifiers have different shapes.
  static const _companionUnsupported =
      'Companion device association is not supported on iOS/macOS '
      '(use QuickBlue.appleAccessorySetup on supported iOS versions).';

  static const _pairingUnsupported =
      'App-initiated Bluetooth LE pairing is not supported on iOS/macOS. '
      'CoreBluetooth pairs automatically when a protected attribute is used.';

  @override
  Future<void> configure({bool maintainState = false}) {
    _ensureInitialized();

    return _api.configure(
      messages.PlatformDarwinConfiguration(maintainState: maintainState),
    );
  }

  @override
  Future<bool> isAppleAccessorySetupSupported() {
    _ensureInitialized();
    return _api.isAppleAccessorySetupSupported();
  }

  @override
  Future<AppleAccessory?> showAppleAccessoryPicker(
    List<AppleAccessoryPickerItem> items,
  ) async {
    _ensureInitialized();
    final accessory = await _api.showAppleAccessoryPicker(
      items.map(_toPlatformAppleAccessoryPickerItem).toList(growable: false),
    );
    return accessory == null ? null : _toAppleAccessory(accessory);
  }

  @override
  Future<List<AppleAccessory>> getAppleAccessories() async {
    _ensureInitialized();
    final accessories = await _api.getAppleAccessories();
    return accessories.map(_toAppleAccessory).toList(growable: false);
  }

  @override
  Future<void> removeAppleAccessory(String deviceId) {
    _ensureInitialized();
    return _api.removeAppleAccessory(deviceId);
  }

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

    final peripherals = await _api.getConnectedPeripherals(serviceUuids);
    return peripherals
        .map((peripheral) => device(peripheral.id))
        .toList(growable: false);
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
  Future<BluetoothBondState> bondState(String deviceId) async {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'bondState',
      message: _pairingUnsupported,
    );
  }

  @override
  Future<void> pair(String deviceId) {
    throw const QuickBlueException(
      code: QuickBlueErrorCode.unsupported,
      operation: 'pair',
      message: _pairingUnsupported,
    );
  }

  @override
  Future<QuickBlueSecurityRecoveryResult> performSecurityRecovery(
    String deviceId,
    QuickBlueSecurityException error,
  ) async {
    if (error.reason ==
        QuickBlueSecurityErrorReason.peerRemovedPairingInformation) {
      return QuickBlueSecurityRecoveryResult.userActionRequired;
    }
    // CoreBluetooth owns pairing and encryption negotiation. Retrying the
    // rejected operation gives it one bounded opportunity to renegotiate.
    return QuickBlueSecurityRecoveryResult.recovered;
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
  Stream<BlueBluetoothState> get bluetoothStateEvents {
    _ensureInitialized();

    return _bluetoothStateEvents;
  }

  @override
  Future<BleL2capSocket> openL2cap(String deviceId, int psm) async {
    _ensureInitialized();

    await _api.openL2cap(deviceId, psm);

    // Wait for the open status.
    await _l2CapEventStream
        .where((event) => event.deviceId == deviceId)
        .firstWhere((event) => event.opened == true)
        .timeout(const Duration(seconds: 5));

    return BleL2capSocket(
      sink: _L2capSink(api: _api, deviceId: deviceId),
      stream: _l2CapEventStream
          .where((event) => event.deviceId == deviceId)
          .map(_l2capEventFromPlatformEvent),
    );
  }

  @override
  Future<void> readValue(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    await readCharacteristicValue(deviceId, service, characteristic);
  }

  @override
  Future<Uint8List> readCharacteristicValue(
    String deviceId,
    String service,
    String characteristic,
  ) {
    _ensureInitialized();

    return _runDarwinGattOperation(
      operation: 'readValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.readValue(deviceId, service, characteristic),
    );
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

    return _runDarwinGattOperation(
      operation: 'setNotifiable',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.setNotifiable(
        deviceId,
        service,
        characteristic,
        bleInputProperty.toPlatformBleInputProperty(),
      ),
    );
  }

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) async {
    _ensureInitialized();
    _activeScanServiceData = scanFilter.serviceData;

    final serviceUuids = scanFilter.serviceUuids.isEmpty
        ? null
        : scanFilter.serviceUuids;
    final manufacturerData = scanFilter.manufacturerData?.isEmpty == true
        ? null
        : scanFilter.manufacturerData;

    try {
      await _api.startScan(
        serviceUuids: serviceUuids,
        manufacturerData: manufacturerData,
        rssi: scanFilter.rssi,
        options: scanOptions.toPlatformDarwinScanOptions(),
      );
    } catch (_) {
      _activeScanServiceData = null;
      rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    _ensureInitialized();

    try {
      await _api.stopScan();
    } finally {
      _activeScanServiceData = null;
    }
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

    return _runDarwinGattOperation(
      operation: 'writeValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.writeValue(
        deviceId,
        service,
        characteristic,
        value,
        bleOutputProperty.toPlatformBleOutputProperty(),
      ),
    );
  }
}

Future<T> _runDarwinGattOperation<T>({
  required String operation,
  required String deviceId,
  required String serviceId,
  required String characteristicId,
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } on PlatformException catch (error, stackTrace) {
    final details = error.details;
    if (details is! Map<Object?, Object?>) {
      rethrow;
    }
    final nativeDomain = details['domain'];
    final nativeCode = details['code'];
    if (nativeDomain is! String || nativeCode is! num) {
      rethrow;
    }
    final reason = _securityErrorReason(nativeDomain, nativeCode.toInt());
    if (reason == null) {
      rethrow;
    }
    Error.throwWithStackTrace(
      _securityException(
        nativeDomain: nativeDomain,
        nativeCode: nativeCode.toInt(),
        reason: reason,
        operation: operation,
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        message:
            error.message ??
            '$operation failed with $nativeDomain error $nativeCode.',
      ),
      stackTrace,
    );
  }
}

QuickBlueSecurityErrorReason? _securityErrorReason(
  String nativeDomain,
  int nativeCode,
) {
  if (nativeDomain == 'CBATTErrorDomain') {
    return switch (nativeCode) {
      5 => QuickBlueSecurityErrorReason.insufficientAuthentication,
      8 => QuickBlueSecurityErrorReason.insufficientAuthorization,
      12 => QuickBlueSecurityErrorReason.insufficientEncryptionKeySize,
      15 => QuickBlueSecurityErrorReason.insufficientEncryption,
      _ => null,
    };
  }
  if (nativeDomain == 'CBErrorDomain') {
    return switch (nativeCode) {
      14 => QuickBlueSecurityErrorReason.peerRemovedPairingInformation,
      15 => QuickBlueSecurityErrorReason.encryptionTimedOut,
      _ => null,
    };
  }
  return null;
}

QuickBlueSecurityException _securityException({
  required String nativeDomain,
  required int nativeCode,
  required QuickBlueSecurityErrorReason reason,
  required String operation,
  required String deviceId,
  String? serviceId,
  String? characteristicId,
  required String message,
}) {
  return QuickBlueSecurityException(
    reason: reason,
    nativeDomain: nativeDomain,
    nativeCode: nativeCode,
    operation: operation,
    deviceId: deviceId,
    serviceId: serviceId,
    characteristicId: characteristicId,
    message: message,
  );
}

extension on ScanOptions {
  messages.PlatformDarwinScanOptions toPlatformDarwinScanOptions() {
    return messages.PlatformDarwinScanOptions(
      allowDuplicates: darwin.allowDuplicates ?? allowDuplicates ?? true,
      solicitedServiceUuids: darwin.solicitedServiceUuids,
    );
  }
}

BlueScanResult _scanResultFromPlatformResult(
  messages.PlatformScanResult result,
) {
  return BlueScanResult(
    deviceId: result.deviceId,
    name: result.name,
    rssi: result.rssi,
    serviceUuids: result.serviceUuids,
    manufacturerDataHead: result.manufacturerDataHead,
    manufacturerData: result.manufacturerData,
    serviceData: result.serviceData,
  );
}

messages.PlatformAppleAccessoryPickerItem _toPlatformAppleAccessoryPickerItem(
  AppleAccessoryPickerItem item,
) {
  final discovery = item.discovery;
  return messages.PlatformAppleAccessoryPickerItem(
    displayName: item.displayName,
    productImage: item.productImage,
    migrationDeviceId: item.migrationDeviceId,
    discovery: messages.PlatformAppleAccessoryDiscovery(
      serviceUuid: discovery.serviceUuid,
      nameSubstring: discovery.nameSubstring,
      serviceData: discovery.serviceData,
      serviceDataMask: discovery.serviceDataMask,
      immediate: discovery.immediate,
    ),
  );
}

AppleAccessory _toAppleAccessory(messages.PlatformAppleAccessory accessory) {
  return AppleAccessory(
    deviceId: accessory.deviceId,
    displayName: accessory.displayName,
  );
}

BleL2CapSocketEvent _l2capEventFromPlatformEvent(
  messages.PlatformL2CapSocketEvent event,
) {
  if (event.data != null) {
    return BleL2CapSocketEventData(deviceId: event.deviceId, data: event.data!);
  } else if (event.error != null) {
    return BleL2CapSocketEventError(
      deviceId: event.deviceId,
      error: event.error,
    );
  } else if (event.opened == true) {
    return BleL2CapSocketEventOpened(deviceId: event.deviceId);
  } else if (event.closed == true) {
    return BleL2CapSocketEventClosed(deviceId: event.deviceId);
  }

  throw QuickBlueException(
    code: QuickBlueErrorCode.invalidState,
    operation: 'openL2cap',
    deviceId: event.deviceId,
    details: event,
    message: 'Unknown L2CAP event.',
  );
}

class _L2capSink implements EventSink<Uint8List> {
  _L2capSink({required this.api, required this.deviceId});

  final messages.QuickBlueApi api;
  final String deviceId;

  @override
  void add(Uint8List event) {
    api.writeL2cap(deviceId, event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close() async {}
}

class _FlutterApi extends messages.QuickBlueFlutterApi {
  _FlutterApi(this.platform);

  final QuickBlueDarwin platform;

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

  platform.handleConnectionStateChanged(
    stateChange.deviceId,
    state,
    stateChange.gattStatus.toBleStatus(),
    error: _connectionError(stateChange),
  );
}

QuickBlueException? _connectionError(
  messages.PlatformConnectionStateChange stateChange,
) {
  final nativeDomain = stateChange.errorDomain;
  final nativeCode = stateChange.errorCode;
  if (nativeDomain == null || nativeCode == null) {
    return null;
  }
  final message =
      stateChange.errorMessage ??
      'CoreBluetooth connection failed with $nativeDomain error $nativeCode.';
  final reason = _securityErrorReason(nativeDomain, nativeCode);
  if (reason != null) {
    return _securityException(
      nativeDomain: nativeDomain,
      nativeCode: nativeCode,
      reason: reason,
      operation: 'connection',
      deviceId: stateChange.deviceId,
      message: message,
    );
  }
  return QuickBlueException(
    code: QuickBlueErrorCode.operationFailed,
    operation: 'connection',
    deviceId: stateChange.deviceId,
    details: <String, Object>{'domain': nativeDomain, 'code': nativeCode},
    message: message,
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

extension _BluetoothStateExtension on messages.PlatformBluetoothState {
  BlueBluetoothState toBlueBluetoothState() {
    return switch (this) {
      messages.PlatformBluetoothState.unknown => BlueBluetoothState.unknown,
      messages.PlatformBluetoothState.unavailable =>
        BlueBluetoothState.unavailable,
      messages.PlatformBluetoothState.unauthorized =>
        BlueBluetoothState.unauthorized,
      messages.PlatformBluetoothState.poweredOff =>
        BlueBluetoothState.poweredOff,
      messages.PlatformBluetoothState.poweredOn => BlueBluetoothState.poweredOn,
    };
  }
}
