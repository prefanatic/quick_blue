import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';

const _stringListEquality = ListEquality<String>();
const _deepEquality = DeepCollectionEquality();

/// Bluetooth adapter state.
enum BlueBluetoothState {
  /// The platform has not reported a known state yet.
  unknown,

  /// Bluetooth is not available on this device.
  unavailable,

  /// The app is not authorized to use Bluetooth.
  unauthorized,

  /// Bluetooth is available but powered off.
  poweredOff,

  /// Bluetooth is powered on and usable.
  poweredOn,
}

/// A Bluetooth LE advertisement result.
///
/// Byte payloads and collections are defensively copied.
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

  /// Creates a scan result from a platform event map.
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

  /// Advertised device name, or an empty string when absent.
  final String name;

  /// Platform-specific device identifier.
  final String deviceId;

  final Uint8List _manufacturerDataHead;
  final Uint8List _manufacturerData;

  /// Received signal strength in dBm.
  final int rssi;

  /// Time this advertisement was emitted to Dart.
  ///
  /// Defaults to `DateTime.now()` when the platform event has no timestamp.
  final DateTime advertisedDateTime;

  /// Advertised service UUIDs.
  final List<String> serviceUuids;

  final Map<String, Uint8List> _serviceData;

  /// Manufacturer data prefix when the platform exposes one separately.
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

  /// Service data keyed by service UUID.
  Map<String, Uint8List> get serviceData => _copyStringByteMap(_serviceData);

  /// Converts this result to a platform event map.
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

/// Filters used when scanning for advertisements.
///
/// Platforms may apply supported filters natively. The managed scan stream also
/// applies [rssi] in Dart so behavior is consistent.
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

  /// A filter that accepts all advertisements.
  static const empty = ScanFilter._empty();

  /// Service UUIDs to match.
  final List<String> serviceUuids;

  final Map<int, Uint8List>? _manufacturerData;

  /// Minimum RSSI in dBm.
  final int? rssi;

  /// Manufacturer data keyed by company identifier.
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

/// Common scan power/latency preference.
enum ScanMode {
  /// Favor lower power usage.
  lowPower,

  /// Balance power and discovery latency.
  balanced,

  /// Favor faster discovery.
  lowLatency,
}

/// Cross-platform and platform-specific scan options.
///
/// Common options are mapped to native options where possible. Platform-specific
/// options win when both are provided.
class ScanOptions {
  const ScanOptions({
    this.allowDuplicates,
    this.scanMode,
    this.android = const AndroidScanOptions(),
    this.darwin = DarwinScanOptions.defaults,
    this.linux = const LinuxScanOptions(),
    this.windows = const WindowsScanOptions(),
  });

  /// Default scan options.
  static const defaults = ScanOptions();

  /// Whether duplicate advertisements should be emitted.
  ///
  /// When false, managed scan streams suppress repeated device ids in Dart.
  final bool? allowDuplicates;

  /// Common scan mode mapped to each platform when possible.
  final ScanMode? scanMode;

  /// Android-specific scan options.
  ///
  /// These map to Android `ScanSettings` fields.
  final AndroidScanOptions android;

  /// iOS and macOS scan options.
  ///
  /// These map to CoreBluetooth scan options.
  final DarwinScanOptions darwin;

  /// Linux BlueZ scan options.
  ///
  /// These map to BlueZ discovery filters.
  final LinuxScanOptions linux;

  /// Windows scan options.
  ///
  /// These map to `BluetoothLEAdvertisementWatcher` options.
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

/// Android `ScanSettings` scan mode.
enum AndroidScanMode {
  /// Use Android opportunistic scanning.
  opportunistic,

  /// Favor lower power usage.
  lowPower,

  /// Balance power and discovery latency.
  balanced,

  /// Favor faster discovery.
  lowLatency,
}

/// Android scan callback type.
enum AndroidScanCallbackType {
  /// Report all matching advertisements.
  allMatches,

  /// Report the first match for each device.
  firstMatch,

  /// Report when a matched device is considered lost.
  matchLost,

