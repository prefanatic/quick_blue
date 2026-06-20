import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue_example/src/ble_smoke_profile.dart';
import 'package:quick_blue/quick_blue.dart';

const _scanSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_SCAN_SECONDS',
  defaultValue: 12,
);
const _connectTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_CONNECT_TIMEOUT_SECONDS',
  defaultValue: 12,
);
const _serviceTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_SERVICE_TIMEOUT_SECONDS',
  defaultValue: 15,
);
const _readTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_READ_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _writeTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_WRITE_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _disconnectTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_DISCONNECT_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _bluetoothReadyTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_BLUETOOTH_READY_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _maxConnectAttempts = int.fromEnvironment(
  'QUICK_BLUE_SMOKE_MAX_CONNECT_ATTEMPTS',
  defaultValue: 3,
);
const _targetDeviceId = String.fromEnvironment('QUICK_BLUE_SMOKE_DEVICE_ID');
const _targetNamePattern = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_NAME_PATTERN',
);
const _profileName = String.fromEnvironment('QUICK_BLUE_SMOKE_PROFILE');
const _profileJson = String.fromEnvironment('QUICK_BLUE_SMOKE_PROFILE_JSON');
const _serviceUuidCsv = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_SERVICE_UUIDS',
);
const _expectedAdvertisedServiceUuidCsv = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_EXPECTED_ADVERTISED_SERVICE_UUIDS',
);
const _expectedServiceUuidCsv = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_EXPECTED_SERVICE_UUIDS',
);
const _expectedManufacturerDataHex = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_EXPECTED_MANUFACTURER_DATA_HEX',
);
const _minRssi = int.fromEnvironment('QUICK_BLUE_SMOKE_MIN_RSSI');
const _connect = String.fromEnvironment('QUICK_BLUE_SMOKE_CONNECT');
const _read = String.fromEnvironment('QUICK_BLUE_SMOKE_READ');
const _dumpAdvertisements = bool.fromEnvironment(
  'QUICK_BLUE_SMOKE_DUMP_ADVERTISEMENTS',
);
const _writeServiceUuid = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_WRITE_SERVICE_UUID',
);
const _writeCharacteristicUuid = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_WRITE_CHARACTERISTIC_UUID',
);
const _writeValueHex = String.fromEnvironment('QUICK_BLUE_SMOKE_WRITE_HEX');
const _writeWithoutResponse = bool.fromEnvironment(
  'QUICK_BLUE_SMOKE_WRITE_WITHOUT_RESPONSE',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'BLE explorer scans, connects, discovers services, reads, optionally writes, and disconnects',
    (_) async {
      if (!_supportsBleSmoke(defaultTargetPlatform)) {
        markTestSkipped(
          'This smoke test targets platforms supported by quick_blue.',
        );
        return;
      }

      final bluetoothAvailable = await _waitForBluetoothAvailable();
      if (!bluetoothAvailable) {
        fail(
          'Bluetooth is not powered on, unavailable, or permission was denied.',
        );
      }

      final profile = _activeProfile();
      final writeRequest = _writeRequest();
      final serviceUuids = _definedList(_serviceUuidCsv, profile.serviceUuids);
      final expectedServiceUuids = _definedList(
        _expectedServiceUuidCsv,
        profile.expectedServiceUuids,
      );
      final connect = _definedBool(_connect, profile.connect) ?? true;
      final read = _definedBool(_read, profile.read) ?? true;
      final maxConnectAttempts = _positive(
        profile.maxConnectAttempts ?? _maxConnectAttempts,
        1,
      );
      final candidates = await _smokeCandidates(
        scanFilter: ScanFilter(serviceUuids: serviceUuids),
        profile: profile,
        shouldConnect: connect,
      );
      if (candidates.isEmpty) {
        markTestSkipped(
          'No BLE advertisements matched the smoke test scan criteria.',
        );
        return;
      }

      final explicitTarget =
          _targetDeviceId.isNotEmpty ||
          _targetNamePattern.isNotEmpty ||
          _profileName.isNotEmpty ||
          _profileJson.isNotEmpty ||
          serviceUuids.isNotEmpty ||
          profile.targetsDevice ||
          expectedServiceUuids.isNotEmpty ||
          writeRequest != null;
      final failures = <String>[];

      for (final candidate in candidates.take(maxConnectAttempts)) {
        final device = candidate.device;

        try {
          _expectAdvertisement(candidate.scanResult, profile);
          if (!connect) {
            return;
          }

          if (candidate.shouldConnect) {
            await device.connect().timeout(
              _seconds(_connectTimeoutSeconds, 12),
            );
          }

          final services = await device.discoverServices().timeout(
            _seconds(_serviceTimeoutSeconds, 15),
          );
          _expectDiscoveredServices(
            device.deviceId,
            services,
            expectedServiceUuids,
          );
          if (read) {
            await _readSmokeCharacteristic(
              device,
              services,
            ).timeout(_seconds(_readTimeoutSeconds, 8));
          }
          if (writeRequest != null) {
            await _writeSmokeCharacteristic(
              device,
              services,
              writeRequest,
            ).timeout(_seconds(_writeTimeoutSeconds, 8));
          }
          if (candidate.shouldDisconnect) {
            await device.disconnect().timeout(
              _seconds(_disconnectTimeoutSeconds, 8),
            );
          }

          return;
        } catch (error) {
          failures.add('${candidate.description}: $error');
          if (candidate.shouldDisconnect) {
            await _bestEffortDisconnect(device);
          }
        }
      }

      final failureSummary = failures.join('\n');
      if (explicitTarget) {
        fail(
          'No targeted BLE device completed the connect/discover/read/write/disconnect '
          'smoke flow.\n$failureSummary',
        );
      }

      markTestSkipped(
        'Found ${candidates.length} BLE advertisements, but none completed the '
        'connect/discover/read/write/disconnect smoke flow. Set '
        'QUICK_BLUE_SMOKE_DEVICE_ID, QUICK_BLUE_SMOKE_NAME_PATTERN, or '
        'QUICK_BLUE_SMOKE_SERVICE_UUIDS to make this a required target. '
        'Use QUICK_BLUE_SMOKE_EXPECTED_SERVICE_UUIDS to assert a known GATT '
        'service set.\n'
        '$failureSummary',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

bool _supportsBleSmoke(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
}

Future<bool> _waitForBluetoothAvailable() async {
  final deadline = DateTime.now().add(
    _seconds(_bluetoothReadyTimeoutSeconds, 8),
  );

  do {
    if (await QuickBlue.isBluetoothAvailable()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));

  return false;
}

Future<List<BlueScanResult>> _scanForCandidates({
  required ScanFilter scanFilter,
  required BleSmokeProfile profile,
}) async {
  final resultsByDeviceId = <String, BlueScanResult>{};
  final errors = <Object>[];
  final targetDeviceId = _targetDeviceId.isEmpty
      ? profile.targetDeviceId
      : _targetDeviceId;
  final targetNamePattern = _targetNamePattern.isEmpty
      ? profile.targetNamePattern
      : _targetNamePattern;
  final namePattern = targetNamePattern == null || targetNamePattern.isEmpty
      ? null
      : RegExp(targetNamePattern, caseSensitive: false);

  final subscription = QuickBlue.scanResults(scanFilter: scanFilter).listen((
    result,
  ) {
    if (targetDeviceId != null &&
        targetDeviceId.isNotEmpty &&
        !_matchesDeviceId(result.deviceId, targetDeviceId)) {
      return;
    }
    if (namePattern != null && !namePattern.hasMatch(result.name)) {
      return;
    }
    resultsByDeviceId[result.deviceId] = result;
  }, onError: errors.add);

  await Future<void>.delayed(_seconds(_scanSeconds, 12));
  await subscription.cancel();

  if (errors.isNotEmpty) {
    throw StateError('BLE scan failed: ${errors.first}');
  }

  final results = resultsByDeviceId.values.toList()
    ..sort((left, right) {
      final byNamed = _isNamed(right).compareTo(_isNamed(left));
      if (byNamed != 0) return byNamed;
      return right.rssi.compareTo(left.rssi);
    });
  if (_dumpAdvertisements) {
    for (final result in results) {
      debugPrint(_describeAdvertisement(result));
    }
  }

  return results;
}

Future<List<_SmokeCandidate>> _smokeCandidates({
  required ScanFilter scanFilter,
  required BleSmokeProfile profile,
  required bool shouldConnect,
}) async {
  final connectedTarget = shouldConnect
      ? await _connectedTarget(profile)
      : null;
  if (connectedTarget != null) {
    return <_SmokeCandidate>[
      _SmokeCandidate(
        device: connectedTarget,
        description: 'already-connected device ${connectedTarget.deviceId}',
        scanResult: null,
        shouldConnect: false,
        shouldDisconnect: false,
      ),
    ];
  }

  final scanResults = await _scanForCandidates(
    scanFilter: scanFilter,
    profile: profile,
  );
  return scanResults
      .map(
        (result) => _SmokeCandidate(
          device: QuickBlue.device(result.deviceId),
          description: _describeScanResult(result),
          scanResult: result,
          shouldConnect: true,
          shouldDisconnect: true,
        ),
      )
      .toList(growable: false);
}

Future<BluetoothDevice?> _connectedTarget(BleSmokeProfile profile) async {
  final targetDeviceId = _targetDeviceId.isEmpty
      ? profile.targetDeviceId
      : _targetDeviceId;
  if (targetDeviceId == null || targetDeviceId.isEmpty) {
    return null;
  }

  final connectedDevices = await QuickBlue.connectedDevices();
  for (final device in connectedDevices) {
    if (_matchesDeviceId(device.deviceId, targetDeviceId)) {
      return device;
    }
  }
  return null;
}

void _expectAdvertisement(BlueScanResult? result, BleSmokeProfile profile) {
  if (result == null) {
    if (profile.expectedAdvertisedServiceUuids.isNotEmpty ||
        profile.expectedManufacturerDataHex != null ||
        profile.expectedServiceDataHex.isNotEmpty ||
        profile.minRssi != null) {
      throw StateError(
        'Cannot validate advertisement fields for an already-connected device.',
      );
    }
    return;
  }

  final minRssi = _minRssi == 0 ? profile.minRssi : _minRssi;
  if (minRssi != null && result.rssi < minRssi) {
    throw StateError(
      '${_describeScanResult(result)} RSSI is below expected minimum $minRssi.',
    );
  }

  final expectedAdvertisedServiceUuids = _definedList(
    _expectedAdvertisedServiceUuidCsv,
    profile.expectedAdvertisedServiceUuids,
  );
  final missingAdvertisedServices = expectedAdvertisedServiceUuids
      .where(
        (expected) => !result.serviceUuids.any(
          (actual) => _matchesBluetoothUuid(actual, expected),
        ),
      )
      .toList(growable: false);
  if (missingAdvertisedServices.isNotEmpty) {
    throw StateError(
      '${_describeScanResult(result)} did not advertise '
      '${missingAdvertisedServices.join(', ')}. Advertised services: '
      '${result.serviceUuids.join(', ')}.',
    );
  }

  final expectedManufacturerDataHex = _expectedManufacturerDataHex.isEmpty
      ? profile.expectedManufacturerDataHex
      : _expectedManufacturerDataHex;
  if (expectedManufacturerDataHex != null &&
      expectedManufacturerDataHex.isNotEmpty) {
    final expected = hexBytes(
      expectedManufacturerDataHex,
      'expectedManufacturerDataHex',
    );
    final manufacturerData = result.manufacturerData;
    if (!hasBytePrefix(manufacturerData, expected)) {
      throw StateError(
        '${_describeScanResult(result)} did not advertise manufacturer data '
        'prefix $expectedManufacturerDataHex. Actual bytes: '
        '${manufacturerData.toList()}.',
      );
    }
  }

  for (final expected in profile.expectedServiceDataHex.entries) {
    final serviceData = result.serviceData.entries.where(
      (entry) => _matchesBluetoothUuid(entry.key, expected.key),
    );
    if (serviceData.isEmpty) {
      throw StateError(
        '${_describeScanResult(result)} did not advertise service data for '
        '${expected.key}.',
      );
    }
    final expectedBytes = hexBytes(
      expected.value,
      'expectedServiceDataHex.${expected.key}',
    );
    if (!serviceData.any(
      (entry) => hasBytePrefix(entry.value, expectedBytes),
    )) {
      throw StateError(
        '${_describeScanResult(result)} did not advertise service data prefix '
        '${expected.value} for ${expected.key}.',
      );
    }
  }
}

void _expectDiscoveredServices(
  String deviceId,
  List<BluetoothService> services,
  List<String> expectedServiceUuids,
) {
  if (expectedServiceUuids.isEmpty) {
    return;
  }

  final serviceUuids = services
      .map((service) => service.uuid)
      .toList(growable: false);
  final missing = expectedServiceUuids
      .where(
        (expected) => !serviceUuids.any(
          (actual) => _matchesBluetoothUuid(actual, expected),
        ),
      )
      .toList(growable: false);

  if (missing.isEmpty) {
    return;
  }

  throw StateError(
    'Expected $deviceId to expose ${expectedServiceUuids.join(', ')}. '
    'Missing: ${missing.join(', ')}. '
    'Discovered services: ${serviceUuids.join(', ')}.',
  );
}

Future<void> _readSmokeCharacteristic(
  BluetoothDevice device,
  List<BluetoothService> services,
) async {
  final readable = _readableSmokeCharacteristic(services);
  if (readable == null) {
    throw StateError('No readable characteristic was discovered.');
  }

  await device.readValue(readable.service.uuid, readable.characteristic.uuid);
}

Future<void> _writeSmokeCharacteristic(
  BluetoothDevice device,
  List<BluetoothService> services,
  _WriteRequest request,
) async {
  final target = _findCharacteristic(
    services,
    request.serviceUuid,
    request.characteristicUuid,
  );
  if (target == null) {
    throw StateError(
      'Requested write characteristic ${request.serviceUuid}/'
      '${request.characteristicUuid} was not discovered.',
    );
  }
  if (!target.characteristic.canWrite) {
    throw StateError(
      'Requested write characteristic ${request.serviceUuid}/'
      '${request.characteristicUuid} is not writable.',
    );
  }
  if (request.bleOutputProperty == BleOutputProperty.withResponse &&
      !target.characteristic.canWriteWithResponse) {
    throw StateError(
      'Requested write characteristic ${request.serviceUuid}/'
      '${request.characteristicUuid} does not support write with response.',
    );
  }
  if (request.bleOutputProperty == BleOutputProperty.withoutResponse &&
      !target.characteristic.canWriteWithoutResponse) {
    throw StateError(
      'Requested write characteristic ${request.serviceUuid}/'
      '${request.characteristicUuid} does not support write without response.',
    );
  }

  await device.writeValue(
    target.service.uuid,
    target.characteristic.uuid,
    request.value,
    request.bleOutputProperty,
  );
}

Future<void> _bestEffortDisconnect(BluetoothDevice device) async {
  try {
    await device.disconnect().timeout(_seconds(_disconnectTimeoutSeconds, 8));
  } catch (_) {
    // The candidate may never have connected, or it may already have dropped.
  }
}

_CharacteristicTarget? _readableSmokeCharacteristic(
  List<BluetoothService> services,
) {
  const preferred = <_CharacteristicId>[
    _CharacteristicId('1800', '2a00'),
    _CharacteristicId('1800', '2a01'),
    _CharacteristicId('180f', '2a19'),
    _CharacteristicId('180a', '2a29'),
    _CharacteristicId('180a', '2a24'),
    _CharacteristicId('180a', '2a26'),
  ];

  for (final id in preferred) {
    final target = _findCharacteristic(services, id.service, id.characteristic);
    if (target != null && target.characteristic.canRead) {
      return target;
    }
  }

  for (final service in services) {
    for (final characteristic in service.characteristicDetails) {
      if (characteristic.canRead) {
        return _CharacteristicTarget(service, characteristic);
      }
    }
  }

  return null;
}

_CharacteristicTarget? _findCharacteristic(
  List<BluetoothService> services,
  String serviceUuid,
  String characteristicUuid,
) {
  for (final service in services) {
    if (!_matchesBluetoothUuid(service.uuid, serviceUuid)) {
      continue;
    }
    for (final characteristic in service.characteristicDetails) {
      if (_matchesBluetoothUuid(characteristic.uuid, characteristicUuid)) {
        return _CharacteristicTarget(service, characteristic);
      }
    }
  }
  return null;
}

_WriteRequest? _writeRequest() {
  final anyWriteDefine =
      _writeServiceUuid.isNotEmpty ||
      _writeCharacteristicUuid.isNotEmpty ||
      _writeValueHex.isNotEmpty;
  if (!anyWriteDefine) {
    return null;
  }

  final missing = <String>[
    if (_writeServiceUuid.isEmpty) 'QUICK_BLUE_SMOKE_WRITE_SERVICE_UUID',
    if (_writeCharacteristicUuid.isEmpty)
      'QUICK_BLUE_SMOKE_WRITE_CHARACTERISTIC_UUID',
    if (_writeValueHex.isEmpty) 'QUICK_BLUE_SMOKE_WRITE_HEX',
  ];
  if (missing.isNotEmpty) {
    throw ArgumentError(
      'Write smoke testing requires all write defines. Missing: '
      '${missing.join(', ')}.',
    );
  }

  return _WriteRequest(
    serviceUuid: _writeServiceUuid,
    characteristicUuid: _writeCharacteristicUuid,
    value: hexBytes(_writeValueHex, 'QUICK_BLUE_SMOKE_WRITE_HEX'),
    bleOutputProperty: _writeWithoutResponse
        ? BleOutputProperty.withoutResponse
        : BleOutputProperty.withResponse,
  );
}

List<String> _csv(String value) {
  return csvList(value);
}

List<String> _definedList(String value, List<String> fallback) {
  return value.isEmpty ? fallback : _csv(value);
}

bool? _definedBool(String value, bool? fallback) {
  return value.isEmpty ? fallback : boolFromString(value, 'Dart define');
}

BleSmokeProfile _activeProfile() {
  var profile = const BleSmokeProfile();
  if (_profileName.isNotEmpty) {
    final builtInProfile = BleSmokeProfile.builtIn(_profileName);
    if (builtInProfile == null) {
      throw ArgumentError('Unknown smoke profile: $_profileName.');
    }
    profile = profile.merge(builtInProfile);
  }
  if (_profileJson.isNotEmpty) {
    profile = profile.merge(BleSmokeProfile.fromJson(_profileJson));
  }
  return profile;
}

Duration _seconds(int value, int fallback) {
  return Duration(seconds: _positive(value, fallback));
}

int _positive(int value, int fallback) {
  return value > 0 ? value : fallback;
}

int _isNamed(BlueScanResult result) {
  return result.name.trim().isEmpty ? 0 : 1;
}

bool _matchesDeviceId(String left, String right) =>
    left.toLowerCase() == right.toLowerCase();

bool _matchesBluetoothUuid(String left, String right) {
  final normalizedLeft = _normalizeBluetoothUuid(left);
  final normalizedRight = _normalizeBluetoothUuid(right);
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft == normalizedRight;
}

String? _normalizeBluetoothUuid(String uuid) {
  final cleaned = uuid.replaceAll('-', '').toLowerCase();
  if (cleaned.length == 4) {
    return '0000${cleaned}00001000800000805f9b34fb';
  }
  if (cleaned.length == 8) {
    return '${cleaned}00001000800000805f9b34fb';
  }
  if (cleaned.length == 32) {
    return cleaned;
  }
  return null;
}

String _describeScanResult(BlueScanResult result) {
  final name = result.name.trim().isEmpty ? '<unnamed>' : result.name.trim();
  return '$name (${result.deviceId}, RSSI ${result.rssi})';
}

String _describeAdvertisement(BlueScanResult result) {
  final serviceData = result.serviceData.map(
    (uuid, value) => MapEntry(uuid, hexString(value)),
  );
  return 'BLE advertisement: '
      'name="${result.name}", '
      'deviceId="${result.deviceId}", '
      'rssi=${result.rssi}, '
      'serviceUuids=${result.serviceUuids}, '
      'manufacturerData="${hexString(result.manufacturerData)}", '
      'serviceData=$serviceData';
}

class _CharacteristicId {
  const _CharacteristicId(this.service, this.characteristic);

  final String service;
  final String characteristic;
}

class _CharacteristicTarget {
  _CharacteristicTarget(this.service, this.characteristic);

  final BluetoothService service;
  final BluetoothCharacteristicInfo characteristic;
}

class _SmokeCandidate {
  _SmokeCandidate({
    required this.device,
    required this.description,
    required this.scanResult,
    required this.shouldConnect,
    required this.shouldDisconnect,
  });

  final BluetoothDevice device;
  final String description;
  final BlueScanResult? scanResult;
  final bool shouldConnect;
  final bool shouldDisconnect;
}

class _WriteRequest {
  _WriteRequest({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.value,
    required this.bleOutputProperty,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final Uint8List value;
  final BleOutputProperty bleOutputProperty;
}
