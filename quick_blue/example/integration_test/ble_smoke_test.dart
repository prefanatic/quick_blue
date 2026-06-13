import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
const _serviceUuidCsv = String.fromEnvironment(
  'QUICK_BLUE_SMOKE_SERVICE_UUIDS',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'BLE explorer scans, connects, discovers services, and disconnects',
    (_) async {
      if (!_supportsBleSmoke(defaultTargetPlatform)) {
        markTestSkipped(
          'This smoke test targets platforms supported by quick_blue.',
        );
        return;
      }

      final bluetoothAvailable = await _waitForBluetoothAvailable();
      if (!bluetoothAvailable) {
        markTestSkipped(
          'Bluetooth is not powered on, unavailable, or permission was denied.',
        );
        return;
      }

      final serviceUuids = _csv(_serviceUuidCsv);
      final candidates = await _scanForCandidates(
        scanFilter: ScanFilter(serviceUuids: serviceUuids),
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
          serviceUuids.isNotEmpty;
      final failures = <String>[];

      for (final result in candidates.take(_positive(_maxConnectAttempts, 1))) {
        final device = QuickBlue.device(result.deviceId);

        try {
          await device.connect().timeout(_seconds(_connectTimeoutSeconds, 12));

          await device.discoverServices().timeout(
            _seconds(_serviceTimeoutSeconds, 15),
          );
          await device.disconnect().timeout(
            _seconds(_disconnectTimeoutSeconds, 8),
          );

          return;
        } catch (error) {
          failures.add('${_describeScanResult(result)}: $error');
          await _bestEffortDisconnect(device);
        }
      }

      final failureSummary = failures.join('\n');
      if (explicitTarget) {
        fail(
          'No targeted BLE device completed the connect/discover/disconnect '
          'smoke flow.\n$failureSummary',
        );
      }

      markTestSkipped(
        'Found ${candidates.length} BLE advertisements, but none completed the '
        'connect/discover/disconnect smoke flow. Set '
        'QUICK_BLUE_SMOKE_DEVICE_ID, QUICK_BLUE_SMOKE_NAME_PATTERN, or '
        'QUICK_BLUE_SMOKE_SERVICE_UUIDS to make this a required target.\n'
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
}) async {
  final resultsByDeviceId = <String, BlueScanResult>{};
  final errors = <Object>[];
  final namePattern = _targetNamePattern.isEmpty
      ? null
      : RegExp(_targetNamePattern, caseSensitive: false);

  final subscription = QuickBlue.scanResults(scanFilter: scanFilter).listen((
    result,
  ) {
    if (_targetDeviceId.isNotEmpty && result.deviceId != _targetDeviceId) {
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

  return results;
}

Future<void> _bestEffortDisconnect(BluetoothDevice device) async {
  try {
    await device.disconnect().timeout(_seconds(_disconnectTimeoutSeconds, 8));
  } catch (_) {
    // The candidate may never have connected, or it may already have dropped.
  }
}

List<String> _csv(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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

String _describeScanResult(BlueScanResult result) {
  final name = result.name.trim().isEmpty ? '<unnamed>' : result.name.trim();
  return '$name (${result.deviceId}, RSSI ${result.rssi})';
}