  /// Report both first-match and match-lost events.
  firstMatchAndMatchLost,
}

/// Android scan match mode.
enum AndroidScanMatchMode {
  /// Match more aggressively.
  aggressive,

  /// Match more conservatively.
  sticky,
}

/// Android maximum advertisement matches.
enum AndroidScanNumOfMatches {
  /// Match one advertisement per filter.
  one,

  /// Match a small number of advertisements per filter.
  few,

  /// Match as many advertisements as Android allows.
  max,
}

/// Android LE PHY preference.
enum AndroidScanPhy {
  /// Use LE 1M PHY.
  le1m,

  /// Use LE coded PHY.
  leCoded,

  /// Use all supported PHYs.
  allSupported,
}

/// Android-specific scan options.
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

  /// Overrides the common [ScanOptions.scanMode] on Android.
  final AndroidScanMode? scanMode;

  /// Native scan callback type.
  final AndroidScanCallbackType callbackType;

  /// Native scan match mode.
  final AndroidScanMatchMode matchMode;

  /// Native maximum matches per filter.
  final AndroidScanNumOfMatches? numOfMatches;

  /// Native report delay.
  ///
  /// A non-zero value allows Android to batch scan results.
  final Duration reportDelay;

  /// Whether to restrict scanning to legacy advertisements.
  final bool? legacy;

  /// Native PHY preference.
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

/// iOS and macOS scan options.
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

  /// Default Darwin scan options.
  static const defaults = DarwinScanOptions._();

  /// Whether duplicate advertisements should be emitted.
  ///
  /// If null, the common [ScanOptions.allowDuplicates] value is used.
  final bool? allowDuplicates;

  /// Solicited service UUIDs passed to CoreBluetooth.
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

/// BlueZ discovery transport.
enum LinuxScanTransport {
  /// Let BlueZ choose the transport.
  auto,

  /// Use BR/EDR discovery.
  bredr,

  /// Use LE discovery.
  le,
}

/// Linux BlueZ scan options.
class LinuxScanOptions {
  const LinuxScanOptions({
    this.rssi,
    this.pathloss,
    this.transport = LinuxScanTransport.le,
    this.duplicateData,
    this.discoverable,
    this.pattern,
  });

  /// BlueZ RSSI discovery filter.
  final int? rssi;

  /// BlueZ pathloss discovery filter.
  final int? pathloss;

  /// BlueZ transport filter.
  final LinuxScanTransport transport;

  /// BlueZ duplicate data filter.
  ///
  /// When false, BlueZ may suppress repeated advertisement data.
  final bool? duplicateData;

  /// BlueZ discoverable filter.
  final bool? discoverable;

  /// BlueZ pattern filter.
  ///
  /// Matches device address or name according to BlueZ discovery filter rules.
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

/// Windows advertisement watcher scanning mode.
enum WindowsScanMode {
  /// Use passive scanning.
  passive,

  /// Use active scanning.
  active,

  /// Do not scan for advertisements.
  none,
}

/// Windows signal strength filter options.
class WindowsSignalStrengthFilter {
  const WindowsSignalStrengthFilter({
    this.inRangeThresholdInDBm,
    this.outOfRangeThresholdInDBm,
    this.outOfRangeTimeout,
    this.samplingInterval,
  });

  /// RSSI threshold for entering range.
  ///
  /// When [ScanFilter.rssi] is set and this is null, Windows uses that RSSI as
  /// the in-range threshold.
  final int? inRangeThresholdInDBm;

  /// RSSI threshold for leaving range.
  final int? outOfRangeThresholdInDBm;

  /// Delay before an out-of-range event is emitted.
  final Duration? outOfRangeTimeout;

  /// Sampling interval for signal strength changes.
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

/// Windows-specific scan options.
class WindowsScanOptions {
  const WindowsScanOptions({this.scanningMode, this.signalStrengthFilter});

  /// Native advertisement watcher scanning mode.
  final WindowsScanMode? scanningMode;

