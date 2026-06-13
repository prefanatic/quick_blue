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
  }) : serviceUuids = List<String>.unmodifiable(serviceUuids),
       _manufacturerData = _copyManufacturerData(manufacturerData);

  const ScanFilter._empty()
    : serviceUuids = const <String>[],
      _manufacturerData = null;

  static const empty = ScanFilter._empty();

  final List<String> serviceUuids;
  final Map<int, Uint8List>? _manufacturerData;

  Map<int, Uint8List>? get manufacturerData {
    final data = _manufacturerData;
    return data == null ? null : _copyManufacturerData(data);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScanFilter &&
            _stringListEquality.equals(serviceUuids, other.serviceUuids) &&
            _deepEquality.equals(_manufacturerData, other._manufacturerData);
  }

  @override
  int get hashCode {
    return Object.hash(
      _stringListEquality.hash(serviceUuids),
      _deepEquality.hash(_manufacturerData),
    );
  }

  @override
  String toString() {
    return 'ScanFilter('
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
  }) : characteristics = List<String>.unmodifiable(characteristics);

  final String deviceId;
  final String uuid;
  final List<String> characteristics;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BluetoothService &&
            other.deviceId == deviceId &&
            other.uuid == uuid &&
            _stringListEquality.equals(other.characteristics, characteristics);
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      uuid,
      _stringListEquality.hash(characteristics),
    );
  }

  @override
  String toString() {
    return 'BluetoothService('
        'deviceId: $deviceId, uuid: $uuid, characteristics: $characteristics'
        ')';
  }
}

class BluetoothCharacteristicValue {
  BluetoothCharacteristicValue({
    required this.deviceId,
    required this.characteristicId,
    required Uint8List value,
  }) : _value = _copyBytes(value);

  final String deviceId;
  final String characteristicId;
  final Uint8List _value;

  Uint8List get value => _copyBytes(_value);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BluetoothCharacteristicValue &&
            other.deviceId == deviceId &&
            other.characteristicId == characteristicId &&
            _deepEquality.equals(other._value, _value);
  }

  @override
  int get hashCode {
    return Object.hash(deviceId, characteristicId, _deepEquality.hash(_value));
  }

  @override
  String toString() {
    return 'BluetoothCharacteristicValue('
        'deviceId: $deviceId, '
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
