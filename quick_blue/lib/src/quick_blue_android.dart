import 'dart:async';
import 'dart:typed_data';

import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'messages.g.dart' as messages;

class QuickBlueAndroid extends QuickBluePlatform {
  QuickBlueAndroid();

  final messages.QuickBlueApi _api = messages.QuickBlueApi();
  messages.QuickBlueFlutterApi? _flutterApi;
  late final Stream<BlueBluetoothState> _bluetoothStateStream = messages
      .bluetoothState()
      .map((state) => state.toBlueBluetoothState())
      .distinct();
  late final Stream<BlueScanResult> _scanResultStream = messages
      .scanResults()
      .map(_scanResultFromPlatformResult);

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
    _ensureInitialized();

    return (await _api.bondState(deviceId)).toBluetoothBondState();
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
  Stream<BlueBluetoothState> get bluetoothStateStream {
    _ensureInitialized();

    return _bluetoothStateStream;
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
  ) {
    _ensureInitialized();

    return _api.readValue(deviceId, service, characteristic);
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

    return _api.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty.toPlatformBleInputProperty(),
    );
  }

  @override
  Future<void> startScan({
    ScanFilter scanFilter = ScanFilter.empty,
    ScanOptions scanOptions = ScanOptions.defaults,
  }) {
    _ensureInitialized();

    return _api.startScan(
      serviceUuids: scanFilter.serviceUuids,
      manufacturerData: scanFilter.manufacturerData,
      rssi: scanFilter.rssi,
      options: scanOptions.toPlatformAndroidScanOptions(),
    );
  }

  @override
  Future<void> stopScan() {
    _ensureInitialized();

    return _api.stopScan();
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

    return _api.writeValue(
      deviceId,
      service,
      characteristic,
      value,
      bleOutputProperty.toPlatformBleOutputProperty(),
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
  Future close() async {}
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

void _handleConnectionStateChange(
  QuickBluePlatform platform,
  messages.PlatformConnectionStateChange stateChange,
) {
  final state = stateChange.state.toBlueConnectionState();
  if (state == null) return;

  platform.onConnectionChanged?.call(
    stateChange.deviceId,
    state,
    stateChange.gattStatus.toBleStatus(),
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
