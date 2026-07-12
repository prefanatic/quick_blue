import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';

import 'support/multi_engine_test_support.dart';

const _deviceId = String.fromEnvironment('QUICK_BLUE_MULTI_ENGINE_DEVICE_ID');
const _serviceId = String.fromEnvironment(
  'QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID',
);
const _characteristicId = String.fromEnvironment(
  'QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS starts and stops a headless secondary Flutter engine', (
    _,
  ) async {
    await startSecondaryEngine();
    await stopSecondaryEngine();
  });

  testWidgets('two iOS engines share one CoreBluetooth connection', (_) async {
    await runMultiEngineConnectionScenario(
      targetDescription: 'BLE device UUID',
      deviceId: _deviceId,
      preparePrimaryConnection: () async {
        await QuickBlue.scanResults()
            .firstWhere(
              (result) =>
                  result.deviceId.toLowerCase() == _deviceId.toLowerCase(),
            )
            .timeout(const Duration(seconds: 15));
      },
    );
  });

  testWidgets(
    'foreground stays connected after the CoreBluetooth host engine stops',
    (_) async {
      await _requireBluetoothTarget();
      await _primeKnownPeripheral();

      final foregroundDevice = QuickBlue.device(_deviceId);
      var secondaryStarted = false;
      var foregroundConnected = false;
      try {
        await startSecondaryEngine();
        secondaryStarted = true;
        // The secondary engine has not scanned or called connectedDevices().
        // Its stable UUID must resolve directly through CoreBluetooth.
        await callMultiEngineWorker<void>('connect', _deviceId);
        await foregroundDevice.connect().timeout(const Duration(seconds: 15));
        foregroundConnected = true;

        await stopSecondaryEngine();
        secondaryStarted = false;

        expect(
          await foregroundDevice.discoverServices().timeout(
            const Duration(seconds: 15),
          ),
          isNotEmpty,
        );
      } finally {
        if (secondaryStarted) {
          await stopSecondaryEngine();
        }
        if (foregroundConnected) {
          await foregroundDevice.disconnect().timeout(
            const Duration(seconds: 10),
          );
        }
      }
    },
  );

  testWidgets(
    'foreground can attach while the background engine is shutting down',
    (_) async {
      await _requireBluetoothTarget();
      await _primeKnownPeripheral();

      final foregroundDevice = QuickBlue.device(_deviceId);
      var secondaryStarted = false;
      var foregroundConnected = false;
      try {
        await startSecondaryEngine();
        secondaryStarted = true;
        await callMultiEngineWorker<void>('connect', _deviceId);

        await Future.wait<void>([
          stopSecondaryEngine().then((_) => secondaryStarted = false),
          foregroundDevice.connect().then((_) => foregroundConnected = true),
        ]).timeout(const Duration(seconds: 20));

        expect(
          await foregroundDevice.discoverServices().timeout(
            const Duration(seconds: 15),
          ),
          isNotEmpty,
        );
      } finally {
        if (secondaryStarted) {
          await stopSecondaryEngine();
        }
        if (foregroundConnected) {
          await foregroundDevice.disconnect().timeout(
            const Duration(seconds: 10),
          );
        }
      }
    },
  );

  testWidgets(
    'notification ownership transfers before the old engine detaches',
    (_) async {
      await _requireBluetoothTarget(requireCharacteristic: true);
      await _primeKnownPeripheral();

      final foregroundDevice = QuickBlue.device(_deviceId);
      final characteristic = foregroundDevice.characteristic(
        _serviceId,
        _characteristicId,
      );
      var secondaryStarted = false;
      var foregroundConnected = false;
      var secondaryConnected = false;
      var foregroundClaimed = false;
      var secondaryClaimed = false;
      try {
        await foregroundDevice.connect().timeout(const Duration(seconds: 15));
        foregroundConnected = true;
        await startSecondaryEngine();
        secondaryStarted = true;
        await callMultiEngineWorker<void>('connect', _deviceId);
        secondaryConnected = true;

        await Future.wait<Object?>([
          foregroundDevice.discoverServices(),
          callMultiEngineWorker<int>('discoverServices', _deviceId),
        ]).timeout(const Duration(seconds: 15));

        await characteristic.setNotifiable(BleInputProperty.notification);
        foregroundClaimed = true;
        await callMultiEngineWorker<void>(
          'setNotifiable',
          _deviceId,
          arguments: const <String, Object?>{
            'serviceId': _serviceId,
            'characteristicId': _characteristicId,
            'property': 'notification',
          },
        );
        secondaryClaimed = true;

        // Releasing the original claim must not disable the secondary claim.
        await characteristic.setNotifiable(BleInputProperty.disabled);
        foregroundClaimed = false;
        await foregroundDevice.disconnect().timeout(
          const Duration(seconds: 10),
        );
        foregroundConnected = false;

        expect(
          await callMultiEngineWorker<int>('discoverServices', _deviceId),
          greaterThan(0),
        );
      } finally {
        if (foregroundClaimed) {
          await characteristic.setNotifiable(BleInputProperty.disabled);
        }
        if (secondaryClaimed) {
          await callMultiEngineWorker<void>(
            'setNotifiable',
            _deviceId,
            arguments: const <String, Object?>{
              'serviceId': _serviceId,
              'characteristicId': _characteristicId,
              'property': 'disabled',
            },
          );
        }
        if (secondaryConnected) {
          await callMultiEngineWorker<void>('disconnect', _deviceId);
        }
        if (secondaryStarted) {
          await stopSecondaryEngine();
        }
        if (foregroundConnected) {
          await foregroundDevice.disconnect().timeout(
            const Duration(seconds: 10),
          );
        }
      }
    },
  );
}

Future<void> _requireBluetoothTarget({
  bool requireCharacteristic = false,
}) async {
  if (_deviceId.isEmpty) {
    fail(
      'Set QUICK_BLUE_MULTI_ENGINE_DEVICE_ID to a connectable BLE device UUID.',
    );
  }
  if (requireCharacteristic &&
      (_serviceId.isEmpty || _characteristicId.isEmpty)) {
    fail(
      'Set QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID and '
      'QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID to a notifiable target.',
    );
  }

  final deadline = DateTime.now().add(const Duration(seconds: 8));
  do {
    if (await QuickBlue.isBluetoothAvailable()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));
  fail('Bluetooth is unavailable or permission was denied.');
}

Future<void> _primeKnownPeripheral() async {
  await QuickBlue.scanResults()
      .firstWhere(
        (result) => result.deviceId.toLowerCase() == _deviceId.toLowerCase(),
      )
      .timeout(const Duration(seconds: 15));
}
