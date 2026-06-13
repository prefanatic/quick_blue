import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_example/src/ble_explorer_controller.dart';

const _scanSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_SCAN_SECONDS',
  defaultValue: 15,
);
const _connectTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_CONNECT_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _secondConnectTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_SECOND_CONNECT_TIMEOUT_SECONDS',
  defaultValue: 12,
);
const _switchDelayMilliseconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_DELAY_MILLISECONDS',
  defaultValue: 600,
);
const _bluetoothReadyTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_BLUETOOTH_READY_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _firstNamePattern = String.fromEnvironment(
  'QUICK_BLUE_SWITCH_FIRST_NAME_PATTERN',
  defaultValue: 'govee',
);
const _secondNamePattern = String.fromEnvironment(
  'QUICK_BLUE_SWITCH_SECOND_NAME_PATTERN',
  defaultValue: 'nest\\s*hub|nesthub',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'switches devices while the first connection is still pending',
    (_) async {
      if (defaultTargetPlatform != TargetPlatform.macOS) {
        markTestSkipped(
          'This switch regression targets the macOS CoreBluetooth path.',
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

      final targets = await _scanForSwitchTargets();
      final first = targets.first;
      final second = targets.second;

      final controller = BleExplorerController(
        connectTimeout: _seconds(_connectTimeoutSeconds, 8),
      );
      addTearDown(controller.dispose);
      await controller.initialBluetoothCheck;
      controller.devices[first.deviceId] = first;
      controller.devices[second.deviceId] = second;

      await controller.selectDevice(first.deviceId);
      final firstConnect = controller.connectSelected().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'quick_blue_example_test',
            context: ErrorDescription('while connecting first BLE target'),
          ),
        );
      });

      await Future<void>.delayed(
        Duration(milliseconds: _positive(_switchDelayMilliseconds, 600)),
      );
      await controller.selectDevice(second.deviceId);
      await controller.connectSelected().timeout(
        _seconds(_secondConnectTimeoutSeconds, 12),
      );

      expect(controller.selectedDeviceId, second.deviceId);
      expect(controller.connecting, isFalse);
      expect(controller.connectionState, BlueConnectionState.connected);

      await _bestEffortDisconnect(QuickBlue.device(second.deviceId));
      await firstConnect;
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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

Future<_SwitchTargets> _scanForSwitchTargets() async {
  BlueScanResult? first;
  BlueScanResult? second;
  final firstPattern = RegExp(_firstNamePattern, caseSensitive: false);
  final secondPattern = RegExp(_secondNamePattern, caseSensitive: false);
  final seen = <String, BlueScanResult>{};
  final errors = <Object>[];

  final subscription = QuickBlue.scanResults().listen((result) {
    seen[result.deviceId] = result;
    if (firstPattern.hasMatch(result.name)) {
      first ??= result;
    }
    if (secondPattern.hasMatch(result.name)) {
      second ??= result;
    }
  }, onError: errors.add);

  final deadline = DateTime.now().add(_seconds(_scanSeconds, 15));
  while (DateTime.now().isBefore(deadline) &&
      (first == null || second == null)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  await subscription.cancel();

  if (errors.isNotEmpty) {
    throw StateError('BLE scan failed: ${errors.first}');
  }
  if (first == null || second == null) {
    final advertised = seen.values.map(_describeScanResult).join('\n');
    fail(
      'Could not find both BLE switch targets.\n'
      'First pattern: $_firstNamePattern\n'
      'Second pattern: $_secondNamePattern\n'
      'Seen advertisements:\n$advertised',
    );
  }

  return _SwitchTargets(first: first!, second: second!);
}

Future<void> _bestEffortDisconnect(BluetoothDevice device) async {
  try {
    await device.disconnect().timeout(const Duration(seconds: 5));
  } catch (_) {
    // The target may already have dropped or may never have connected.
  }
}

Duration _seconds(int value, int fallback) {
  return Duration(seconds: _positive(value, fallback));
}

int _positive(int value, int fallback) {
  return value > 0 ? value : fallback;
}

String _describeScanResult(BlueScanResult result) {
  final name = result.name.trim().isEmpty ? '<unnamed>' : result.name.trim();
  return '$name (${result.deviceId}, RSSI ${result.rssi})';
}

class _SwitchTargets {
  const _SwitchTargets({required this.first, required this.second});

  final BlueScanResult first;
  final BlueScanResult second;
}