  /// Native signal strength filter.
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

/// Request for Android companion-device association.
///
/// Association shows the platform picker and may return null when the user
/// cancels.
class CompanionAssociationRequest {
  CompanionAssociationRequest({
    List<BleCompanionFilter> filters = const <BleCompanionFilter>[],
    this.singleDevice = true,
  }) : filters = List<BleCompanionFilter>.unmodifiable(filters);

  /// Creates a BLE companion association request.
  CompanionAssociationRequest.ble({
    List<BleCompanionFilter> filters = const <BleCompanionFilter>[],
    bool singleDevice = true,
  }) : this(filters: filters, singleDevice: singleDevice);

  /// Filters shown in the system companion-device picker.
  ///
  /// An empty list lets Android show any compatible BLE device.
  final List<BleCompanionFilter> filters;

  /// Whether the picker should allow only one selected device.
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

/// A BLE filter for Android companion-device association.
///
/// Multiple fields narrow the same picker filter rather than creating separate
/// alternatives.
class BleCompanionFilter {
  BleCompanionFilter({
    this.deviceId,
    this.namePattern,
    List<String> serviceUuids = const <String>[],
    Map<int, Uint8List>? manufacturerData,
  }) : serviceUuids = List<String>.unmodifiable(serviceUuids),
       _manufacturerData = _copyManufacturerData(manufacturerData);

  /// Exact device identifier to match.
  final String? deviceId;

  /// Regular expression matched against advertised device names.
  final String? namePattern;

  /// Service UUIDs to match.
  final List<String> serviceUuids;

  final Map<int, Uint8List>? _manufacturerData;

  /// Manufacturer data keyed by company identifier.
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

/// Device connection state.
class BlueConnectionState {
  /// The device is disconnected.
  static const disconnected = BlueConnectionState._('disconnected');

  /// The device is connected.
  static const connected = BlueConnectionState._('connected');

  /// String value used by platform messages.
  final String value;

  const BlueConnectionState._(this.value);

  /// Parses a platform connection state value.
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

/// Result status for BLE operations reported by the platform.
enum BleStatus {
  /// The operation succeeded.
  success,

  /// The operation failed.
  failure,
}

/// Device pairing/bonding state.
enum BluetoothBondState {
  /// The platform cannot currently determine the bond state.
  unknown,

  /// The device is not bonded with the host.
  notBonded,

  /// Pairing or bonding is in progress.
  bonding,

  /// The device is bonded with the host.
  bonded,
}

/// A connection state event for a Bluetooth LE device.
///
/// Connection operations complete from these events in the device API.
class BluetoothConnectionStateChange {
  BluetoothConnectionStateChange({
    required this.deviceId,
    required this.state,
    required this.status,
  });

  /// Platform-specific device identifier.
  final String deviceId;

  /// Reported connection state.
  final BlueConnectionState state;

  /// Whether the operation that produced this event succeeded.
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

/// A discovered GATT service.
///
/// Lists are immutable. Older platform callbacks may provide only
/// [characteristics], in which case [characteristicDetails] is synthesized with
/// all capability flags false.
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

  /// Platform-specific device identifier.
  final String deviceId;

  /// Service UUID.
  final String uuid;

  /// Characteristic UUIDs discovered under this service.
  final List<String> characteristics;

  /// Characteristic metadata discovered under this service.
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

/// Metadata for a discovered GATT characteristic.
///
/// Capability flags are best-effort and reflect what the platform discovered.
class BluetoothCharacteristicInfo {
  BluetoothCharacteristicInfo({
    required this.uuid,
    this.canRead = false,
    this.canWriteWithResponse = false,
    this.canWriteWithoutResponse = false,
    this.canNotify = false,
    this.canIndicate = false,
  });

  /// Characteristic UUID.
  final String uuid;

  /// Whether the characteristic can be read.
  final bool canRead;

  /// Whether the characteristic supports writes with response.
  final bool canWriteWithResponse;

  /// Whether the characteristic supports writes without response.
  final bool canWriteWithoutResponse;

  /// Whether the characteristic supports notifications.
  final bool canNotify;

  /// Whether the characteristic supports indications.
  final bool canIndicate;

