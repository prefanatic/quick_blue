import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';

const _scanSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_SCAN_SECONDS',
  defaultValue: 12,
);
const _durationSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_DURATION_SECONDS',
  defaultValue: 30,
);
const _connectTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_CONNECT_TIMEOUT_SECONDS',
  defaultValue: 15,
);
const _serviceTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_SERVICE_TIMEOUT_SECONDS',
  defaultValue: 15,
);
const _readTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_READ_TIMEOUT_SECONDS',
  defaultValue: 5,
);
const _readIterations = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_READ_ITERATIONS',
  defaultValue: 100,
);
const _readDelayMilliseconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_READ_DELAY_MILLISECONDS',
);
const _bluetoothReadyTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_BLUETOOTH_READY_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _sequenceOffset = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_SEQUENCE_OFFSET',
  defaultValue: -1,
);
const _sequenceWidthBytes = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_SEQUENCE_WIDTH_BYTES',
  defaultValue: 2,
);
const _sequenceLittleEndian = bool.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_SEQUENCE_LITTLE_ENDIAN',
  defaultValue: true,
);
const _targetDeviceId = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_DEVICE_ID',
);
const _targetNamePattern = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NAME_PATTERN',
);
const _scanServiceUuidCsv = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_SCAN_SERVICE_UUIDS',
);
const _notifyServiceUuid = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID',
);
const _notifyCharacteristicUuid = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID',
);
const _notifyWriteServiceUuid = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_SERVICE_UUID',
);
const _notifyWriteCharacteristicUuid = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_CHARACTERISTIC_UUID',
);
const _notifyWriteCommandHex = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_COMMAND_HEX',
);
const _notifyWriteIterations = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_ITERATIONS',
  defaultValue: 1,
);
const _notifyWriteDelayMilliseconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_DELAY_MILLISECONDS',
);
const _notifyWriteTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_TIMEOUT_SECONDS',
  defaultValue: 5,
);
const _notifyWriteWithoutResponse = bool.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_WITHOUT_RESPONSE',
  defaultValue: true,
);
const _readServiceUuid = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_READ_SERVICE_UUID',
);
const _readCharacteristicUuid = String.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_READ_CHARACTERISTIC_UUID',
);
const _useIndications = bool.fromEnvironment(
  'QUICK_BLUE_BENCHMARK_USE_INDICATIONS',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'BLE characteristic notification and read benchmark',
    (_) async {
      if (!_supportsBleBenchmark(defaultTargetPlatform)) {
        markTestSkipped(
          'This benchmark targets platforms supported by quick_blue.',
        );
        return;
      }
      if (_notifyServiceUuid.isEmpty || _notifyCharacteristicUuid.isEmpty) {
        markTestSkipped(
          'Set QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID and '
          'QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID for a known '
          'notifying characteristic.',
        );
        return;
      }
      final hasPartialReadTarget =
          (_readServiceUuid.isEmpty && _readCharacteristicUuid.isNotEmpty) ||
          (_readServiceUuid.isNotEmpty && _readCharacteristicUuid.isEmpty);
      if (hasPartialReadTarget) {
        markTestSkipped(
          'Set both QUICK_BLUE_BENCHMARK_READ_SERVICE_UUID and '
          'QUICK_BLUE_BENCHMARK_READ_CHARACTERISTIC_UUID, or omit both to '
          'read the notifying characteristic when it is readable.',
        );
        return;
      }
      final hasPartialNotifyWriteTarget =
          (_notifyWriteServiceUuid.isEmpty &&
              _notifyWriteCharacteristicUuid.isNotEmpty) ||
          (_notifyWriteServiceUuid.isNotEmpty &&
              _notifyWriteCharacteristicUuid.isEmpty);
      if (hasPartialNotifyWriteTarget) {
        markTestSkipped(
          'Set both QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_SERVICE_UUID and '
          'QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_CHARACTERISTIC_UUID, or omit '
          'both to write the notifying characteristic when it is writable.',
        );
        return;
      }
      if (_targetDeviceId.isEmpty && _targetNamePattern.isEmpty) {
        markTestSkipped(
          'Set QUICK_BLUE_BENCHMARK_DEVICE_ID or '
          'QUICK_BLUE_BENCHMARK_NAME_PATTERN to select a benchmark device.',
        );
        return;
      }

      final bluetoothAvailable = await _waitForBluetoothAvailable();
      if (!bluetoothAvailable) {
        fail(
          'Bluetooth is not powered on, unavailable, or permission was denied.',
        );
      }

      final target = await _benchmarkTarget();
      if (target == null) {
        markTestSkipped('No BLE device matched the benchmark target.');
        return;
      }

      final device = target.device;
      final connectedByBenchmark = target.shouldDisconnect;
      final result = <String, Object?>{
        'target': target.description,
        'platform': defaultTargetPlatform.name,
        'notifyServiceUuid': _notifyServiceUuid,
        'notifyCharacteristicUuid': _notifyCharacteristicUuid,
        'notificationDurationSeconds': _durationSeconds,
      };

      try {
        if (target.shouldConnect) {
          await device.connect().timeout(_seconds(_connectTimeoutSeconds, 15));
        }

        final services = await device.discoverServices().timeout(
          _seconds(_serviceTimeoutSeconds, 15),
        );
        final notifyInfo = _findCharacteristic(
          services,
          serviceUuid: _notifyServiceUuid,
          characteristicUuid: _notifyCharacteristicUuid,
        );
        if (notifyInfo == null || !notifyInfo.info.canSubscribe) {
          fail(
            'Benchmark characteristic $_notifyServiceUuid/'
            '$_notifyCharacteristicUuid was not discovered or does not support '
            'notify/indicate.',
          );
        }

        _ResolvedCharacteristic? notifyWriteTarget;
        Uint8List? notifyWriteCommand;
        if (_notifyWriteCommandHex.trim().isNotEmpty) {
          notifyWriteCommand = _hexBytes(_notifyWriteCommandHex);
          notifyWriteTarget = _notifyWriteTarget(services, notifyInfo);
          if (notifyWriteTarget == null) {
            fail(
              'Notify-write benchmark characteristic '
              '$_notifyWriteServiceUuid/$_notifyWriteCharacteristicUuid was '
              'not discovered.',
            );
          }
          if (!notifyWriteTarget.info.canWrite) {
            fail(
              'Notify-write benchmark characteristic '
              '${notifyWriteTarget.service.uuid}/${notifyWriteTarget.info.uuid} '
              'does not support writes.',
            );
          }
          result['notifyWriteServiceUuid'] = notifyWriteTarget.service.uuid;
          result['notifyWriteCharacteristicUuid'] = notifyWriteTarget.info.uuid;
          result['notifyWriteCommandHex'] = _hex(notifyWriteCommand);
          result['notificationMode'] = 'writeCommand';
        } else {
          result['notificationMode'] = 'passiveDuration';
        }

        final notifyResult = await _measureNotifications(
          device: device,
          serviceUuid: notifyInfo.service.uuid,
          characteristicUuid: notifyInfo.info.uuid,
          writeTarget: notifyWriteTarget,
          writeCommand: notifyWriteCommand,
        );
        result['notifications'] = notifyResult.toJson();

        final readTarget = _readTarget(services, notifyInfo);
        final hasExplicitReadTarget =
            _readServiceUuid.isNotEmpty && _readCharacteristicUuid.isNotEmpty;
        if (readTarget == null && hasExplicitReadTarget) {
          fail(
            'Read benchmark characteristic $_readServiceUuid/'
            '$_readCharacteristicUuid was not discovered.',
          );
        }
        if (readTarget == null) {
          result['reads'] = <String, Object?>{
            'skipped': true,
            'reason':
                'No readable benchmark characteristic was configured or '
                'available on the notifying characteristic.',
          };
        } else {
          result['readServiceUuid'] = readTarget.service.uuid;
          result['readCharacteristicUuid'] = readTarget.info.uuid;
          result['reads'] = (await _measureReads(
            device: device,
            serviceUuid: readTarget.service.uuid,
            characteristicUuid: readTarget.info.uuid,
          )).toJson();
        }
      } finally {
        if (connectedByBenchmark) {
          await _bestEffortDisconnect(device);
        }
      }

      binding.reportData = result;
      debugPrint(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'quickBlueBleCharacteristicBenchmark': result,
        }),
        wrapWidth: 1024,
      );
    },
    timeout: Timeout(_seconds(_durationSeconds + 180, 210)),
  );
}

