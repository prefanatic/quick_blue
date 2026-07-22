import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';

const _scanSeconds = int.fromEnvironment(
  'QUICK_BLUE_STRESS_SCAN_SECONDS',
  defaultValue: 15,
);
const _iterations = int.fromEnvironment(
  'QUICK_BLUE_STRESS_ITERATIONS',
  defaultValue: 3,
);
const _operationTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_STRESS_OPERATION_TIMEOUT_SECONDS',
  defaultValue: 15,
);
const _bluetoothReadyTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_STRESS_BLUETOOTH_READY_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _firstNamePattern = String.fromEnvironment(
  'QUICK_BLUE_STRESS_FIRST_NAME_PATTERN',
);
const _secondNamePattern = String.fromEnvironment(
  'QUICK_BLUE_STRESS_SECOND_NAME_PATTERN',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'repeated BLE lifecycle and two-device isolation stress',
    (_) async {
      if (!_supportsBleStress(defaultTargetPlatform)) {
        markTestSkipped(
          'This stress test targets platforms supported by quick_blue.',
        );
        return;
      }
      if (_firstNamePattern.isEmpty) {
        markTestSkipped(
          'Set QUICK_BLUE_STRESS_FIRST_NAME_PATTERN to a known connectable '
          'device with a readable characteristic.',
        );
        return;
      }
      if (!await _waitForBluetoothAvailable()) {
        fail(
          'Bluetooth is not powered on, unavailable, or permission was denied.',
        );
      }

      final targets = await _scanForTargets();
      final first = QuickBlue.device(targets.first.deviceId);
      final second = targets.second == null
          ? null
          : QuickBlue.device(targets.second!.deviceId);
      addTearDown(() => _bestEffortDisconnect(first));
      if (second != null) {
        addTearDown(() => _bestEffortDisconnect(second));
      }

      final iterations = _positive(_iterations, 3);
      for (var iteration = 1; iteration <= iterations; iteration += 1) {
        final rescanned = await _scanForTargets();
        expect(rescanned.first.deviceId, targets.first.deviceId);
        expect(rescanned.second?.deviceId, targets.second?.deviceId);
        debugPrint(
          'BLE lifecycle stress: completed scan restart '
          '$iteration/$iterations.',
        );
      }

      for (var iteration = 1; iteration <= iterations; iteration += 1) {
        await _exerciseOverlappingConnect(first);
        await _exerciseConnectDisconnectRace(first);
        debugPrint(
          'BLE lifecycle stress: completed connection race '
          '$iteration/$iterations for ${first.deviceId}.',
        );
      }

      for (var iteration = 1; iteration <= iterations; iteration += 1) {
        final services = await _exerciseCleanLifecycle(first);
        if (iteration == 1) {
          debugPrint(
            'BLE lifecycle stress: ${first.deviceId} GATT services: $services',
            wrapWidth: 1024,
          );
        }
        debugPrint(
          'BLE lifecycle stress: completed clean iteration '
          '$iteration/$iterations for ${first.deviceId}.',
        );
      }

      var cancelledDiscoveries = 0;
      for (var iteration = 1; iteration <= iterations; iteration += 1) {
        final outcome = await _exerciseDiscoveryDisconnectRace(first);
        if (outcome == _DiscoveryRaceOutcome.cancelled) {
          cancelledDiscoveries += 1;
        }
        debugPrint(
          'BLE lifecycle stress: discovery/disconnect iteration '
          '$iteration/$iterations ${outcome.name} for ${first.deviceId}.',
        );
      }

      if (second != null) {
        await _exerciseTwoDeviceIsolation(first, second);
      }

      debugPrint(
        'BLE lifecycle stress completed: first=${targets.first.name} '
        '(${targets.first.deviceId}), second='
        '${targets.second?.name ?? '<not configured>'} '
        '(${targets.second?.deviceId ?? '<not configured>'}), '
        'iterations=$iterations, cancelledDiscoveries=$cancelledDiscoveries.',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

bool _supportsBleStress(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
}

Future<List<BluetoothService>> _exerciseCleanLifecycle(
  BluetoothDevice device,
) async {
  await device.connect().timeout(_operationTimeout);

  final discoveries = await Future.wait(<Future<List<BluetoothService>>>[
    device.discoverServices(),
    device.discoverServices(),
  ]).timeout(_operationTimeout);
  expect(discoveries.first, isNotEmpty);
  expect(discoveries.last, discoveries.first);
  await _readFirstReadable(device, discoveries.first);

  await device.disconnect().timeout(_operationTimeout);
  return discoveries.first;
}

Future<void> _exerciseOverlappingConnect(BluetoothDevice device) async {
  final primaryConnect = device.connect();
  final overlappingConnect = device.connect().then<_OperationResult>(
    (_) => const _OperationResult.completed(),
    onError: (Object error, StackTrace _) => _OperationResult.failed(error),
  );

  final overlapping = await overlappingConnect.timeout(_operationTimeout);
  expect(
    overlapping.error,
    isA<QuickBlueException>()
        .having((error) => error.code, 'code', QuickBlueErrorCode.invalidState)
        .having((error) => error.operation, 'operation', 'connect')
        .having((error) => error.deviceId, 'deviceId', device.deviceId),
  );
  await primaryConnect.timeout(_operationTimeout);
  await device.disconnect().timeout(_operationTimeout);
}

Future<void> _exerciseConnectDisconnectRace(BluetoothDevice device) async {
  final connectResult = device.connect().then<_OperationResult>(
    (_) => const _OperationResult.completed(),
    onError: (Object error, StackTrace _) => _OperationResult.failed(error),
  );
  await Future<void>.delayed(const Duration(milliseconds: 1));
  await device.disconnect().timeout(_operationTimeout);

  final connect = await connectResult.timeout(_operationTimeout);
  if (connect.error != null) {
    expect(
      connect.error,
      isA<QuickBlueException>()
          .having((error) => error.code, 'code', QuickBlueErrorCode.cancelled)
          .having((error) => error.operation, 'operation', 'connect')
          .having((error) => error.deviceId, 'deviceId', device.deviceId),
    );
  }

  await _exerciseCleanLifecycle(device);
}

Future<_DiscoveryRaceOutcome> _exerciseDiscoveryDisconnectRace(
  BluetoothDevice device,
) async {
  await device.connect().timeout(_operationTimeout);
  final discoveryOutcome = device.discoverServices().then<_DiscoveryResult>(
    _DiscoveryResult.completed,
    onError: (Object error, StackTrace stackTrace) =>
        _DiscoveryResult.failed(error, stackTrace),
  );

  await device.disconnect().timeout(_operationTimeout);
  final discovery = await discoveryOutcome.timeout(_operationTimeout);
  final outcome = switch (discovery.error) {
    null => _DiscoveryRaceOutcome.completedBeforeDisconnect,
    final QuickBlueException error
        when error.code == QuickBlueErrorCode.cancelled =>
      _DiscoveryRaceOutcome.cancelled,
    final Object error => Error.throwWithStackTrace(
      error,
      discovery.stackTrace!,
    ),
  };

  await device.connect().timeout(_operationTimeout);
  final services = await device.discoverServices().timeout(_operationTimeout);
  expect(services, isNotEmpty);
  await _readFirstReadable(device, services);
  await device.disconnect().timeout(_operationTimeout);
  return outcome;
}

Future<void> _exerciseTwoDeviceIsolation(
  BluetoothDevice first,
  BluetoothDevice second,
) async {
  await Future.wait(<Future<void>>[
    first.connect(),
    second.connect(),
  ]).timeout(_operationTimeout);

  final services = await Future.wait(<Future<List<BluetoothService>>>[
    first.discoverServices(),
    second.discoverServices(),
  ]).timeout(_operationTimeout);
  expect(services.first, isNotEmpty);
  expect(services.last, isNotEmpty);
  await Future.wait(<Future<void>>[
    _readFirstReadable(first, services.first),
    _readFirstReadable(second, services.last),
  ]).timeout(_operationTimeout);

  await first.disconnect().timeout(_operationTimeout);
  await _readFirstReadable(second, services.last).timeout(_operationTimeout);

  await first.connect().timeout(_operationTimeout);
  final rediscovered = await first.discoverServices().timeout(
    _operationTimeout,
  );
  expect(rediscovered, isNotEmpty);
  await _readFirstReadable(first, rediscovered);
  await _readFirstReadable(second, services.last);

  await Future.wait(<Future<void>>[
    first.disconnect(),
    second.disconnect(),
  ]).timeout(_operationTimeout);
}

Future<void> _readFirstReadable(
  BluetoothDevice device,
  List<BluetoothService> services,
) async {
  for (final service in services) {
    for (final characteristic in service.characteristicDetails) {
      if (characteristic.canRead) {
        await device
            .readValue(service.uuid, characteristic.uuid)
            .timeout(_operationTimeout);
        return;
      }
    }
  }
  fail('No readable characteristic was discovered for ${device.deviceId}.');
}

Future<_StressTargets> _scanForTargets() async {
  final firstPattern = RegExp(_firstNamePattern, caseSensitive: false);
  final secondPattern = _secondNamePattern.isEmpty
      ? null
      : RegExp(_secondNamePattern, caseSensitive: false);
  BlueScanResult? first;
  BlueScanResult? second;
  final seen = <String, BlueScanResult>{};
  final errors = <Object>[];

  final subscription = QuickBlue.scanResults().listen((result) {
    seen[result.deviceId] = result;
    if (first == null && firstPattern.hasMatch(result.name)) {
      first = result;
    }
    if (secondPattern != null &&
        second == null &&
        secondPattern.hasMatch(result.name) &&
        result.deviceId != first?.deviceId) {
      second = result;
    }
  }, onError: errors.add);

  final deadline = DateTime.now().add(
    Duration(seconds: _positive(_scanSeconds, 15)),
  );
  while (DateTime.now().isBefore(deadline) &&
      (first == null || (secondPattern != null && second == null))) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  await subscription.cancel();

  if (errors.isNotEmpty) {
    throw StateError('BLE scan failed: ${errors.first}');
  }
  if (first == null || (secondPattern != null && second == null)) {
    final advertisements = seen.values.map(_describeScanResult).join('\n');
    fail(
      'Could not find the required BLE lifecycle stress target(s).\n'
      'First pattern: $_firstNamePattern\n'
      'Second pattern: '
      '${secondPattern == null ? '<not configured>' : _secondNamePattern}\n'
      'Seen advertisements:\n$advertisements',
    );
  }

  return _StressTargets(first: first!, second: second);
}

Future<bool> _waitForBluetoothAvailable() async {
  final deadline = DateTime.now().add(
    Duration(seconds: _positive(_bluetoothReadyTimeoutSeconds, 8)),
  );
  do {
    if (await QuickBlue.isBluetoothAvailable()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));
  return false;
}

Future<void> _bestEffortDisconnect(BluetoothDevice device) async {
  try {
    await device.disconnect().timeout(const Duration(seconds: 5));
  } catch (_) {
    // The stress flow may have already disconnected the target.
  }
}

Duration get _operationTimeout =>
    Duration(seconds: _positive(_operationTimeoutSeconds, 15));

int _positive(int value, int fallback) => value > 0 ? value : fallback;

String _describeScanResult(BlueScanResult result) {
  final name = result.name.trim().isEmpty ? '<unnamed>' : result.name.trim();
  return '$name (${result.deviceId}, RSSI ${result.rssi})';
}

enum _DiscoveryRaceOutcome { completedBeforeDisconnect, cancelled }

class _DiscoveryResult {
  const _DiscoveryResult.completed(List<BluetoothService> services)
    : error = null,
      stackTrace = null;

  const _DiscoveryResult.failed(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;
}

class _OperationResult {
  const _OperationResult.completed() : error = null;

  const _OperationResult.failed(this.error);

  final Object? error;
}

class _StressTargets {
  const _StressTargets({required this.first, required this.second});

  final BlueScanResult first;
  final BlueScanResult? second;
}
