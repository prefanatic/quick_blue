import 'dart:async';

import 'package:flutter/services.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

class QuickBlueAndroid extends QuickBluePlatform {
  QuickBlueAndroid();

  final messages.QuickBlueApi _api = messages.QuickBlueApi();
  messages.QuickBlueFlutterApi? _flutterApi;
  late final Stream<BlueBluetoothState> _bluetoothStateEvents = messages
      .bluetoothState()
      .map((state) => state.toBlueBluetoothState());
  late final Stream<BluetoothBondStateChange> _bondStateEvents = messages
      .bondStateChanges()
      .map(_bondStateChangeFromPlatform);
  late final Stream<BlueScanResult> _scanResultStream = messages
      .scanResults()
      .map(_scanResultFromPlatformResult)
      .where(_matchesActiveServiceDataFilter);
  Map<String, Uint8List>? _activeScanServiceData;

  bool _matchesActiveServiceDataFilter(BlueScanResult result) {
    return matchesServiceDataFilter(_activeScanServiceData, result.serviceData);
  }

  static void registerWith() {
    QuickBluePlatform.instance = QuickBlueAndroid();
  }

  void _ensureInitialized() {
    if (_flutterApi != null) return;
    _flutterApi = _FlutterApi(this);
    messages.QuickBlueFlutterApi.setUp(_flutterApi);
  }

  @override
  Future<bool> isCompanionAssociationSupported() {
    _ensureInitialized();

    return _api.isCompanionAssociationSupported();
  }

  @override
  Future<CompanionAssociation?> companionAssociate(
    CompanionAssociationRequest request,
  ) async {
    _ensureInitialized();

    final association = await _api.companionAssociate(
      messages.PlatformCompanionAssociationRequest(
        filters: request.filters.map(_toPlatformBleCompanionFilter).toList(),
        singleDevice: request.singleDevice,
      ),
    );
    return association == null ? null : _toCompanionAssociation(association);
  }