bool _supportsBleBenchmark(TargetPlatform platform) {
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

Future<_BenchmarkTarget?> _benchmarkTarget() async {
  final connected = await _connectedTarget();
  if (connected != null) {
    return _BenchmarkTarget(
      device: connected,
      description: 'already-connected device ${connected.deviceId}',
      shouldConnect: false,
      shouldDisconnect: false,
    );
  }

  final result = await _scanForTarget();
  if (result == null) {
    return null;
  }
  return _BenchmarkTarget(
    device: QuickBlue.device(result.deviceId),
    description: _describeScanResult(result),
    shouldConnect: true,
    shouldDisconnect: true,
  );
}

Future<BluetoothDevice?> _connectedTarget() async {
  if (_targetDeviceId.isEmpty) {
    return null;
  }

  final serviceUuids = _csv(_scanServiceUuidCsv);
  final lookupServiceUuids = serviceUuids.isEmpty
      ? <String>[_notifyServiceUuid]
      : serviceUuids;
  final connectedDevices = await QuickBlue.connectedDevices(
    serviceUuids: lookupServiceUuids,
  );
  for (final device in connectedDevices) {
    if (_matchesDeviceId(device.deviceId, _targetDeviceId)) {
      return device;
    }
  }
  return null;
}

Future<BlueScanResult?> _scanForTarget() async {
  final namePattern = _targetNamePattern.isEmpty
      ? null
      : RegExp(_targetNamePattern, caseSensitive: false);
  final serviceUuids = _csv(_scanServiceUuidCsv);
  final matches = <String, BlueScanResult>{};
  final errors = <Object>[];

  final subscription =
      QuickBlue.scanResults(
        scanFilter: ScanFilter(serviceUuids: serviceUuids),
      ).listen((result) {
        if (_targetDeviceId.isNotEmpty &&
            !_matchesDeviceId(result.deviceId, _targetDeviceId)) {
          return;
        }
        if (namePattern != null && !namePattern.hasMatch(result.name)) {
          return;
        }
        matches[result.deviceId] = result;
      }, onError: errors.add);

  await Future<void>.delayed(_seconds(_scanSeconds, 12));
  await subscription.cancel();

  if (errors.isNotEmpty) {
    throw StateError('BLE scan failed: ${errors.first}');
  }

  final results = matches.values.toList()
    ..sort((left, right) {
      final named = (_isNamed(right) ? 1 : 0) - (_isNamed(left) ? 1 : 0);
      if (named != 0) return named;
      return right.rssi.compareTo(left.rssi);
    });
  return results.firstOrNull;
}

Future<_NotificationBenchmarkResult> _measureNotifications({
  required BluetoothDevice device,
  required String serviceUuid,
  required String characteristicUuid,
  required _ResolvedCharacteristic? writeTarget,
  required Uint8List? writeCommand,
}) async {
  final characteristic = device.characteristic(serviceUuid, characteristicUuid);
  final writeCharacteristic = writeTarget == null
      ? null
      : device.characteristic(writeTarget.service.uuid, writeTarget.info.uuid);
  final stopwatch = Stopwatch();
  final intervals = <int>[];
  final writeLatencies = <int>[];
  var bytes = 0;
  var count = 0;
  var writeBytes = 0;
  var previousMicros = 0;
  var firstMicros = 0;
  var lastMicros = 0;
  var lastSequence = -1;
  var sequenceSamples = 0;
  var sequenceGaps = 0;
  var duplicateOrReorderedSequences = 0;
  var waitForCount = 0;
  Completer<void>? notificationWaiter;

  final subscription = characteristic.valueStream.listen((value) {
    final now = stopwatch.elapsedMicroseconds;
    if (count == 0) {
      firstMicros = now;
    } else {
      intervals.add(now - previousMicros);
    }
    previousMicros = now;
    lastMicros = now;
    count++;
    bytes += value.length;

    final sequence = _readSequence(value);
    if (sequence != null) {
      sequenceSamples++;
      if (lastSequence != -1) {
        if (sequence <= lastSequence) {
          duplicateOrReorderedSequences++;
        } else if (sequence > lastSequence + 1) {
          sequenceGaps += sequence - lastSequence - 1;
        }
      }
      lastSequence = sequence;
    }

    final waiter = notificationWaiter;
    if (waiter != null && !waiter.isCompleted && count >= waitForCount) {
      waiter.complete();
    }
  });

  var notificationsEnabled = false;
  try {
    await device.setNotifiable(
      serviceUuid,
      characteristicUuid,
      _useIndications
          ? BleInputProperty.indication
          : BleInputProperty.notification,
    );
    notificationsEnabled = true;
    stopwatch.start();

    if (writeCommand != null && writeCharacteristic != null) {
      final writeIterations = _notifyWriteIterations <= 0
          ? 1
          : _notifyWriteIterations;
      final writeMode = _notifyWriteWithoutResponse
          ? BleOutputProperty.withoutResponse
          : BleOutputProperty.withResponse;
      for (var index = 0; index < writeIterations; index++) {
        final waiter = Completer<void>();
        waitForCount = count + 1;
        notificationWaiter = waiter;

        final writeStopwatch = Stopwatch()..start();
        await writeCharacteristic.write(writeCommand, writeMode);
        writeBytes += writeCommand.length;
        await waiter.future.timeout(_seconds(_notifyWriteTimeoutSeconds, 5));
        writeStopwatch.stop();
        writeLatencies.add(writeStopwatch.elapsedMicroseconds);
        if (identical(notificationWaiter, waiter)) {
          notificationWaiter = null;
        }

        if (_notifyWriteDelayMilliseconds > 0 && index != writeIterations - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: _notifyWriteDelayMilliseconds),
          );
        }
      }
    } else {
      await Future<void>.delayed(_seconds(_durationSeconds, 30));
    }
  } finally {
    notificationWaiter = null;
    await subscription.cancel();
    if (notificationsEnabled) {
      await device.setNotifiable(
        serviceUuid,
        characteristicUuid,
        BleInputProperty.disabled,
      );
    }
    if (stopwatch.isRunning) {
      stopwatch.stop();
    }
  }

  final activeMicros = count < 2 ? 0 : lastMicros - firstMicros;
  final elapsedMicros = stopwatch.elapsedMicroseconds;
  return _NotificationBenchmarkResult(
    duration: stopwatch.elapsed,
    activeDurationMicros: activeMicros,
    elapsedMicros: elapsedMicros,
    count: count,
    bytes: bytes,
    intervals: intervals,
    sequenceSamples: sequenceSamples,
    sequenceGaps: sequenceGaps,
    duplicateOrReorderedSequences: duplicateOrReorderedSequences,
    commandWrites: writeCommand == null
        ? null
        : _NotifyWriteBenchmarkResult(
            count: writeLatencies.length,
            bytes: writeBytes,
            latencies: writeLatencies,
          ),
  );
}

