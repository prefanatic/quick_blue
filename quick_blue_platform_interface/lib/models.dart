import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';

const _stringListEquality = ListEquality<String>();
const _deepEquality = DeepCollectionEquality();

enum BlueBluetoothState {
  unknown,
  unavailable,
  unauthorized,
  poweredOff,
  poweredOn,
}

class BlueScanResult {
  BlueScanResult({
    required this.name,
    required this.deviceId,
    Uint8List? manufacturerDataHead,
    Uint8List? manufacturerData,
    required this.rssi,
    DateTime? advertisedDateTime,
    List<String> serviceUuids = const [],
    Map<String, Uint8List> serviceData = const <String, Uint8List>{},
  }) : _manufacturerDataHead = _copyBytes(manufacturerDataHead),
       _manufacturerData = _copyBytes(manufacturerData),
       advertisedDateTime = advertisedDateTime ?? DateTime.now(),
       serviceUuids = List<String>.unmodifiable(serviceUuids),
       _serviceData = _copyStringByteMap(serviceData);

  BlueScanResult.fromMap(Map<String, dynamic> map)
    : name = map['name'],
      deviceId = map['deviceId'],
      _manufacturerDataHead = _copyBytes(map['manufacturerDataHead']),
      _manufacturerData = _copyBytes(map['manufacturerData']),
      rssi = map['rssi'],
      advertisedDateTime =
          map['advertisedDateTime'] as DateTime? ?? DateTime.now(),
      serviceUuids = List<String>.unmodifiable(
        map['serviceUuids']?.cast<String>() ?? <String>[],
      ),
      _serviceData = _copyStringByteMap(
        map['serviceData']?.cast<String, Uint8List>() ?? <String, Uint8List>{},
      );

  final String name;
  final String deviceId;
  final Uint8List _manufacturerDataHead;
  final Uint8List _manufacturerData;
  final int rssi;
  final DateTime advertisedDateTime;
  final List<String> serviceUuids;
  final Map<String, Uint8List> _serviceData;

  Uint8List get manufacturerDataHead => _copyBytes(_manufacturerDataHead);

  /// The full manufacturer data when available, otherwise the advertised
  /// "head". Platforms that only surface advertisement data populate the head,
  /// so fall back to it when the full payload is absent (null or empty).
  Uint8List get manufacturerData {
    final data = _manufacturerData.isNotEmpty
        ? _manufacturerData
        : _manufacturerDataHead;
    return _copyBytes(data);
  }

  Map<String, Uint8List> get serviceData => _copyStringByteMap(_serviceData);

  Map<String, dynamic> toMap() => {
    'name': name,
    'deviceId': deviceId,
    'manufacturerDataHead': manufacturerDataHead,
    'manufacturerData': _copyBytes(_manufacturerData),
    'rssi': rssi,
    'advertisedDateTime': advertisedDateTime,
    'serviceUuids': serviceUuids,
    'serviceData': serviceData,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BlueScanResult &&
            other.name == name &&
            other.deviceId == deviceId &&
            _deepEquality.equals(
              other._manufacturerDataHead,
              _manufacturerDataHead,
            ) &&
            _deepEquality.equals(other._manufacturerData, _manufacturerData) &&
            other.rssi == rssi &&
            other.advertisedDateTime == advertisedDateTime &&
            _stringListEquality.equals(other.serviceUuids, serviceUuids) &&
            _deepEquality.equals(other._serviceData, _serviceData);
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      deviceId,
      _deepEquality.hash(_manufacturerDataHead),
      _deepEquality.hash(_manufacturerData),
      rssi,
      advertisedDateTime,
      _stringListEquality.hash(serviceUuids),
      _deepEquality.hash(_serviceData),
    );
  }

  @override
  String toString() {
    return 'BlueScanResult('
        'name: $name, '
        'deviceId: $deviceId, '
        'manufacturerDataHead: ${_manufacturerDataHead.toList()}, '
        'manufacturerData: ${_manufacturerData.toList()}, '
        'rssi: $rssi, '
        'advertisedDateTime: $advertisedDateTime, '
        'serviceUuids: $serviceUuids, '
        'serviceData: ${_stringByteMapToString(_serviceData)}'
        ')';
  }
}

