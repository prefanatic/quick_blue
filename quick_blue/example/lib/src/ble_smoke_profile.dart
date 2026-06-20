import 'dart:convert';
import 'dart:typed_data';

const valveLighthouseSmokeProfileName = 'valve_lighthouse';

const _builtInProfiles = <String, BleSmokeProfile>{
  valveLighthouseSmokeProfileName: BleSmokeProfile(
    name: valveLighthouseSmokeProfileName,
    targetNamePattern: r'^(LHB-|Valve|Base Station|Lighthouse)',
    expectedManufacturerDataHex: '00 02',
    connect: false,
    read: false,
    maxConnectAttempts: 1,
  ),
};

class BleSmokeProfile {
  const BleSmokeProfile({
    this.name,
    this.targetDeviceId,
    this.targetNamePattern,
    this.serviceUuids = const <String>[],
    this.expectedAdvertisedServiceUuids = const <String>[],
    this.expectedServiceUuids = const <String>[],
    this.expectedManufacturerDataHex,
    this.expectedServiceDataHex = const <String, String>{},
    this.minRssi,
    this.connect,
    this.read,
    this.maxConnectAttempts,
  });

  final String? name;
  final String? targetDeviceId;
  final String? targetNamePattern;
  final List<String> serviceUuids;
  final List<String> expectedAdvertisedServiceUuids;
  final List<String> expectedServiceUuids;
  final String? expectedManufacturerDataHex;
  final Map<String, String> expectedServiceDataHex;
  final int? minRssi;
  final bool? connect;
  final bool? read;
  final int? maxConnectAttempts;

  bool get targetsDevice =>
      _isPresent(targetDeviceId) ||
      _isPresent(targetNamePattern) ||
      serviceUuids.isNotEmpty ||
      expectedAdvertisedServiceUuids.isNotEmpty ||
      expectedServiceUuids.isNotEmpty ||
      _isPresent(expectedManufacturerDataHex) ||
      expectedServiceDataHex.isNotEmpty ||
      minRssi != null;

  BleSmokeProfile merge(BleSmokeProfile override) {
    return BleSmokeProfile(
      name: override.name ?? name,
      targetDeviceId: _overrideString(targetDeviceId, override.targetDeviceId),
      targetNamePattern: _overrideString(
        targetNamePattern,
        override.targetNamePattern,
      ),
      serviceUuids: _overrideList(serviceUuids, override.serviceUuids),
      expectedAdvertisedServiceUuids: _overrideList(
        expectedAdvertisedServiceUuids,
        override.expectedAdvertisedServiceUuids,
      ),
      expectedServiceUuids: _overrideList(
        expectedServiceUuids,
        override.expectedServiceUuids,
      ),
      expectedManufacturerDataHex: _overrideString(
        expectedManufacturerDataHex,
        override.expectedManufacturerDataHex,
      ),
      expectedServiceDataHex: override.expectedServiceDataHex.isEmpty
          ? expectedServiceDataHex
          : override.expectedServiceDataHex,
      minRssi: override.minRssi ?? minRssi,
      connect: override.connect ?? connect,
      read: override.read ?? read,
      maxConnectAttempts: override.maxConnectAttempts ?? maxConnectAttempts,
    );
  }

  static BleSmokeProfile? builtIn(String name) {
    return _builtInProfiles[name.trim().toLowerCase()];
  }

  static BleSmokeProfile fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Smoke profile JSON must be an object.');
    }
    return BleSmokeProfile.fromMap(decoded);
  }

  factory BleSmokeProfile.fromMap(Map<String, Object?> map) {
    return BleSmokeProfile(
      name: _string(map, 'name'),
      targetDeviceId: _string(map, 'deviceId'),
      targetNamePattern: _string(map, 'namePattern'),
      serviceUuids: _stringList(map, 'serviceUuids'),
      expectedAdvertisedServiceUuids: _stringList(
        map,
        'expectedAdvertisedServiceUuids',
      ),
      expectedServiceUuids: _stringList(map, 'expectedServiceUuids'),
      expectedManufacturerDataHex: _string(map, 'expectedManufacturerDataHex'),
      expectedServiceDataHex: _stringMap(map, 'expectedServiceDataHex'),
      minRssi: _int(map, 'minRssi'),
      connect: _bool(map, 'connect'),
      read: _bool(map, 'read'),
      maxConnectAttempts: _int(map, 'maxConnectAttempts'),
    );
  }
}

Uint8List hexBytes(String value, String fieldName) {
  final cleaned = value.replaceAll(
    RegExp(r'0x|[\s:_-]', caseSensitive: false),
    '',
  );
  if (cleaned.isEmpty || cleaned.length.isOdd) {
    throw ArgumentError('$fieldName must contain hex bytes.');
  }

  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var index = 0; index < cleaned.length; index += 2) {
    final byte = int.tryParse(cleaned.substring(index, index + 2), radix: 16);
    if (byte == null) {
      throw ArgumentError('$fieldName contains non-hex characters.');
    }
    bytes[index ~/ 2] = byte;
  }
  return bytes;
}

List<String> csvList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool? boolFromString(String value, String fieldName) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  throw ArgumentError('$fieldName must be true or false.');
}

bool hasBytePrefix(Uint8List value, Uint8List prefix) {
  if (prefix.length > value.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index += 1) {
    if (value[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

String hexString(Uint8List value) {
  return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
}

bool _isPresent(String? value) => value != null && value.trim().isNotEmpty;

String? _overrideString(String? base, String? override) {
  return _isPresent(override) ? override : base;
}

List<String> _overrideList(List<String> base, List<String> override) {
  return override.isEmpty ? base : List<String>.unmodifiable(override);
}

String? _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('$key must be a string.');
}

int? _int(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$key must be an integer.');
}

bool? _bool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

List<String> _stringList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is String) {
    return csvList(value);
  }
  if (value is List<Object?>) {
    return value
        .map((item) {
          if (item is! String) {
            throw FormatException('$key must contain only strings.');
          }
          return item;
        })
        .toList(growable: false);
  }
  throw FormatException('$key must be a string or string list.');
}

Map<String, String> _stringMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return const <String, String>{};
  }
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object.');
  }
  return value.map((entryKey, entryValue) {
    if (entryValue is! String) {
      throw FormatException('$key values must be strings.');
    }
    return MapEntry(entryKey, entryValue);
  });
}