Future<_ReadBenchmarkResult> _measureReads({
  required BluetoothDevice device,
  required String serviceUuid,
  required String characteristicUuid,
}) async {
  final characteristic = device.characteristic(serviceUuid, characteristicUuid);
  final latencies = <int>[];
  var bytes = 0;
  final totalStopwatch = Stopwatch()..start();

  for (var index = 0; index < _readIterations; index++) {
    final readStopwatch = Stopwatch()..start();
    final value = await characteristic.read().timeout(
      _seconds(_readTimeoutSeconds, 5),
    );
    readStopwatch.stop();
    latencies.add(readStopwatch.elapsedMicroseconds);
    bytes += value.length;

    if (_readDelayMilliseconds > 0 && index != _readIterations - 1) {
      await Future<void>.delayed(
        Duration(milliseconds: _readDelayMilliseconds),
      );
    }
  }

  totalStopwatch.stop();
  return _ReadBenchmarkResult(
    duration: totalStopwatch.elapsed,
    elapsedMicros: totalStopwatch.elapsedMicroseconds,
    count: latencies.length,
    bytes: bytes,
    latencies: latencies,
  );
}

_ResolvedCharacteristic? _readTarget(
  List<BluetoothService> services,
  _ResolvedCharacteristic notifyInfo,
) {
  if (_readServiceUuid.isNotEmpty && _readCharacteristicUuid.isNotEmpty) {
    return _findCharacteristic(
      services,
      serviceUuid: _readServiceUuid,
      characteristicUuid: _readCharacteristicUuid,
    );
  }
  if (notifyInfo.info.canRead) {
    return notifyInfo;
  }
  return null;
}