class ScanFilter {
  ScanFilter({
    List<String> serviceUuids = const [],
    Map<int, Uint8List>? manufacturerData,
    this.rssi,
  }) : serviceUuids = List<String>.unmodifiable(serviceUuids),
       _manufacturerData = _copyManufacturerData(manufacturerData);

  const ScanFilter._empty()
    : serviceUuids = const <String>[],
      _manufacturerData = null,
      rssi = null;

  static const empty = ScanFilter._empty();

  final List<String> serviceUuids;
  final Map<int, Uint8List>? _manufacturerData;
  final int? rssi;

  Map<int, Uint8List>? get manufacturerData {
    final data = _manufacturerData;
    return data == null ? null : _copyManufacturerData(data);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScanFilter &&
            _stringListEquality.equals(serviceUuids, other.serviceUuids) &&
            _deepEquality.equals(_manufacturerData, other._manufacturerData) &&
            other.rssi == rssi;
  }

  @override
  int get hashCode {
    return Object.hash(
      _stringListEquality.hash(serviceUuids),
      _deepEquality.hash(_manufacturerData),
      rssi,
    );
  }

  @override
  String toString() {
    return 'ScanFilter('
        'serviceUuids: $serviceUuids, '
        'manufacturerData: ${_intByteMapToString(_manufacturerData)}, '
        'rssi: $rssi'
        ')';
  }
}

enum ScanMode { lowPower, balanced, lowLatency }

class ScanOptions {
  const ScanOptions({
    this.allowDuplicates,
    this.scanMode,
    this.android = const AndroidScanOptions(),
    this.darwin = DarwinScanOptions.defaults,
    this.linux = const LinuxScanOptions(),
    this.windows = const WindowsScanOptions(),
  });

  static const defaults = ScanOptions();

  final bool? allowDuplicates;
  final ScanMode? scanMode;
  final AndroidScanOptions android;
  final DarwinScanOptions darwin;
  final LinuxScanOptions linux;
  final WindowsScanOptions windows;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScanOptions &&
            other.allowDuplicates == allowDuplicates &&
            other.scanMode == scanMode &&
            other.android == android &&
            other.darwin == darwin &&
            other.linux == linux &&
            other.windows == windows;
  }

  @override
  int get hashCode {
    return Object.hash(
      allowDuplicates,
      scanMode,
      android,
      darwin,
      linux,
      windows,
    );
  }

  @override
  String toString() {
    return 'ScanOptions('
        'allowDuplicates: $allowDuplicates, '
        'scanMode: $scanMode, '
        'android: $android, '
        'darwin: $darwin, '
        'linux: $linux, '
        'windows: $windows'
        ')';
  }
}

enum AndroidScanMode { opportunistic, lowPower, balanced, lowLatency }

enum AndroidScanCallbackType {
  allMatches,
  firstMatch,
  matchLost,
  firstMatchAndMatchLost,
}

enum AndroidScanMatchMode { aggressive, sticky }

enum AndroidScanNumOfMatches { one, few, max }

enum AndroidScanPhy { le1m, leCoded, allSupported }

class AndroidScanOptions {
  const AndroidScanOptions({
    this.scanMode,
    this.callbackType = AndroidScanCallbackType.allMatches,
    this.matchMode = AndroidScanMatchMode.sticky,
    this.numOfMatches,
    this.reportDelay = Duration.zero,
    this.legacy,
    this.phy,
  });

  final AndroidScanMode? scanMode;
  final AndroidScanCallbackType callbackType;
  final AndroidScanMatchMode matchMode;
  final AndroidScanNumOfMatches? numOfMatches;
  final Duration reportDelay;
  final bool? legacy;
  final AndroidScanPhy? phy;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AndroidScanOptions &&
            other.scanMode == scanMode &&
            other.callbackType == callbackType &&
            other.matchMode == matchMode &&
            other.numOfMatches == numOfMatches &&
            other.reportDelay == reportDelay &&
            other.legacy == legacy &&
            other.phy == phy;
  }

  @override
  int get hashCode {
    return Object.hash(
      scanMode,
      callbackType,
      matchMode,
      numOfMatches,
      reportDelay,
      legacy,
      phy,
    );
  }

  @override
  String toString() {
    return 'AndroidScanOptions('
        'scanMode: $scanMode, '
        'callbackType: $callbackType, '
        'matchMode: $matchMode, '
        'numOfMatches: $numOfMatches, '
        'reportDelay: $reportDelay, '
        'legacy: $legacy, '
        'phy: $phy'
        ')';
  }
}

