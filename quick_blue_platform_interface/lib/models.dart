import 'dart:async';
import 'dart:typed_data';

final _empty = Uint8List.fromList(List.empty());

class BlueScanResult {
  final String name;
  final String deviceId;
  final Uint8List? _manufacturerDataHead;
  final Uint8List? _manufacturerData;
  final int rssi;
  final DateTime advertisedDateTime;
  final List<String> serviceUuids;
  final Map<String, Uint8List> serviceData;

  Uint8List get manufacturerDataHead => _manufacturerDataHead ?? _empty;

  /// The full manufacturer data when available, otherwise the advertised
  /// "head". Platforms that only surface advertisement data populate the head,
  /// so fall back to it when the full payload is absent (null or empty).
  Uint8List get manufacturerData {
    final data = _manufacturerData;
    return (data != null && data.isNotEmpty) ? data : manufacturerDataHead;
  }

  BlueScanResult({
    required this.name,
    required this.deviceId,
    Uint8List? manufacturerDataHead,
    Uint8List? manufacturerData,
    required this.rssi,
    DateTime? advertisedDateTime,
    this.serviceUuids = const [],
    this.serviceData = const <String, Uint8List>{},
  }) : _manufacturerDataHead = manufacturerDataHead ?? _empty,
       _manufacturerData = manufacturerData ?? _empty,
       advertisedDateTime = advertisedDateTime ?? DateTime.now();

  BlueScanResult.fromMap(Map<String, dynamic> map)
    : name = map['name'],
      deviceId = map['deviceId'],
      _manufacturerDataHead = map['manufacturerDataHead'],
      _manufacturerData = map['manufacturerData'],
      rssi = map['rssi'],
      advertisedDateTime = DateTime.now(),
      serviceUuids = map['serviceUuids']?.cast<String>() ?? <String>[],
      serviceData =
          map['serviceData']?.cast<String, Uint8List>() ??
          <String, Uint8List>{};

  Map<String, dynamic> toMap() => {
    'name': name,
    'deviceId': deviceId,
    'manufacturerDataHead': _manufacturerDataHead,
    'manufacturerData': _manufacturerData,
    'rssi': rssi,
    'advertisedDateTime': advertisedDateTime,
    'serviceUuids': serviceUuids,
    'serviceData': serviceData,
  };
}

class ScanFilter {
  const ScanFilter({this.serviceUuids = const [], this.manufacturerData});

  final List<String> serviceUuids;
  final Map<int, Uint8List>? manufacturerData;
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
}

class BluetoothService {
  BluetoothService({
    required this.deviceId,
    required this.uuid,
    required this.characteristics,
  });

  final String deviceId;
  final String uuid;
  final List<String> characteristics;
}

class BluetoothCharacteristicValue {
  BluetoothCharacteristicValue({
    required this.deviceId,
    required this.characteristicId,
    required this.value,
  });

  final String deviceId;
  final String characteristicId;
  final Uint8List value;
}

class BleInputProperty {
  static const disabled = BleInputProperty._('disabled');
  static const notification = BleInputProperty._('notification');
  static const indication = BleInputProperty._('indication');

  final String value;

  const BleInputProperty._(this.value);
}

class BleOutputProperty {
  static const withResponse = BleOutputProperty._('withResponse');
  static const withoutResponse = BleOutputProperty._('withoutResponse');

  final String value;

  const BleOutputProperty._(this.value);
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
}

class BleL2CapSocketEventData extends BleL2CapSocketEvent {
  BleL2CapSocketEventData({required super.deviceId, required this.data});

  final Uint8List data;
}

class BleL2CapSocketEventClosed extends BleL2CapSocketEvent {
  BleL2CapSocketEventClosed({required super.deviceId});
}

class BleL2CapSocketEventError extends BleL2CapSocketEvent {
  BleL2CapSocketEventError({required super.deviceId, this.error});

  final String? error;
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
  String toString() =>
      'CompanionDevice(id: $id, name: $name, associationId: $associationId)';
}
