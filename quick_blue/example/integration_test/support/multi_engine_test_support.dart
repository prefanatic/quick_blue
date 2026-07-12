import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_example/multi_engine_worker.dart';

const _controlChannel = MethodChannel(
  'quick_blue.example/multi_engine_control',
);

Future<void> runMultiEngineConnectionScenario({
  required String targetDescription,
  required String deviceId,
  Future<void> Function()? preparePrimaryConnection,
}) async {
  if (deviceId.isEmpty) {
    fail(
      'Set QUICK_BLUE_MULTI_ENGINE_DEVICE_ID to a connectable '
      '$targetDescription.',
    );
  }
  expect(multiEngineWorkerEntrypointReference, isA<Function>());
  if (!await _waitForBluetooth()) {
    fail('Bluetooth is unavailable or permission was denied.');
  }
  await preparePrimaryConnection?.call();

  final primaryDevice = QuickBlue.device(deviceId);
  await primaryDevice.connect().timeout(const Duration(seconds: 15));
  var secondaryStarted = false;
  try {
    await startSecondaryEngine();
    secondaryStarted = true;
    await _callWorker<void>('connect', deviceId);

    await _expectConcurrentDiscovery(primaryDevice, deviceId);

    // An explicit secondary disconnect must leave the primary attached.
    await _callWorker<void>('disconnect', deviceId);
    await _expectPrimaryConnectionUsable(primaryDevice);

    // Reattach, then destroy the engine without an explicit disconnect. This
    // matches background-task and foreground-service engine shutdown.
    await _callWorker<void>('connect', deviceId);
    expect(
      await _callWorker<int>('discoverServices', deviceId),
      greaterThan(0),
    );
    await stopSecondaryEngine();
    secondaryStarted = false;

    await _expectPrimaryConnectionUsable(primaryDevice);
  } finally {
    try {
      if (secondaryStarted) {
        await stopSecondaryEngine();
      }
    } finally {
      await primaryDevice.disconnect().timeout(const Duration(seconds: 10));
    }
  }
}

Future<void> startSecondaryEngine() {
  return _controlChannel
      .invokeMethod<void>('startSecondary')
      .timeout(const Duration(seconds: 10));
}

Future<void> stopSecondaryEngine() {
  return _controlChannel
      .invokeMethod<void>('stopSecondary')
      .timeout(const Duration(seconds: 10));
}

Future<void> _expectConcurrentDiscovery(
  BluetoothDevice primaryDevice,
  String deviceId,
) async {
  final discoveries = await Future.wait<Object?>([
    primaryDevice.discoverServices().timeout(const Duration(seconds: 15)),
    _callWorker<int>('discoverServices', deviceId),
  ]);
  expect(discoveries[0] as List<BluetoothService>, isNotEmpty);
  expect(discoveries[1] as int?, greaterThan(0));
}

Future<void> _expectPrimaryConnectionUsable(
  BluetoothDevice primaryDevice,
) async {
  final services = await primaryDevice.discoverServices().timeout(
    const Duration(seconds: 15),
  );
  expect(services, isNotEmpty);
}

Future<bool> _waitForBluetooth() async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  do {
    if (await QuickBlue.isBluetoothAvailable()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));
  return false;
}

Future<T?> _callWorker<T>(String method, String deviceId) {
  return _controlChannel
      .invokeMethod<T>('callSecondary', {
        'method': method,
        'arguments': {'deviceId': deviceId},
      })
      .timeout(const Duration(seconds: 20));
}