class DarwinScanOptions {
  factory DarwinScanOptions({
    bool? allowDuplicates,
    List<String> solicitedServiceUuids = const <String>[],
  }) {
    return DarwinScanOptions._(
      allowDuplicates: allowDuplicates,
      solicitedServiceUuids: List<String>.unmodifiable(solicitedServiceUuids),
    );
  }

  const DarwinScanOptions._({
    this.allowDuplicates,
    this.solicitedServiceUuids = const <String>[],
  });

  static const defaults = DarwinScanOptions._();

  final bool? allowDuplicates;
  final List<String> solicitedServiceUuids;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DarwinScanOptions &&
            other.allowDuplicates == allowDuplicates &&
            _stringListEquality.equals(
              solicitedServiceUuids,
              other.solicitedServiceUuids,
            );
  }

  @override
  int get hashCode {
    return Object.hash(
      allowDuplicates,
      _stringListEquality.hash(solicitedServiceUuids),
    );
  }

  @override
  String toString() {
    return 'DarwinScanOptions('
        'allowDuplicates: $allowDuplicates, '
        'solicitedServiceUuids: $solicitedServiceUuids'
        ')';
  }
}

enum LinuxScanTransport { auto, bredr, le }

class LinuxScanOptions {
  const LinuxScanOptions({
    this.rssi,
    this.pathloss,
    this.transport = LinuxScanTransport.le,
    this.duplicateData,
    this.discoverable,
    this.pattern,
  });

  final int? rssi;
  final int? pathloss;
  final LinuxScanTransport transport;
  final bool? duplicateData;
  final bool? discoverable;
  final String? pattern;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LinuxScanOptions &&
            other.rssi == rssi &&
            other.pathloss == pathloss &&
            other.transport == transport &&
            other.duplicateData == duplicateData &&
            other.discoverable == discoverable &&
            other.pattern == pattern;
  }

  @override
  int get hashCode {
    return Object.hash(
      rssi,
      pathloss,
      transport,
      duplicateData,
      discoverable,
      pattern,
    );
  }

  @override
  String toString() {
    return 'LinuxScanOptions('
        'rssi: $rssi, '
        'pathloss: $pathloss, '
        'transport: $transport, '
        'duplicateData: $duplicateData, '
        'discoverable: $discoverable, '
        'pattern: $pattern'
        ')';
  }
}

enum WindowsScanMode { passive, active, none }

class WindowsSignalStrengthFilter {
  const WindowsSignalStrengthFilter({
    this.inRangeThresholdInDBm,
    this.outOfRangeThresholdInDBm,
    this.outOfRangeTimeout,
    this.samplingInterval,
  });

  final int? inRangeThresholdInDBm;
  final int? outOfRangeThresholdInDBm;
  final Duration? outOfRangeTimeout;
  final Duration? samplingInterval;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WindowsSignalStrengthFilter &&
            other.inRangeThresholdInDBm == inRangeThresholdInDBm &&
            other.outOfRangeThresholdInDBm == outOfRangeThresholdInDBm &&
            other.outOfRangeTimeout == outOfRangeTimeout &&
            other.samplingInterval == samplingInterval;
  }

  @override
  int get hashCode {
    return Object.hash(
      inRangeThresholdInDBm,
      outOfRangeThresholdInDBm,
      outOfRangeTimeout,
      samplingInterval,
    );
  }

  @override
  String toString() {
    return 'WindowsSignalStrengthFilter('
        'inRangeThresholdInDBm: $inRangeThresholdInDBm, '
        'outOfRangeThresholdInDBm: $outOfRangeThresholdInDBm, '
        'outOfRangeTimeout: $outOfRangeTimeout, '
        'samplingInterval: $samplingInterval'
        ')';
  }
}

class WindowsScanOptions {
  const WindowsScanOptions({this.scanningMode, this.signalStrengthFilter});

  final WindowsScanMode? scanningMode;
  final WindowsSignalStrengthFilter? signalStrengthFilter;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WindowsScanOptions &&
            other.scanningMode == scanningMode &&
            other.signalStrengthFilter == signalStrengthFilter;
  }

  @override
  int get hashCode => Object.hash(scanningMode, signalStrengthFilter);

  @override
  String toString() {
    return 'WindowsScanOptions('
        'scanningMode: $scanningMode, '
        'signalStrengthFilter: $signalStrengthFilter'
        ')';
  }
}