  /// Whether either write mode is supported.
  bool get canWrite => canWriteWithResponse || canWriteWithoutResponse;

  /// Whether notifications or indications are supported.
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

/// A value update from a GATT characteristic.
///
/// [serviceId] is empty for legacy value callbacks that did not report the
/// service UUID.
class BluetoothCharacteristicValue {
  BluetoothCharacteristicValue({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
    required Uint8List value,
  }) : _value = _copyBytes(value);

  /// Platform-specific device identifier.
  final String deviceId;

  /// Service UUID.
  final String serviceId;

  /// Characteristic UUID.
  final String characteristicId;

  final Uint8List _value;

  /// Characteristic value bytes.
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

/// Characteristic subscription mode.
class BleInputProperty {
  /// Disable notifications or indications.
  static const disabled = BleInputProperty._('disabled');

  /// Enable notifications.
  static const notification = BleInputProperty._('notification');

  /// Enable indications.
  static const indication = BleInputProperty._('indication');

  /// String value used by platform messages.
  final String value;

  const BleInputProperty._(this.value);

  @override
  String toString() => value;
}

/// Characteristic write mode.
class BleOutputProperty {
  /// Write with response.
  static const withResponse = BleOutputProperty._('withResponse');

  /// Write without response.
  static const withoutResponse = BleOutputProperty._('withoutResponse');

  /// String value used by platform messages.
  final String value;

  const BleOutputProperty._(this.value);

  @override
  String toString() => value;
}

/// A BLE L2CAP socket.
///
/// Write outbound frames to [sink] and listen to [stream] for open, data,
/// error, and close events.
class BleL2capSocket {
  BleL2capSocket({required this.sink, required this.stream});

  /// Sink for outbound L2CAP frames.
  final EventSink<Uint8List> sink;

  /// Stream of inbound L2CAP events.
  final Stream<BleL2CapSocketEvent> stream;
}

/// Base class for L2CAP socket events.
///
/// Switch on the concrete subtype to handle socket state and data.
sealed class BleL2CapSocketEvent {
  BleL2CapSocketEvent({required this.deviceId});

  /// Platform-specific device identifier.
  final String deviceId;
}

/// Event emitted when an L2CAP socket opens.
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

/// Event emitted when L2CAP data is received.
class BleL2CapSocketEventData extends BleL2CapSocketEvent {
  BleL2CapSocketEventData({required super.deviceId, required Uint8List data})
    : _data = _copyBytes(data);

  final Uint8List _data;

  /// Received L2CAP frame bytes.
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

/// Event emitted when an L2CAP socket closes.
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

/// Event emitted when an L2CAP socket reports an error.
class BleL2CapSocketEventError extends BleL2CapSocketEvent {
  BleL2CapSocketEventError({required super.deviceId, this.error});

  /// Platform error message, when available.
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

/// Android companion-device association.
///
/// Values are whatever Android reports for the saved association; device id and
/// display name may be absent.
class CompanionAssociation {
  CompanionAssociation({
    required this.id,
    this.deviceId,
    this.displayName,
    this.deviceProfile,
  });

  /// Creates an association from a platform event map.
  CompanionAssociation.fromMap(Map map)
    : id = map['id'] as int,
      deviceId = map['deviceId'] as String?,
      displayName = map['displayName'] as String?,
      deviceProfile = map['deviceProfile'] as String?;

  /// Platform association identifier.
  final int id;

  /// Associated device identifier, when the platform reports one.
  final String? deviceId;

  /// Display name shown by the platform, when available.
  final String? displayName;

  /// Android device profile, when available.
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

/// Legacy Android companion-device association model.
@Deprecated('Use CompanionAssociation instead.')
class CompanionDevice {
  CompanionDevice({
    required this.id,
    required this.name,
    required this.associationId,
  });

  /// Creates a legacy companion device from a platform event map.
  CompanionDevice.fromMap(Map map)
    : id = map['id'] as String,
      name = map['name'] as String,
      associationId = map['associationId'] as int;

  /// Associated device identifier.
  final String id;

  /// Display name shown by the platform.
  final String name;

  /// Platform association identifier.
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