_ResolvedCharacteristic? _notifyWriteTarget(
  List<BluetoothService> services,
  _ResolvedCharacteristic notifyInfo,
) {
  if (_notifyWriteServiceUuid.isNotEmpty &&
      _notifyWriteCharacteristicUuid.isNotEmpty) {
    return _findCharacteristic(
      services,
      serviceUuid: _notifyWriteServiceUuid,
      characteristicUuid: _notifyWriteCharacteristicUuid,
    );
  }
  if (notifyInfo.info.canWrite) {
    return notifyInfo;
  }
  return null;
}

_ResolvedCharacteristic? _findCharacteristic(
  List<BluetoothService> services, {
  required String serviceUuid,
  required String characteristicUuid,
}) {
  for (final service in services) {
    if (!_matchesUuid(service.uuid, serviceUuid)) {
      continue;
    }
    for (final characteristic in service.characteristicDetails) {
      if (_matchesUuid(characteristic.uuid, characteristicUuid)) {
        return _ResolvedCharacteristic(service, characteristic);
      }
    }
  }
  return null;
}

int? _readSequence(Uint8List value) {
  if (_sequenceOffset < 0) {
    return null;
  }
  if (_sequenceWidthBytes != 1 &&
      _sequenceWidthBytes != 2 &&
      _sequenceWidthBytes != 4) {
    throw StateError('Sequence width must be 1, 2, or 4 bytes.');
  }
  if (value.length < _sequenceOffset + _sequenceWidthBytes) {
    return null;
  }

  var sequence = 0;
  for (var index = 0; index < _sequenceWidthBytes; index++) {
    final shift = _sequenceLittleEndian
        ? index * 8
        : (_sequenceWidthBytes - index - 1) * 8;
    sequence |= value[_sequenceOffset + index] << shift;
  }
  return sequence;
}