class CompanionAssociationRequest {
  CompanionAssociationRequest({
    List<BleCompanionFilter> filters = const <BleCompanionFilter>[],
    this.singleDevice = true,
  }) : filters = List<BleCompanionFilter>.unmodifiable(filters);

  CompanionAssociationRequest.ble({
    List<BleCompanionFilter> filters = const <BleCompanionFilter>[],
    bool singleDevice = true,
  }) : this(filters: filters, singleDevice: singleDevice);

  final List<BleCompanionFilter> filters;
  final bool singleDevice;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CompanionAssociationRequest &&
            _deepEquality.equals(filters, other.filters) &&
            other.singleDevice == singleDevice;
  }

  @override
  int get hashCode => Object.hash(_deepEquality.hash(filters), singleDevice);

  @override
  String toString() {
    return 'CompanionAssociationRequest('
        'filters: $filters, '
        'singleDevice: $singleDevice'
        ')';
  }
}

class BleCompanionFilter {
  BleCompanionFilter({
    this.deviceId,
    this.namePattern,
    List<String> serviceUuids = const <String>[],
    Map<int, Uint8List>? manufacturerData,
  }) : serviceUuids = List<String>.unmodifiable(serviceUuids),
       _manufacturerData = _copyManufacturerData(manufacturerData);

  final String? deviceId;
  final String? namePattern;
  final List<String> serviceUuids;
  final Map<int, Uint8List>? _manufacturerData;

  Map<int, Uint8List>? get manufacturerData {
    final data = _manufacturerData;
    return data == null ? null : _copyManufacturerData(data);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleCompanionFilter &&
            other.deviceId == deviceId &&
            other.namePattern == namePattern &&
            _stringListEquality.equals(serviceUuids, other.serviceUuids) &&
            _deepEquality.equals(_manufacturerData, other._manufacturerData);
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      namePattern,
      _stringListEquality.hash(serviceUuids),
      _deepEquality.hash(_manufacturerData),
    );
  }

  @override
  String toString() {
    return 'BleCompanionFilter('
        'deviceId: $deviceId, '
        'namePattern: $namePattern, '
        'serviceUuids: $serviceUuids, '
        'manufacturerData: ${_intByteMapToString(_manufacturerData)}'
        ')';
  }
}

Uint8List _copyBytes(Object? bytes) {
  if (bytes == null) {
    return Uint8List(0);
  }

  return Uint8List.fromList((bytes as Uint8List));
}

Map<int, Uint8List>? _copyManufacturerData(
  Map<int, Uint8List>? manufacturerData,
) {
  if (manufacturerData == null || manufacturerData.isEmpty) {
    return null;
  }

  return Map<int, Uint8List>.unmodifiable(
    manufacturerData.map(
      (manufacturerId, data) =>
          MapEntry(manufacturerId, Uint8List.fromList(data)),
    ),
  );
}

Map<String, Uint8List> _copyStringByteMap(Map<String, Uint8List> data) {
  if (data.isEmpty) {
    return const <String, Uint8List>{};
  }

  return Map<String, Uint8List>.unmodifiable(
    data.map((key, value) => MapEntry(key, Uint8List.fromList(value))),
  );
}

String _intByteMapToString(Map<int, Uint8List>? data) {
  if (data == null) {
    return 'null';
  }

  return data.map((key, value) => MapEntry(key, value.toList())).toString();
}

String _stringByteMapToString(Map<String, Uint8List> data) {
  return data.map((key, value) => MapEntry(key, value.toList())).toString();
}

class BlueConnectionState {
  static const disconnected = BlueConnectionState._('disconnected');
  static const connected = BlueConnectionState._('connected');

  final String value;

  const BlueConnectionState._(this.value);

  static BlueConnectionState parse(String value) {
    if (value == disconnected.value) {
      return disconnected;
    } else if (value == connected.value) {
      return connected;
    }
    throw ArgumentError.value(value);
  }

  @override
  String toString() => value;
}

enum BleStatus { success, failure }

class BluetoothConnectionStateChange {
  BluetoothConnectionStateChange({
    required this.deviceId,
    required this.state,
    required this.status,
  });

