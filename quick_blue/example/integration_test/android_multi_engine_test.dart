import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_example/multi_engine_worker.dart';

const _controlChannel = MethodChannel(
  'quick_blue.example/multi_engine_control',
);
const _deviceId = String.fromEnvironment('QUICK_BLUE_MULTI_ENGINE_DEVICE_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two Android engines share one native GATT connection', (
    _,
  ) async {
    if (_deviceId.isEmpty) {
      fail(
        'Set QUICK_BLUE_MULTI_ENGINE_DEVICE_ID to a connectable BLE device.',
      );
    }
    expect(multiEngineWorkerEntrypointReference, isA<Function>());
    if (!await QuickBlue.isBluetoothAvailable()) {
      fail('Bluetooth is unavailable or permission was denied.');
    }

    final primaryDevice = QuickBlue.device(_deviceId);
    await primaryDevice.connect().timeout(const Duration(seconds: 15));
    try {
      await _controlChannel
          .invokeMethod<void>('startSecondary')
          .timeout(const Duration(seconds: 10));
      await _callWorker<void>('connect');

      final discoveries = await Future.wait<Object?>([
        primaryDevice.discoverServices().timeout(const Duration(seconds: 15)),
        _callWorker<int>('discoverServices'),
      ]);
      expect(discoveries[0] as List<BluetoothService>, isNotEmpty);
      expect(discoveries[1] as int?, greaterThan(0));

      await _callWorker<void>('disconnect');

      final primaryServices = await primaryDevice.discoverServices().timeout(
        const Duration(seconds: 15),
      );
      expect(primaryServices, isNotEmpty);
    } finally {
      await _controlChannel.invokeMethod<void>('stopSecondary');
      await primaryDevice.disconnect().timeout(const Duration(seconds: 10));
    }
  });
}

Future<T?> _callWorker<T>(String method) {
  return _controlChannel
      .invokeMethod<T>('callSecondary', {
        'method': method,
        'arguments': {'deviceId': _deviceId},
      })
      .timeout(const Duration(seconds: 20));
}