  @override
  Future<void> companionDisassociate(int associationId) {
    _ensureInitialized();

    return _api.companionDisassociate(associationId);
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
  Future<void> connect(String deviceId) async {
    _ensureInitialized();
    try {
      await _api.connect(deviceId);
    } on PlatformException catch (error, stackTrace) {
      if (error.code != 'DeviceBusy') rethrow;
      Error.throwWithStackTrace(
        QuickBlueException(
          code: QuickBlueErrorCode.deviceBusy,
          operation: 'connect',
          deviceId: deviceId,
          message:
              error.message ??
              'The shared connection to $deviceId is temporarily unavailable.',
          details: error.details,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> disconnect(String deviceId) {
    _ensureInitialized();

    return _api.disconnect(deviceId);
  }

  @override
  Future<BluetoothBondState> bondState(String deviceId) async {
    _ensureInitialized();

    return (await _api.bondState(deviceId)).toBluetoothBondState();
  }

  @override
  Stream<BluetoothBondStateChange> get bondStateStream {
    _ensureInitialized();

    return _bondStateEvents;
  }

  @override
  Future<void> pair(String deviceId) {
    _ensureInitialized();

    return _api.pair(deviceId);
  }

  @override
  Future<void> discoverServices(String deviceId) {
    _ensureInitialized();

    return _api.discoverServices(deviceId);
  }

  @override
  Future<List<CompanionAssociation>> getCompanionAssociations() async {
    _ensureInitialized();

    final associations = await _api.getCompanionAssociations();
    return associations.map(_toCompanionAssociation).toList(growable: false);
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

    return BleL2capSocket(
      sink: _L2capSink(api: _api, deviceId: deviceId),
      stream: messages
          .l2CapSocketEvents()
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
  ) async {
    _ensureInitialized();

    final value = await _runGattOperation(
      operation: 'readValue',
      deviceId: deviceId,
      serviceId: service,
      characteristicId: characteristic,
      action: () => _api.readValue(deviceId, service, characteristic),
    );
    handleCharacteristicValueChanged(deviceId, service, characteristic, value);
    return value;
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

    return _runGattOperation(
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

    try {
      await _api.startScan(
        serviceUuids: scanFilter.serviceUuids,
        serviceData: scanFilter.serviceData,
        manufacturerData: scanFilter.manufacturerData,
        rssi: scanFilter.rssi,
        options: scanOptions.toPlatformAndroidScanOptions(),
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

    return _runGattOperation(
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

Future<T> _runGattOperation<T>({
  required String operation,
  required String deviceId,
  required String serviceId,
  required String characteristicId,
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } on PlatformException catch (error, stackTrace) {
    final status = error.details;
    if (error.code != 'GattError' || status is! num) {
      rethrow;
    }
    final nativeStatus = status.toInt();
    final securityReason = _androidSecurityReason(nativeStatus);
    if (securityReason != null) {
      Error.throwWithStackTrace(
        QuickBlueSecurityException(
          reason: securityReason,
          nativeDomain: 'android.bluetooth.BluetoothGatt',
          nativeCode: nativeStatus,
          operation: operation,
          deviceId: deviceId,
          serviceId: serviceId,
          characteristicId: characteristicId,
          message:
              error.message ??
              '$operation failed with GATT status $nativeStatus.',
        ),
        stackTrace,
      );
    }
    Error.throwWithStackTrace(
      QuickBlueGattException(
        status: nativeStatus,
        operation: operation,
        deviceId: deviceId,
        serviceId: serviceId,
        characteristicId: characteristicId,
        message: error.message ?? '$operation failed with GATT status $status.',
      ),
      stackTrace,
    );
  }
}

extension on ScanOptions {
  messages.PlatformAndroidScanOptions toPlatformAndroidScanOptions() {
    return messages.PlatformAndroidScanOptions(
      scanMode:
          (android.scanMode ??
                  scanMode?.toAndroidScanMode() ??
                  AndroidScanMode.lowLatency)
              .toPlatformAndroidScanMode(),
      callbackType: android.callbackType.toPlatformAndroidScanCallbackType(),
      matchMode: android.matchMode.toPlatformAndroidScanMatchMode(),
      numOfMatches: android.numOfMatches?.toPlatformAndroidScanNumOfMatches(),
      reportDelayMillis: android.reportDelay.inMilliseconds,
      legacy: android.legacy,
      phy: android.phy?.toPlatformAndroidScanPhy(),
    );
  }
}

extension on ScanMode {
  AndroidScanMode toAndroidScanMode() {
    return switch (this) {
      ScanMode.lowPower => AndroidScanMode.lowPower,
      ScanMode.balanced => AndroidScanMode.balanced,
      ScanMode.lowLatency => AndroidScanMode.lowLatency,
    };
  }
}

extension on AndroidScanMode {
  messages.PlatformAndroidScanMode toPlatformAndroidScanMode() {
    return switch (this) {
      AndroidScanMode.opportunistic =>
        messages.PlatformAndroidScanMode.opportunistic,
      AndroidScanMode.lowPower => messages.PlatformAndroidScanMode.lowPower,
      AndroidScanMode.balanced => messages.PlatformAndroidScanMode.balanced,
      AndroidScanMode.lowLatency => messages.PlatformAndroidScanMode.lowLatency,
    };
  }
}

extension on AndroidScanCallbackType {
  messages.PlatformAndroidScanCallbackType toPlatformAndroidScanCallbackType() {
    return switch (this) {
      AndroidScanCallbackType.allMatches =>
        messages.PlatformAndroidScanCallbackType.allMatches,
      AndroidScanCallbackType.firstMatch =>
        messages.PlatformAndroidScanCallbackType.firstMatch,
      AndroidScanCallbackType.matchLost =>
        messages.PlatformAndroidScanCallbackType.matchLost,
      AndroidScanCallbackType.firstMatchAndMatchLost =>
        messages.PlatformAndroidScanCallbackType.firstMatchAndMatchLost,
    };
  }
}

extension on AndroidScanMatchMode {
  messages.PlatformAndroidScanMatchMode toPlatformAndroidScanMatchMode() {
    return switch (this) {
      AndroidScanMatchMode.aggressive =>
        messages.PlatformAndroidScanMatchMode.aggressive,
      AndroidScanMatchMode.sticky =>
        messages.PlatformAndroidScanMatchMode.sticky,
    };
  }
}

extension on AndroidScanNumOfMatches {
  messages.PlatformAndroidScanNumOfMatches toPlatformAndroidScanNumOfMatches() {
    return switch (this) {
      AndroidScanNumOfMatches.one =>
        messages.PlatformAndroidScanNumOfMatches.one,
      AndroidScanNumOfMatches.few =>
        messages.PlatformAndroidScanNumOfMatches.few,
      AndroidScanNumOfMatches.max =>
        messages.PlatformAndroidScanNumOfMatches.max,
    };
  }
}

extension on AndroidScanPhy {
  messages.PlatformAndroidScanPhy toPlatformAndroidScanPhy() {
    return switch (this) {
      AndroidScanPhy.le1m => messages.PlatformAndroidScanPhy.le1m,
      AndroidScanPhy.leCoded => messages.PlatformAndroidScanPhy.leCoded,
      AndroidScanPhy.allSupported =>
        messages.PlatformAndroidScanPhy.allSupported,
    };
  }
}

messages.PlatformBleCompanionFilter _toPlatformBleCompanionFilter(
  BleCompanionFilter filter,
) {
  return messages.PlatformBleCompanionFilter(
    deviceId: filter.deviceId,
    namePattern: filter.namePattern,
    serviceUuids: filter.serviceUuids,
    manufacturerData: filter.manufacturerData,
  );
}

CompanionAssociation _toCompanionAssociation(
  messages.PlatformCompanionAssociation association,
) {
  return CompanionAssociation(
    id: association.id,
    deviceId: association.deviceId,
    displayName: association.displayName,
    deviceProfile: association.deviceProfile,
  );
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

  final QuickBlueAndroid platform;

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

BluetoothBondStateChange _bondStateChangeFromPlatform(
  messages.PlatformBondStateChange stateChange,
) {
  return BluetoothBondStateChange(
    deviceId: stateChange.deviceId,
    state: stateChange.state.toBluetoothBondState(),
    previousState: stateChange.previousState.toBluetoothBondState(),
  );
}

void _handleConnectionStateChange(
  QuickBluePlatform platform,
  messages.PlatformConnectionStateChange stateChange,
) {
  final state = stateChange.state.toBlueConnectionState();
  if (state == null) return;

  final nativeStatus = stateChange.nativeStatus;
  final securityReason = nativeStatus == null
      ? null
      : _androidSecurityReason(nativeStatus);
  final error = securityReason == null
      ? null
      : QuickBlueSecurityException(
          reason: securityReason,
          nativeDomain: 'android.bluetooth.BluetoothGatt',
          nativeCode: nativeStatus,
          operation: 'connection',
          deviceId: stateChange.deviceId,
          message: 'Connection failed with GATT status $nativeStatus.',
        );

  platform.handleConnectionStateChanged(
    stateChange.deviceId,
    state,
    stateChange.gattStatus.toBleStatus(),
    error: error,
  );
}

QuickBlueSecurityErrorReason? _androidSecurityReason(int nativeStatus) {
  return switch (nativeStatus) {
    5 => QuickBlueSecurityErrorReason.insufficientAuthentication,
    8 => QuickBlueSecurityErrorReason.insufficientAuthorization,
    12 => QuickBlueSecurityErrorReason.insufficientEncryptionKeySize,
    15 => QuickBlueSecurityErrorReason.insufficientEncryption,
    _ => null,
  };
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

extension _PlatformBondStateExtension on messages.PlatformBondState {
  BluetoothBondState toBluetoothBondState() {
    return switch (this) {
      messages.PlatformBondState.unknown => BluetoothBondState.unknown,
      messages.PlatformBondState.notBonded => BluetoothBondState.notBonded,
      messages.PlatformBondState.bonding => BluetoothBondState.bonding,
      messages.PlatformBondState.bonded => BluetoothBondState.bonded,
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