  final String deviceId;
  final BlueConnectionState state;
  final BleStatus status;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BluetoothConnectionStateChange &&
            other.deviceId == deviceId &&
            other.state == state &&
            other.status == status;
  }

  @override
  int get hashCode => Object.hash(deviceId, state, status);

  @override
  String toString() {
    return 'BluetoothConnectionStateChange('
        'deviceId: $deviceId, state: $state, status: $status'
        ')';
  }
}

class BluetoothService {
  BluetoothService({
    required this.deviceId,
    required this.uuid,
    required List<String> characteristics,
    List<BluetoothCharacteristicInfo>? characteristicDetails,
  }) : characteristics = List<String>.unmodifiable(characteristics),
       characteristicDetails = List<BluetoothCharacteristicInfo>.unmodifiable(
         characteristicDetails ??
             characteristics.map(
               (uuid) => BluetoothCharacteristicInfo(uuid: uuid),
             ),
       );

  final String deviceId;
  final String uuid;
  final List<String> characteristics;
  final List<BluetoothCharacteristicInfo> characteristicDetails;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BluetoothService &&
            other.deviceId == deviceId &&
            other.uuid == uuid &&
            _stringListEquality.equals(
              other.characteristics,
              characteristics,
            ) &&
            const ListEquality<BluetoothCharacteristicInfo>().equals(
              other.characteristicDetails,
              characteristicDetails,
            );
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      uuid,
      _stringListEquality.hash(characteristics),
      const ListEquality<BluetoothCharacteristicInfo>().hash(
        characteristicDetails,
      ),
    );
  }

  @override
  String toString() {
    return 'BluetoothService('
        'deviceId: $deviceId, uuid: $uuid, characteristics: $characteristics'
        ', characteristicDetails: $characteristicDetails'
        ')';
  }
}

class BluetoothCharacteristicInfo {
  BluetoothCharacteristicInfo({
    required this.uuid,
    this.canRead = false,
    this.canWriteWithResponse = false,
    this.canWriteWithoutResponse = false,
    this.canNotify = false,
    this.canIndicate = false,
  });

  final String uuid;
  final bool canRead;
  final bool canWriteWithResponse;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;

  bool get canWrite => canWriteWithResponse || canWriteWithoutResponse;

  bool get canSubscribe => canNotify || canIndicate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BluetoothCharacteristicInfo &&
            other.uuid == uuid &&
            other.canRead == canRead &&
            other.canWriteWithResponse == canWriteWithResponse &&
            other.canWriteWithoutResponse == canWriteWithoutResponse &&
            other.canNotify == canNotify &&
            other.canIndicate == canIndicate;
  }

  @override
  int get hashCode {
    return Object.hash(
      uuid,
      canRead,
      canWriteWithResponse,
      canWriteWithoutResponse,
      canNotify,
      canIndicate,
    );
  }

  @override
  String toString() {
    return 'BluetoothCharacteristicInfo('
        'uuid: $uuid, '
        'canRead: $canRead, '
        'canWriteWithResponse: $canWriteWithResponse, '
        'canWriteWithoutResponse: $canWriteWithoutResponse, '
        'canNotify: $canNotify, '
        'canIndicate: $canIndicate'
        ')';
  }
}

class BluetoothCharacteristicValue {
  BluetoothCharacteristicValue({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required Uint8List value,
  }) : _value = _copyBytes(value);

  final String deviceId;
  final String serviceId;
  final String characteristicId;
  final Uint8List _value;

  Uint8List get value => _copyBytes(_value);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BluetoothCharacteristicValue &&
            other.deviceId == deviceId &&
            other.serviceId == serviceId &&
            other.characteristicId == characteristicId &&
            _deepEquality.equals(other._value, _value);
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      serviceId,
      characteristicId,
      _deepEquality.hash(_value),
    );
  }

  @override
  String toString() {
    return 'BluetoothCharacteristicValue('
        'deviceId: $deviceId, '
        'serviceId: $serviceId, '
        'characteristicId: $characteristicId, '
        'value: ${_value.toList()}'
        ')';
  }
}

class BleInputProperty {
  static const disabled = BleInputProperty._('disabled');
  static const notification = BleInputProperty._('notification');
  static const indication = BleInputProperty._('indication');

  final String value;