Future<void> _bestEffortDisconnect(BluetoothDevice device) async {
  try {
    await device.disconnect().timeout(const Duration(seconds: 5));
  } catch (_) {
    // Best effort cleanup after benchmark completion or failure.
  }
}

String _describeScanResult(BlueScanResult result) {
  final name = result.name.isEmpty ? '<unnamed>' : result.name;
  return '$name (${result.deviceId}, RSSI=${result.rssi})';
}

bool _isNamed(BlueScanResult result) => result.name.trim().isNotEmpty;

bool _matchesDeviceId(String left, String right) {
  return left.toLowerCase() == right.toLowerCase();
}

bool _matchesUuid(String left, String right) {
  if (left == right) {
    return true;
  }
  final normalizedLeft = _normalizeUuid(left);
  final normalizedRight = _normalizeUuid(right);
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft == normalizedRight;
}

String? _normalizeUuid(String uuid) {
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

List<String> _csv(String value) {
  if (value.trim().isEmpty) {
    return const <String>[];
  }
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

Uint8List _hexBytes(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\s:_-]'), '');
  if (cleaned.isEmpty) {
    throw StateError('Hex command must not be empty.');
  }
  if (cleaned.length.isOdd) {
    throw StateError('Hex command must contain an even number of digits.');
  }
  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var index = 0; index < bytes.length; index++) {
    final offset = index * 2;
    bytes[index] = int.parse(cleaned.substring(offset, offset + 2), radix: 16);
  }
  return bytes;
}