  const BleInputProperty._(this.value);

  @override
  String toString() => value;
}

class BleOutputProperty {
  static const withResponse = BleOutputProperty._('withResponse');
  static const withoutResponse = BleOutputProperty._('withoutResponse');

  final String value;

  const BleOutputProperty._(this.value);

  @override
  String toString() => value;
}

class BleL2capSocket {
  BleL2capSocket({required this.sink, required this.stream});

  final EventSink<Uint8List> sink;
  final Stream<BleL2CapSocketEvent> stream;
}

sealed class BleL2CapSocketEvent {
  BleL2CapSocketEvent({required this.deviceId});

  final String deviceId;
}

class BleL2CapSocketEventOpened extends BleL2CapSocketEvent {
  BleL2CapSocketEventOpened({required super.deviceId});

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleL2CapSocketEventOpened && other.deviceId == deviceId;
  }

  @override
  int get hashCode => Object.hash(BleL2CapSocketEventOpened, deviceId);

  @override
  String toString() => 'BleL2CapSocketEventOpened(deviceId: $deviceId)';
}

class BleL2CapSocketEventData extends BleL2CapSocketEvent {
  BleL2CapSocketEventData({required super.deviceId, required Uint8List data})
    : _data = _copyBytes(data);

  final Uint8List _data;

  Uint8List get data => _copyBytes(_data);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleL2CapSocketEventData &&
            other.deviceId == deviceId &&
            _deepEquality.equals(other._data, _data);
  }

  @override
  int get hashCode =>
      Object.hash(BleL2CapSocketEventData, deviceId, _deepEquality.hash(_data));

  @override
  String toString() {
    return 'BleL2CapSocketEventData('
        'deviceId: $deviceId, data: ${_data.toList()}'
        ')';
  }
}

class BleL2CapSocketEventClosed extends BleL2CapSocketEvent {
  BleL2CapSocketEventClosed({required super.deviceId});

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleL2CapSocketEventClosed && other.deviceId == deviceId;
  }

  @override
  int get hashCode => Object.hash(BleL2CapSocketEventClosed, deviceId);

  @override
  String toString() => 'BleL2CapSocketEventClosed(deviceId: $deviceId)';
}

class BleL2CapSocketEventError extends BleL2CapSocketEvent {
  BleL2CapSocketEventError({required super.deviceId, this.error});

  final String? error;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleL2CapSocketEventError &&
            other.deviceId == deviceId &&
            other.error == error;
  }

  @override
  int get hashCode => Object.hash(BleL2CapSocketEventError, deviceId, error);

  @override
  String toString() {
    return 'BleL2CapSocketEventError(deviceId: $deviceId, error: $error)';
  }
}

class CompanionAssociation {
  CompanionAssociation({
    required this.id,
    this.deviceId,
    this.displayName,
    this.deviceProfile,
  });

  CompanionAssociation.fromMap(Map map)
    : id = map['id'] as int,
      deviceId = map['deviceId'] as String?,
      displayName = map['displayName'] as String?,
      deviceProfile = map['deviceProfile'] as String?;

  final int id;
  final String? deviceId;
  final String? displayName;
  final String? deviceProfile;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CompanionAssociation &&
            other.id == id &&
            other.deviceId == deviceId &&
            other.displayName == displayName &&
            other.deviceProfile == deviceProfile;
  }

  @override
  int get hashCode => Object.hash(id, deviceId, displayName, deviceProfile);

  @override
  String toString() {
    return 'CompanionAssociation('
        'id: $id, '
        'deviceId: $deviceId, '
        'displayName: $displayName, '
        'deviceProfile: $deviceProfile'
        ')';
  }
}

@Deprecated('Use CompanionAssociation instead.')
class CompanionDevice {
  CompanionDevice({
    required this.id,
    required this.name,
    required this.associationId,
  });

  CompanionDevice.fromMap(Map map)
    : id = map['id'] as String,
      name = map['name'] as String,
      associationId = map['associationId'] as int;

  final String id;
  final String name;
  final int associationId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CompanionDevice &&
            other.id == id &&
            other.name == name &&
            other.associationId == associationId;
  }

  @override
  int get hashCode => Object.hash(id, name, associationId);

  @override
  String toString() =>
      'CompanionDevice(id: $id, name: $name, associationId: $associationId)';
}