String _hex(Uint8List value) {
  return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Duration _seconds(int value, int fallback) {
  return Duration(seconds: value <= 0 ? fallback : value);
}

extension<T> on List<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}

class _BenchmarkTarget {
  _BenchmarkTarget({
    required this.device,
    required this.description,
    required this.shouldConnect,
    required this.shouldDisconnect,
  });

  final BluetoothDevice device;
  final String description;
  final bool shouldConnect;
  final bool shouldDisconnect;
}

class _ResolvedCharacteristic {
  _ResolvedCharacteristic(this.service, this.info);

  final BluetoothService service;
  final BluetoothCharacteristicInfo info;
}

class _NotificationBenchmarkResult {
  _NotificationBenchmarkResult({
    required this.duration,
    required this.activeDurationMicros,
    required this.elapsedMicros,
    required this.count,
    required this.bytes,
    required this.intervals,
    required this.sequenceSamples,
    required this.sequenceGaps,
    required this.duplicateOrReorderedSequences,
    required this.commandWrites,
  });

  final Duration duration;
  final int activeDurationMicros;
  final int elapsedMicros;
  final int count;
  final int bytes;
  final List<int> intervals;
  final int sequenceSamples;
  final int sequenceGaps;
  final int duplicateOrReorderedSequences;
  final _NotifyWriteBenchmarkResult? commandWrites;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'elapsedMilliseconds': duration.inMilliseconds,
      'activeMilliseconds': activeDurationMicros / 1000,
      'count': count,
      'bytes': bytes,
      'notificationsPerSecond': _rate(count, elapsedMicros),
      'bytesPerSecond': _rate(bytes, elapsedMicros),
      'activeNotificationsPerSecond': _rate(count, activeDurationMicros),
      'activeBytesPerSecond': _rate(bytes, activeDurationMicros),
      'interArrivalMicros': _distribution(intervals),
      'sequenceSamples': sequenceSamples,
      'sequenceGaps': sequenceGaps,
      'duplicateOrReorderedSequences': duplicateOrReorderedSequences,
      if (commandWrites != null) 'commandWrites': commandWrites!.toJson(),
    };
  }
}

class _NotifyWriteBenchmarkResult {
  _NotifyWriteBenchmarkResult({
    required this.count,
    required this.bytes,
    required this.latencies,
  });

  final int count;
  final int bytes;
  final List<int> latencies;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'count': count,
      'bytes': bytes,
      'latencyMicros': _distribution(latencies),
    };
  }
}

class _ReadBenchmarkResult {
  _ReadBenchmarkResult({
    required this.duration,
    required this.elapsedMicros,
    required this.count,
    required this.bytes,
    required this.latencies,
  });

  final Duration duration;
  final int elapsedMicros;
  final int count;
  final int bytes;
  final List<int> latencies;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'elapsedMilliseconds': duration.inMilliseconds,
      'count': count,
      'bytes': bytes,
      'readsPerSecond': _rate(count, elapsedMicros),
      'bytesPerSecond': _rate(bytes, elapsedMicros),
      'latencyMicros': _distribution(latencies),
    };
  }
}

Map<String, Object?> _distribution(List<int> values) {
  if (values.isEmpty) {
    return <String, Object?>{
      'count': 0,
      'min': null,
      'p50': null,
      'p95': null,
      'max': null,
    };
  }
  final sorted = values.toList()..sort();
  return <String, Object?>{
    'count': sorted.length,
    'min': sorted.first,
    'p50': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
    'max': sorted.last,
  };
}

int _percentile(List<int> sortedValues, double percentile) {
  final index = ((sortedValues.length - 1) * percentile).round();
  return sortedValues[index];
}

double _rate(int count, int elapsedMicros) {
  if (elapsedMicros <= 0) {
    return 0;
  }
  return count * 1000000 / elapsedMicros;
}
